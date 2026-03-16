'use client';

import { useCallback, useRef } from 'react';

type Rect = { x: number; y: number; width: number; height: number };

interface TextSelectionResult {
    text: string;
    pageNumber: number;
    position: { x: number; y: number };
    rects: Rect[];
    bounds: Rect;
    range: Range;
    pageDimensions?: { width: number; height: number };
}

interface UseTextSelectionOptions {
    containerRef: React.RefObject<HTMLElement | null>;
    wrapperRef: React.RefObject<HTMLElement | null>;
    pageDimensions: Map<number, { width: number; height: number }>;
    onSelect: (result: TextSelectionResult) => void;
    onPageChange?: (page: number) => void;
}

export function useTextSelection({
    containerRef,
    wrapperRef,
    pageDimensions,
    onSelect,
    onPageChange,
}: UseTextSelectionOptions) {
    const isProcessing = useRef(false);

    const handleSelectionEnd = useCallback(() => {
        if (isProcessing.current) return;

        const selection = window.getSelection();
        if (!selection || selection.isCollapsed) return;

        const text = selection.toString().trim();
        if (!text) return;

        const range = selection.getRangeAt(0);
        if (!containerRef.current?.contains(range.commonAncestorContainer)) return;

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

        isProcessing.current = true;

        const selectionRects = Array.from(range.getClientRects())
            .filter(r => r.width > 0 && r.height > 0)
            .map(r => ({
                x: ((r.left - pageRect.left) / pageRect.width) * 100,
                y: ((r.top - pageRect.top) / pageRect.height) * 100,
                width: (r.width / pageRect.width) * 100,
                height: (r.height / pageRect.height) * 100,
            }));

        const bounds = {
            x: rect.left - wrapperRect.left,
            y: rect.top - wrapperRect.top,
            width: rect.width,
            height: rect.height,
        };

        const position = {
            x: rect.left - wrapperRect.left + rect.width / 2,
            y: rect.top - wrapperRect.top - 12,
        };

        onSelect({
            text,
            pageNumber,
            position,
            rects: selectionRects,
            bounds,
            range,
            pageDimensions: pageDimensions.get(pageNumber),
        });

        onPageChange?.(pageNumber);
        isProcessing.current = false;
    }, [containerRef, wrapperRef, pageDimensions, onSelect, onPageChange]);

    return { handleSelectionEnd };
}
