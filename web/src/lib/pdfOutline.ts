// Document outline (TOC) extraction from a pdf.js document. The PDF's embedded
// bookmark tree (getOutline) is resolved into flat items with 1-based page
// numbers so the reader can jump straight to a section.
import type { pdfjs } from 'react-pdf';

export interface OutlineItem {
  title: string;
  pageNumber: number | null;
  level: number;
}

// pdf.js outline node shape (only the fields we use).
interface RawOutlineNode {
  title: string;
  dest: string | unknown[] | null;
  items?: RawOutlineNode[];
}

/**
 * Resolves a pdf.js destination (named or explicit) to a 1-based page number.
 * Returns null when the destination can't be resolved.
 */
async function resolveDestinationPage(
  pdf: pdfjs.PDFDocumentProxy,
  dest: string | unknown[] | null
): Promise<number | null> {
  try {
    if (!dest) return null;
    const explicit = typeof dest === 'string' ? await pdf.getDestination(dest) : dest;
    if (!Array.isArray(explicit) || explicit.length === 0) return null;

    const ref = explicit[0];
    if (ref && typeof ref === 'object') {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const pageIndex = await pdf.getPageIndex(ref as any);
      return pageIndex + 1;
    }
    return null;
  } catch {
    return null;
  }
}

/**
 * Reads the PDF's bookmark tree and flattens it into a list of outline items
 * with resolved page numbers. Returns an empty array when the PDF has no
 * embedded outline.
 */
export async function extractOutline(pdf: pdfjs.PDFDocumentProxy): Promise<OutlineItem[]> {
  const raw = (await pdf.getOutline()) as RawOutlineNode[] | null;
  if (!raw || raw.length === 0) return [];

  const result: OutlineItem[] = [];

  const walk = async (nodes: RawOutlineNode[], level: number): Promise<void> => {
    for (const node of nodes) {
      const pageNumber = await resolveDestinationPage(pdf, node.dest);
      result.push({ title: node.title?.trim() || 'Başlıksız', pageNumber, level });
      if (node.items && node.items.length > 0) {
        await walk(node.items, level + 1);
      }
    }
  };

  await walk(raw, 0);
  return result;
}
