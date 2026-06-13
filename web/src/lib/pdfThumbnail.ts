// Renders the first page of a PDF to a small PNG thumbnail at upload time.
// Storing this on the file row lets the library grid skip downloading the
// full PDF per card (Phase B perf — P2).
'use client';

// Target render width — large enough to stay crisp on a 3:4 grid card,
// small enough that the resulting base64 stays in the tens of KB.
const THUMBNAIL_WIDTH = 220;

/**
 * Produce a base64-encoded PNG (no data: prefix) of the PDF's first page.
 * Returns null on any failure so the upload can proceed without a thumbnail —
 * the live-download fallback in PDFThumbnail still works for those rows.
 *
 * pdf.js is imported lazily inside the function: it touches browser-only
 * globals (DOMMatrix) at module evaluation, so a static top-level import would
 * pull it into the server bundle and break prerendering of any page that uses
 * this util (e.g. the upload flow on /library).
 */
export async function generatePdfThumbnail(file: Blob): Promise<string | null> {
    try {
        const { pdfjs } = await import('react-pdf');
        await import('@/lib/pdfjs-config'); // Ensure the worker is configured

        const buffer = await file.arrayBuffer();
        const pdf = await pdfjs.getDocument({ data: new Uint8Array(buffer) }).promise;
        const page = await pdf.getPage(1);

        const baseViewport = page.getViewport({ scale: 1 });
        const scale = THUMBNAIL_WIDTH / baseViewport.width;
        const viewport = page.getViewport({ scale });

        const canvas = document.createElement('canvas');
        canvas.width = Math.ceil(viewport.width);
        canvas.height = Math.ceil(viewport.height);
        const context = canvas.getContext('2d');
        if (!context) {
            await pdf.destroy();
            return null;
        }

        await page.render({ canvas, canvasContext: context, viewport }).promise;

        const dataUrl = canvas.toDataURL('image/png');
        await pdf.destroy();

        // Strip the "data:image/png;base64," prefix — PDFThumbnail re-adds it,
        // matching the iOS-generated thumbnail convention.
        return dataUrl.split(',')[1] ?? null;
    } catch {
        return null;
    }
}
