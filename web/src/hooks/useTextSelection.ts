// Extracts text-selection geometry from the PDF page DOM and reports it
// upward (percentage-based rects for annotations + viewport coords for popups).
"use client";

import { useCallback, type RefObject } from "react";
import { assembleReadingOrderText, type PositionedText } from "@/lib/textGeometry";

export type SelectionRect = { x: number; y: number; width: number; height: number };

/**
 * Reconstructs the selected text from the pdf.js text-layer spans that the
 * selection Range intersects, in geometric reading order. On 2-column PDFs
 * `selection.toString()` follows DOM (content-stream) order and interleaves
 * the columns; here spans are clustered into columns by x, ordered by line,
 * and hyphenated line breaks are merged so translation gets natural text.
 * Returns "" when nothing usable is found — callers must fall back.
 */
function extractSelectionTextGeometryAware(
  range: Range,
  pageElement: HTMLElement,
  pageRect: DOMRect
): string {
  const spans = pageElement.querySelectorAll<HTMLElement>(
    ".react-pdf__Page__textContent span, .textLayer span"
  );
  const items: PositionedText[] = [];

  for (const span of Array.from(spans)) {
    if (!range.intersectsNode(span)) continue;

    // Clamp a copy of the span's contents to the selection so boundary spans
    // contribute only their selected portion.
    const spanRange = document.createRange();
    spanRange.selectNodeContents(span);
    if (spanRange.compareBoundaryPoints(Range.START_TO_START, range) < 0) {
      spanRange.setStart(range.startContainer, range.startOffset);
    }
    if (spanRange.compareBoundaryPoints(Range.END_TO_END, range) > 0) {
      spanRange.setEnd(range.endContainer, range.endOffset);
    }
    const text = spanRange.toString();
    if (!text.trim()) continue;

    // The span's own rect (not the clamped range's) keeps partial boundary
    // runs anchored to their line/column for ordering purposes.
    const rect = span.getBoundingClientRect();
    if (!rect.width || !rect.height) continue;

    items.push({
      text,
      left: rect.left - pageRect.left,
      top: rect.top - pageRect.top,
      height: rect.height,
      right: rect.right - pageRect.left,
    });
  }

  if (items.length === 0) return "";
  return assembleReadingOrderText(items, pageRect.width);
}

interface UseTextSelectionOptions {
  wrapperRef: RefObject<HTMLDivElement | null>;
  containerRef: RefObject<HTMLDivElement | null>;
  pageDimensions: Map<number, { width: number; height: number }>;
  onTextSelect?: (
    text: string,
    pageNumber: number,
    rect: { x: number; y: number },
    selectionRects?: SelectionRect[],
    selectionBounds?: SelectionRect,
    selectionRange?: Range,
    pageDimensions?: { width: number; height: number }
  ) => void;
  // Selecting text also moves the current page to the selection's page
  onSelectPage?: (pageNumber: number) => void;
}

export function useTextSelection({
  wrapperRef,
  containerRef,
  pageDimensions,
  onTextSelect,
  onSelectPage,
}: UseTextSelectionOptions) {
  const handleSelectionEnd = useCallback(() => {
    const selection = window.getSelection();
    if (!selection || selection.isCollapsed) return;

    if (!selection.toString().trim()) return;

    const range = selection.getRangeAt(0);
    if (!containerRef.current?.contains(range.commonAncestorContainer)) {
      return;
    }

    const rect = range.getBoundingClientRect();
    const wrapperRect = wrapperRef.current?.getBoundingClientRect();

    if (!wrapperRect) return;

    let element: HTMLElement | null = range.commonAncestorContainer as HTMLElement;
    if (element.nodeType === Node.TEXT_NODE) {
      element = element.parentElement;
    }

    const pageElement = element?.closest('[data-page-number]') as HTMLElement | null;
    if (!pageElement) return;

    const pageNumber = Number(pageElement.dataset.pageNumber);
    if (!Number.isFinite(pageNumber) || pageNumber < 1) return;

    const canvas = pageElement.querySelector('.react-pdf__Page__canvas') as HTMLCanvasElement | null;
    const pageRect = (canvas ?? pageElement).getBoundingClientRect();

    if (!pageRect.width || !pageRect.height) return;

    // Geometry-aware reconstruction with a hard fallback: any failure or empty
    // result must never break selection, so we degrade to DOM order.
    let text = "";
    try {
      text = extractSelectionTextGeometryAware(range, pageElement, pageRect);
    } catch {
      text = "";
    }
    if (!text) text = selection.toString().trim();
    if (!text) return;

    const selectionRects = Array.from(range.getClientRects())
      .filter(r => r.width > 0 && r.height > 0)
      .map(r => ({
        x: ((r.left - pageRect.left) / pageRect.width) * 100,
        y: ((r.top - pageRect.top) / pageRect.height) * 100,
        width: (r.width / pageRect.width) * 100,
        height: (r.height / pageRect.height) * 100,
      }));

    const selectionBounds = {
      x: rect.left - wrapperRect.left,
      y: rect.top - wrapperRect.top,
      width: rect.width,
      height: rect.height,
    };

    if (onTextSelect) {
      const dims = pageDimensions.get(pageNumber);
      onTextSelect(
        text,
        pageNumber,
        {
          x: rect.left - wrapperRect.left + rect.width / 2,
          y: rect.top - wrapperRect.top - 40,
        },
        selectionRects,
        selectionBounds,
        range,
        dims
      );
    }

    onSelectPage?.(pageNumber);
  }, [wrapperRef, containerRef, pageDimensions, onTextSelect, onSelectPage]);

  return { handleSelectionEnd };
}
