import { describe, expect, it } from 'vitest';
import type { pdfjs } from 'react-pdf';
import { searchDocument } from './pdfSearch';

// Builds a minimal stand-in for a pdf.js document whose pages return the given
// text. searchDocument only touches numPages, getPage and getTextContent.
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
});
