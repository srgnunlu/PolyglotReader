import { describe, expect, it, vi } from 'vitest';
import type { pdfjs } from 'react-pdf';
import { searchDocument, type SearchProgress } from './pdfSearch';

// Builds a minimal stand-in for a pdf.js document whose pages return the given
// text. searchDocument only touches numPages, getPage and getTextContent.
// Items carry no geometry, exercising the plain-join fallback path.
function fakePdf(pages: string[]): pdfjs.PDFDocumentProxy {
  return {
    numPages: pages.length,
    getPage: async (pageNum: number) => ({
      getTextContent: async () => ({
        items: pages[pageNum - 1].split(' ').map(str => ({ str })),
      }),
    }),
  } as unknown as pdfjs.PDFDocumentProxy;
}

interface PositionedItem {
  str: string;
  x: number;
  y: number;
  size?: number;
}

const PAGE_WIDTH = 595;

// Stand-in whose items carry pdf.js-style geometry (transform/width/height),
// exercising the column-aware reading-order path.
function fakePositionedPdf(pages: PositionedItem[][]): pdfjs.PDFDocumentProxy {
  return {
    numPages: pages.length,
    getPage: async (pageNum: number) => ({
      getViewport: () => ({ width: PAGE_WIDTH }),
      getTextContent: async () => ({
        items: pages[pageNum - 1].map(({ str, x, y, size = 12 }) => ({
          str,
          transform: [size, 0, 0, size, x, y],
          width: str.length * 6,
          height: size,
        })),
      }),
    }),
  } as unknown as pdfjs.PDFDocumentProxy;
}

describe('searchDocument', () => {
  it('returns no matches for queries shorter than 2 chars', async () => {
    const result = await searchDocument(fakePdf(['hello world']), 'a');
    expect(result.matches).toEqual([]);
    expect(result.capped).toBe(false);
  });

  it('finds a match and reports its page', async () => {
    const result = await searchDocument(
      fakePdf(['the quick brown fox', 'jumps over the lazy dog']),
      'lazy'
    );
    expect(result.matches).toHaveLength(1);
    expect(result.matches[0].pageNumber).toBe(2);
    expect(result.matches[0].snippet).toContain('lazy');
  });

  it('is case-insensitive', async () => {
    const result = await searchDocument(fakePdf(['Travma Tahtası kullanımı']), 'travma');
    expect(result.matches).toHaveLength(1);
    expect(result.matches[0].pageNumber).toBe(1);
  });

  it('matches Turkish characters', async () => {
    const result = await searchDocument(fakePdf(['Çocuk hastalarda doz']), 'çocuk');
    expect(result.matches).toHaveLength(1);
  });

  it('finds multiple occurrences across pages in page order', async () => {
    const result = await searchDocument(
      fakePdf(['kalp kalp', 'damar', 'kalp damar']),
      'kalp'
    );
    expect(result.matches).toHaveLength(3);
    expect(result.matches.map(m => m.pageNumber)).toEqual([1, 1, 3]);
  });

  it('returns no matches when the term is absent', async () => {
    const result = await searchDocument(fakePdf(['alpha beta gamma']), 'delta');
    expect(result.matches).toEqual([]);
  });

  it('orders two-column pages column by column, not in item order', async () => {
    // Items arrive interleaved (line 1 of both columns, then line 2 of both),
    // mimicking content-stream order on a 2-column layout.
    const page: PositionedItem[] = [
      { str: 'acil servis', x: 50, y: 700 },
      { str: 'hasta sayısı', x: 320, y: 700 },
      { str: 'triyaj puanı', x: 50, y: 688 },
      { str: 'yatak durumu', x: 320, y: 688 },
    ];
    const pdf = fakePositionedPdf([page]);

    // Phrase spanning column 1's line break only exists in reading order.
    const columnAware = await searchDocument(pdf, 'servis triyaj');
    expect(columnAware.matches).toHaveLength(1);

    // The naive interleaved join would produce "servis hasta" — must be gone.
    const interleaved = await searchDocument(pdf, 'servis hasta');
    expect(interleaved.matches).toEqual([]);
  });

  it('merges hyphenated line breaks so the whole word matches', async () => {
    const page: PositionedItem[] = [
      { str: 'bilgi-', x: 50, y: 700 },
      { str: 'lendirme süreci', x: 50, y: 688 },
    ];
    const result = await searchDocument(fakePositionedPdf([page]), 'bilgilendirme');
    expect(result.matches).toHaveLength(1);
    expect(result.matches[0].snippet).toContain('bilgilendirme süreci');
  });

  it('reports progress and ends with a final full-coverage call', async () => {
    const pages = Array.from({ length: 20 }, (_, i) => `sayfa ${i + 1} kalp içeriği`);
    const calls: SearchProgress[] = [];
    const result = await searchDocument(fakePdf(pages), 'kalp', {
      onProgress: progress => calls.push(progress),
    });

    expect(calls.length).toBeGreaterThanOrEqual(2); // batch yields + final
    const last = calls[calls.length - 1];
    expect(last.pagesScanned).toBe(20);
    expect(last.totalPages).toBe(20);
    expect(last.matches).toHaveLength(result.matches.length);
    // Intermediate calls carry partial results
    expect(calls[0].pagesScanned).toBeLessThan(20);
    expect(calls[0].matches.length).toBeGreaterThan(0);
  });

  it('rejects with AbortError when the signal is already aborted', async () => {
    const controller = new AbortController();
    controller.abort();
    await expect(
      searchDocument(fakePdf(['kalp damar']), 'kalp', { signal: controller.signal })
    ).rejects.toMatchObject({ name: 'AbortError' });
  });

  it('stops scanning when aborted mid-search', async () => {
    const pages = Array.from({ length: 30 }, () => 'kalp damar beyin');
    const controller = new AbortController();
    const getPageSpy = vi.fn();
    const pdf = {
      numPages: pages.length,
      getPage: async (pageNum: number) => {
        getPageSpy(pageNum);
        return {
          getTextContent: async () => ({
            items: pages[pageNum - 1].split(' ').map(str => ({ str })),
          }),
        };
      },
    } as unknown as pdfjs.PDFDocumentProxy;

    await expect(
      searchDocument(pdf, 'kalp', {
        signal: controller.signal,
        onProgress: () => controller.abort(), // abort at the first batch yield
      })
    ).rejects.toMatchObject({ name: 'AbortError' });
    expect(getPageSpy.mock.calls.length).toBeLessThan(30);
  });
});
