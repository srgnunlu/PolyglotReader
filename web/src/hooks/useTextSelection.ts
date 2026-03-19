// Detects text selection within a container element
"use client";

import { useCallback, useEffect, useState, type RefObject } from "react";

interface SelectionInfo {
  selectedText: string;
  selectionRect: { x: number; y: number; width: number; height: number };
  pageNumber: number;
  selectionRects: { x: number; y: number; width: number; height: number }[];
  selectionRange: Range;
  pageDimensions: { width: number; height: number } | null;
}

export function useTextSelection(containerRef: RefObject<HTMLElement | null>) {
  const [selection, setSelection] = useState<SelectionInfo | null>(null);

  const clearSelection = useCallback(() => {
    setSelection(null);
    window.getSelection()?.removeAllRanges();
  }, []);

  const handleSelectionEnd = useCallback(() => {
    const sel = window.getSelection();
    if (!sel || sel.isCollapsed) return;

    const text = sel.toString().trim();
    if (!text || !containerRef.current) return;

    const range = sel.getRangeAt(0);
    if (!containerRef.current.contains(range.commonAncestorContainer)) return;

    const rect = range.getBoundingClientRect();
    const containerRect = containerRef.current.getBoundingClientRect();

    // Find the page element
    let element: HTMLElement | null = range.commonAncestorContainer as HTMLElement;
    if (element.nodeType === Node.TEXT_NODE) element = element.parentElement;
    const pageElement = element?.closest("[data-page-number]") as HTMLElement | null;
    if (!pageElement) return;

    const pageNumber = Number(pageElement.dataset.pageNumber);
    if (!Number.isFinite(pageNumber) || pageNumber < 1) return;

    const canvas = pageElement.querySelector(".react-pdf__Page__canvas") as HTMLCanvasElement | null;
    const pageRect = (canvas ?? pageElement).getBoundingClientRect();
    if (!pageRect.width || !pageRect.height) return;

    const selectionRects = Array.from(range.getClientRects())
      .filter((r) => r.width > 0 && r.height > 0)
      .map((r) => ({
        x: ((r.left - pageRect.left) / pageRect.width) * 100,
        y: ((r.top - pageRect.top) / pageRect.height) * 100,
        width: (r.width / pageRect.width) * 100,
        height: (r.height / pageRect.height) * 100,
      }));

    setSelection({
      selectedText: text,
      selectionRect: {
        x: rect.left - containerRect.left + rect.width / 2,
        y: rect.top - containerRect.top - 40,
        width: rect.width,
        height: rect.height,
      },
      pageNumber,
      selectionRects,
      selectionRange: range,
      pageDimensions: canvas
        ? { width: canvas.width, height: canvas.height }
        : null,
    });
  }, [containerRef]);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;

    el.addEventListener("mouseup", handleSelectionEnd);
    el.addEventListener("touchend", handleSelectionEnd);
    return () => {
      el.removeEventListener("mouseup", handleSelectionEnd);
      el.removeEventListener("touchend", handleSelectionEnd);
    };
  }, [containerRef, handleSelectionEnd]);

  return { selection, clearSelection };
}
