// Detects whether a PDF page is "scanned" (image-only, no usable text layer).
// On such pages text selection never fires, so the reader shows an OCR
// affordance instead. Verdicts are cached per document+page — getTextContent
// is not free and the answer never changes for a given document.
"use client";

import { useEffect, useRef, useState } from "react";
import type { pdfjs } from "react-pdf";

interface DetectedState {
  doc: pdfjs.PDFDocumentProxy | null;
  scannedPages: Set<number>;
}

export function useScannedPageDetection(
  pdf: pdfjs.PDFDocumentProxy | null,
  pageNumber: number
): boolean {
  // State carries the document it belongs to, so a document switch implicitly
  // invalidates old verdicts without needing a synchronous reset in an effect.
  const [detected, setDetected] = useState<DetectedState>({
    doc: null,
    scannedPages: new Set(),
  });
  // Pages whose detection already started for the current document — dedupes
  // repeat visits to the same page (results arrive via setDetected).
  const startedRef = useRef<{ doc: pdfjs.PDFDocumentProxy | null; pages: Set<number> }>({
    doc: null,
    pages: new Set(),
  });

  useEffect(() => {
    if (!pdf || pageNumber < 1 || pageNumber > pdf.numPages) return;

    if (startedRef.current.doc !== pdf) {
      startedRef.current = { doc: pdf, pages: new Set() };
    }
    if (startedRef.current.pages.has(pageNumber)) return;
    startedRef.current.pages.add(pageNumber);

    (async () => {
      try {
        const page = await pdf.getPage(pageNumber);
        const content = await page.getTextContent();
        const hasText = content.items.some(
          item => "str" in item && typeof item.str === "string" && item.str.trim().length > 0
        );
        if (!hasText) {
          setDetected(prev => {
            const scannedPages = prev.doc === pdf ? new Set(prev.scannedPages) : new Set<number>();
            scannedPages.add(pageNumber);
            return { doc: pdf, scannedPages };
          });
        }
      } catch {
        // Detection failure just means no OCR affordance — never an error UI.
      }
    })();
  }, [pdf, pageNumber]);

  return detected.doc === pdf && detected.scannedPages.has(pageNumber);
}
