// Detects right-clicks on embedded PDF images by walking the page's operator
// list (CTM transforms), crops the image region from the rendered canvas and
// reports it as base64 for AI analysis.
"use client";

import { useCallback, type RefObject } from "react";
import { pdfjs } from "react-pdf";

interface UsePDFImageSelectionOptions {
  pdfUrl: string;
  displayScale: number;
  renderScale: number;
  pdfDocumentRef: RefObject<pdfjs.PDFDocumentProxy | null>;
  containerRef: RefObject<HTMLDivElement | null>;
  onImageSelect?: (
    imageBase64: string,
    pageNumber: number,
    position: { x: number; y: number }
  ) => void;
}

export function usePDFImageSelection({
  pdfUrl,
  displayScale,
  renderScale,
  pdfDocumentRef,
  containerRef,
  onImageSelect,
}: UsePDFImageSelectionOptions) {
  const handleImageContextMenu = useCallback(async (e: React.MouseEvent) => {
    if (e.type !== 'contextmenu') return;
    e.preventDefault();

    if (!onImageSelect || !containerRef.current) return;

    const selection = window.getSelection();
    if (selection && !selection.isCollapsed) return;

    const target = e.target as HTMLElement;
    const pageElement = target.closest('.pdf-page') as HTMLElement;

    if (!pageElement) return;

    const pageNumber = Number(pageElement.getAttribute('data-page-number'));
    if (!pageNumber) return;

    const canvas = pageElement.querySelector('canvas');
    if (!canvas) return;

    try {
      if (!pdfDocumentRef.current) {
        pdfDocumentRef.current = await pdfjs.getDocument(pdfUrl).promise;
      }
      const pdf = pdfDocumentRef.current;
      const page = await pdf.getPage(pageNumber);
      const ops = await page.getOperatorList();

      const pageRect = pageElement.getBoundingClientRect();
      const displayViewport = page.getViewport({ scale: displayScale });
      const renderViewport = page.getViewport({ scale: renderScale });

      const [clickX, clickY] = displayViewport.convertToPdfPoint(
        e.clientX - pageRect.left,
        e.clientY - pageRect.top
      );

      const multiply = (m1: number[], m2: number[]) => {
        return [
          m1[0] * m2[0] + m1[1] * m2[2],
          m1[0] * m2[1] + m1[1] * m2[3],
          m1[2] * m2[0] + m1[3] * m2[2],
          m1[2] * m2[1] + m1[3] * m2[3],
          m1[4] * m2[0] + m1[5] * m2[2] + m2[4],
          m1[4] * m2[1] + m1[5] * m2[3] + m2[5]
        ];
      };

      const transform = (p: { x: number, y: number }, m: number[]) => {
        return {
          x: m[0] * p.x + m[2] * p.y + m[4],
          y: m[1] * p.x + m[3] * p.y + m[5]
        };
      };

      let ctm = [1, 0, 0, 1, 0, 0];
      const ctmStack: number[][] = [];

      for (let i = 0; i < ops.fnArray.length; i++) {
        const fn = ops.fnArray[i];
        const args = ops.argsArray[i];

        if (fn === pdfjs.OPS.save) {
          ctmStack.push([...ctm]);
        } else if (fn === pdfjs.OPS.restore) {
          if (ctmStack.length > 0) {
            ctm = ctmStack.pop()!;
          }
        } else if (fn === pdfjs.OPS.transform) {
          ctm = multiply(args, ctm);
        } else if (fn === pdfjs.OPS.paintImageXObject) {
          const p1 = transform({ x: 0, y: 0 }, ctm);
          const p2 = transform({ x: 1, y: 0 }, ctm);
          const p3 = transform({ x: 1, y: 1 }, ctm);
          const p4 = transform({ x: 0, y: 1 }, ctm);

          const minX = Math.min(p1.x, p2.x, p3.x, p4.x);
          const maxX = Math.max(p1.x, p2.x, p3.x, p4.x);
          const minY = Math.min(p1.y, p2.y, p3.y, p4.y);
          const maxY = Math.max(p1.y, p2.y, p3.y, p4.y);

          if (clickX >= minX && clickX <= maxX && clickY >= minY && clickY <= maxY) {
            const pixelRatio = canvas.width / renderViewport.width;
            const corners = [p1, p2, p3, p4].map(p => {
              const vp = renderViewport.convertToViewportPoint(p.x, p.y);
              return { x: vp[0] * pixelRatio, y: vp[1] * pixelRatio };
            });

            const cMinX = Math.min(...corners.map(c => c.x));
            const cMaxX = Math.max(...corners.map(c => c.x));
            const cMinY = Math.min(...corners.map(c => c.y));
            const cMaxY = Math.max(...corners.map(c => c.y));

            const cropW = cMaxX - cMinX;
            const cropH = cMaxY - cMinY;

            if (cropW <= 0 || cropH <= 0) continue;

            const tempCanvas = document.createElement('canvas');
            tempCanvas.width = cropW;
            tempCanvas.height = cropH;
            const tempCtx = tempCanvas.getContext('2d');
            if (!tempCtx) continue;

            tempCtx.drawImage(
              canvas,
              cMinX, cMinY, cropW, cropH,
              0, 0, cropW, cropH
            );

            const imageBase64 = tempCanvas.toDataURL('image/png').split(',')[1];

            onImageSelect(imageBase64, pageNumber, {
              x: e.clientX,
              y: e.clientY
            });
            return;
          }
        }
      }
    } catch (err) {
      console.error('Error selecting image:', err);
    }
  }, [onImageSelect, pdfUrl, displayScale, renderScale, pdfDocumentRef, containerRef]);

  return { handleImageContextMenu };
}
