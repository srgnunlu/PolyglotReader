// In-document full-text search over a pdf.js document. Pulls the text content
// of each page on demand and returns matches with a context snippet so the
// reader can list results and jump to a page. Pages are scanned in small
// batches with event-loop yields in between so a 200-page PDF never freezes
// the UI, and a superseded search can be cancelled via AbortSignal.
import type { pdfjs } from 'react-pdf';
import { assembleReadingOrderText, type PositionedText } from './textGeometry';

export interface SearchMatch {
  pageNumber: number;
  snippet: string;
  matchIndex: number; // offset of the match start within the page text
}

export interface SearchProgress {
  pagesScanned: number;
  totalPages: number;
  /** Matches found so far (snapshot — safe to render directly). */
  matches: SearchMatch[];
}

export interface SearchDocumentOptions {
  onProgress?: (progress: SearchProgress) => void;
  signal?: AbortSignal;
}

// Hard cap so a pathological query ("e") on a huge PDF can't lock up the tab.
const MAX_MATCHES = 200;
const SNIPPET_CONTEXT = 40; // characters of context on each side of a match
const PAGE_BATCH_SIZE = 8; // pages scanned between event-loop yields

interface TextItemLike {
  str?: string;
  transform?: number[];
  width?: number;
  height?: number;
}

function buildSnippet(text: string, index: number, queryLength: number): string {
  const start = Math.max(0, index - SNIPPET_CONTEXT);
  const end = Math.min(text.length, index + queryLength + SNIPPET_CONTEXT);
  const prefix = start > 0 ? '…' : '';
  const suffix = end < text.length ? '…' : '';
  return `${prefix}${text.slice(start, end).trim()}${suffix}`;
}

function throwIfAborted(signal?: AbortSignal): void {
  if (signal?.aborted) {
    throw new DOMException('Search aborted', 'AbortError');
  }
}

async function yieldToEventLoop(): Promise<void> {
  // scheduler.yield (Chrome 129+) resumes with higher priority than a timer;
  // fall back to a macrotask elsewhere.
  const scheduler = (globalThis as { scheduler?: { yield?: () => Promise<void> } }).scheduler;
  if (scheduler?.yield) {
    await scheduler.yield();
    return;
  }
  await new Promise<void>(resolve => setTimeout(resolve, 0));
}

/**
 * Builds a page's searchable text. When items carry geometry (real pdf.js
 * output), they are reassembled in column-aware reading order with hyphenated
 * line breaks merged — on 2-column PDFs the raw item order interleaves the
 * columns and phrases spanning a line break would never match. Items without
 * geometry (defensive) fall back to the plain join.
 */
function pageTextFromItems(items: TextItemLike[], pageWidth: number): string {
  const positioned: PositionedText[] = [];
  let allPositioned = true;
  for (const item of items) {
    const transform = item.transform;
    if (!transform || transform.length < 6) {
      allPositioned = false;
      break;
    }
    positioned.push({
      text: item.str ?? '',
      left: transform[4],
      // PDF-space y grows upward; reading order wants top-down.
      top: -transform[5],
      height: item.height || Math.abs(transform[3]) || 1,
      right: item.width !== undefined ? transform[4] + item.width : undefined,
    });
  }

  if (allPositioned && positioned.length > 0) {
    return assembleReadingOrderText(positioned, pageWidth);
  }
  return items
    .map(item => item.str ?? '')
    .join(' ')
    .replace(/\s+/g, ' ');
}

/**
 * Searches every page for `query` (case-insensitive) and returns matches in
 * page order. Capped at MAX_MATCHES; `capped` signals truncation so the UI can
 * say so rather than implying full coverage. Yields to the event loop between
 * page batches, reporting partial results via `onProgress`; rejects with an
 * AbortError when `signal` is aborted.
 */
export async function searchDocument(
  pdf: pdfjs.PDFDocumentProxy,
  query: string,
  options: SearchDocumentOptions = {}
): Promise<{ matches: SearchMatch[]; capped: boolean }> {
  const { onProgress, signal } = options;
  const trimmed = query.trim();
  if (trimmed.length < 2) return { matches: [], capped: false };

  const needle = trimmed.toLocaleLowerCase('tr');
  const matches: SearchMatch[] = [];
  let capped = false;
  let pagesScanned = 0;

  throwIfAborted(signal);

  for (let pageNum = 1; pageNum <= pdf.numPages; pageNum++) {
    if (pageNum > 1 && (pageNum - 1) % PAGE_BATCH_SIZE === 0) {
      onProgress?.({ pagesScanned, totalPages: pdf.numPages, matches: matches.slice() });
      await yieldToEventLoop();
      throwIfAborted(signal);
    }

    const page = await pdf.getPage(pageNum);
    throwIfAborted(signal);
    const textContent = await page.getTextContent();
    throwIfAborted(signal);

    // Test doubles may omit getViewport; A4 width is a harmless default since
    // the width only calibrates the column-gutter threshold.
    const getViewport = (page as { getViewport?: (params: { scale: number }) => { width: number } }).getViewport;
    const pageWidth = typeof getViewport === 'function'
      ? getViewport.call(page, { scale: 1 }).width
      : 595;

    const pageText = pageTextFromItems(textContent.items as TextItemLike[], pageWidth);
    const haystack = pageText.toLocaleLowerCase('tr');

    let from = 0;
    let index = haystack.indexOf(needle, from);
    while (index !== -1) {
      matches.push({
        pageNumber: pageNum,
        snippet: buildSnippet(pageText, index, trimmed.length),
        matchIndex: index,
      });
      if (matches.length >= MAX_MATCHES) {
        capped = true;
        break;
      }
      from = index + needle.length;
      index = haystack.indexOf(needle, from);
    }
    pagesScanned = pageNum;
    if (capped) break;
  }

  onProgress?.({ pagesScanned, totalPages: pdf.numPages, matches: matches.slice() });
  return { matches, capped };
}
