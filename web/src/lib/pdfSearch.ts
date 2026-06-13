// In-document full-text search over a pdf.js document. Pulls the text content
// of each page on demand and returns matches with a context snippet so the
// reader can list results and jump to a page.
import type { pdfjs } from 'react-pdf';

export interface SearchMatch {
  pageNumber: number;
  snippet: string;
  matchIndex: number; // offset of the match start within the page text
}

// Hard cap so a pathological query ("e") on a huge PDF can't lock up the tab.
const MAX_MATCHES = 200;
const SNIPPET_CONTEXT = 40; // characters of context on each side of a match

interface TextItemLike {
  str?: string;
}

function buildSnippet(text: string, index: number, queryLength: number): string {
  const start = Math.max(0, index - SNIPPET_CONTEXT);
  const end = Math.min(text.length, index + queryLength + SNIPPET_CONTEXT);
  const prefix = start > 0 ? '…' : '';
  const suffix = end < text.length ? '…' : '';
  return `${prefix}${text.slice(start, end).trim()}${suffix}`;
}

/**
 * Searches every page for `query` (case-insensitive) and returns matches in
 * page order. Capped at MAX_MATCHES; `capped` signals truncation so the UI can
 * say so rather than implying full coverage.
 */
export async function searchDocument(
  pdf: pdfjs.PDFDocumentProxy,
  query: string
): Promise<{ matches: SearchMatch[]; capped: boolean }> {
  const trimmed = query.trim();
  if (trimmed.length < 2) return { matches: [], capped: false };

  const needle = trimmed.toLocaleLowerCase('tr');
  const matches: SearchMatch[] = [];
  let capped = false;

  for (let pageNum = 1; pageNum <= pdf.numPages; pageNum++) {
    const page = await pdf.getPage(pageNum);
    const textContent = await page.getTextContent();
    const pageText = (textContent.items as TextItemLike[])
      .map(item => item.str ?? '')
      .join(' ')
      .replace(/\s+/g, ' ');
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
    if (capped) break;
  }

  return { matches, capped };
}
