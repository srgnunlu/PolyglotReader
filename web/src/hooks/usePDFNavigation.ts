// PDF page navigation, scroll tracking, scroll restoration, progress reporting.
// Page tracking is scroll-based with rAF throttling; currentPage/onPageChange
// live in refs so the effect only depends on totalPages — keeping the
// "effect → setState → effect" freeze loop fixed (see commits f3e469a, 03b0c8a).
"use client";

import { useEffect, useRef, useState, useCallback } from "react";

interface UsePDFNavigationOptions {
  totalPages: number;
  initialPage?: number;
  initialScroll?: { x: number; y: number; scale: number };
  containerRef: React.RefObject<HTMLDivElement | null>;
  pageRefs: React.RefObject<Map<number, HTMLDivElement>>;
  displayScale: number;
  onPageChange?: (page: number) => void;
  onProgressChange?: (page: number, x: number, y: number, scale: number) => void;
  // Called once during scroll restoration when the saved zoom differs
  restoreScale?: (scale: number) => void;
}

export function usePDFNavigation({
  totalPages,
  initialPage = 1,
  initialScroll,
  containerRef,
  pageRefs,
  displayScale,
  onPageChange,
  onProgressChange,
  restoreScale,
}: UsePDFNavigationOptions) {
  const [currentPage, setCurrentPage] = useState(initialPage);
  const [isRestored, setIsRestored] = useState(false);

  // Scroll to initial page once the document is ready
  useEffect(() => {
    if (!totalPages) return;
    const targetPage = Math.min(Math.max(initialPage, 1), totalPages);
    pageRefs.current?.get(targetPage)?.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [initialPage, totalPages, pageRefs]);

  // Track current page based on scroll position
  const currentPageRef = useRef(currentPage);
  const onPageChangeRef = useRef(onPageChange);
  useEffect(() => {
    currentPageRef.current = currentPage;
    onPageChangeRef.current = onPageChange;
  });

  useEffect(() => {
    const container = containerRef.current;
    if (!container || totalPages === 0) return;

    let rafId: number;
    const updateCurrentPage = () => {
      const containerRect = container.getBoundingClientRect();
      const containerMid = containerRect.top + containerRect.height / 2;
      let closestPage = currentPageRef.current;
      let closestDist = Infinity;

      pageRefs.current?.forEach((el, pageNum) => {
        const rect = el.getBoundingClientRect();
        const pageMid = rect.top + rect.height / 2;
        const dist = Math.abs(pageMid - containerMid);
        if (dist < closestDist) {
          closestDist = dist;
          closestPage = pageNum;
        }
      });

      if (closestPage !== currentPageRef.current) {
        setCurrentPage(closestPage);
        onPageChangeRef.current?.(closestPage);
      }
    };

    const handleScroll = () => {
      cancelAnimationFrame(rafId);
      rafId = requestAnimationFrame(updateCurrentPage);
    };

    container.addEventListener("scroll", handleScroll, { passive: true });

    return () => {
      container.removeEventListener("scroll", handleScroll);
      cancelAnimationFrame(rafId);
    };
  }, [totalPages, containerRef, pageRefs]);

  // Handle initial scroll restoration
  useEffect(() => {
    if (!containerRef.current || totalPages === 0 || isRestored || !initialScroll) return;

    const timer = setTimeout(() => {
      if (initialScroll && containerRef.current) {
        if (initialScroll.scale !== displayScale) {
          restoreScale?.(initialScroll.scale);
        }

        pageRefs.current?.get(initialPage)?.scrollIntoView({ behavior: "auto", block: "start" });
      }
      setIsRestored(true);
    }, 500);

    return () => clearTimeout(timer);
  }, [totalPages, initialScroll, isRestored, initialPage, displayScale, restoreScale, containerRef, pageRefs]);

  // Monitor scroll for progress updates (debounced)
  useEffect(() => {
    const container = containerRef.current;
    if (!container || !onProgressChange) return;

    const handleScroll = () => {
      const pageElement = pageRefs.current?.get(currentPage);
      let offsetX = 0;
      let offsetY = 0;

      if (pageElement) {
        const containerRect = container.getBoundingClientRect();
        const pageRect = pageElement.getBoundingClientRect();

        offsetY = Math.max(0, containerRect.top - pageRect.top) / displayScale;
        offsetX = Math.max(0, containerRect.left - pageRect.left) / displayScale;
      }

      onProgressChange(currentPage, offsetX, offsetY, displayScale);
    };

    let timeoutId: ReturnType<typeof setTimeout>;
    const debouncedScroll = () => {
      clearTimeout(timeoutId);
      timeoutId = setTimeout(handleScroll, 500);
    };

    container.addEventListener("scroll", debouncedScroll);
    return () => {
      container.removeEventListener("scroll", debouncedScroll);
      clearTimeout(timeoutId);
    };
  }, [currentPage, displayScale, onProgressChange, containerRef, pageRefs]);

  const goToPage = useCallback(
    (page: number) => {
      if (!totalPages) return;
      const newPage = Math.max(1, Math.min(page, totalPages));
      setCurrentPage(newPage);
      onPageChangeRef.current?.(newPage);
      pageRefs.current?.get(newPage)?.scrollIntoView({ behavior: "smooth", block: "start" });
    },
    [totalPages, pageRefs]
  );

  return { currentPage, setCurrentPage, goToPage };
}
