// Extracts text-selection geometry from the PDF page DOM and reports it
// upward (percentage-based rects for annotations + viewport coords for popups).
"use client";

import { useCallback, type RefObject } from "react";

export type SelectionRect = { x: number; y: number; width: number; height: number };

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

    const text = selection.toString().trim();
    if (!text) return;

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
