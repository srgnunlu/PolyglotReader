// Pulls plain text out of a loaded pdf.js document, page by page, up to a
// character budget. Used by features that need the document's text content
// without going through the RAG chunk pipeline (e.g. quiz generation, which
// must work even before a document has been chunked/embedded).
import type { pdfjs } from 'react-pdf';

interface TextItemLike {
  str?: string;
}

// Mirrors the iOS quiz path, which feeds Gemini the first ~15k characters of
// the document text (GeminiAnalysisService.generateQuiz uses context.prefix(15000)).
const DEFAULT_MAX_CHARS = 15000;

/**
 * Extracts text from `pdf` in page order, stopping once `maxChars` is reached.
 * Returns a whitespace-normalised string. Pages are read sequentially because
 * pdf.js page proxies are cheapest to consume one at a time.
 */
export async function extractPdfText(
  pdf: pdfjs.PDFDocumentProxy,
  maxChars: number = DEFAULT_MAX_CHARS
): Promise<string> {
  const parts: string[] = [];
  let total = 0;

  for (let pageNum = 1; pageNum <= pdf.numPages; pageNum++) {
    const page = await pdf.getPage(pageNum);
    const content = await page.getTextContent();
    const pageText = (content.items as TextItemLike[])
      .map(item => item.str ?? '')
      .join(' ')
      .replace(/\s+/g, ' ')
      .trim();

    if (!pageText) continue;

    parts.push(pageText);
    total += pageText.length;
    if (total >= maxChars) break;
  }

  return parts.join('\n\n').slice(0, maxChars).trim();
}
