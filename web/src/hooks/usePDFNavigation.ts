// PDF page navigation, scroll tracking, progress reporting
"use client";

import { useEffect, useState, useCallback } from "react";

interface UsePDFNavigationOptions {
  totalPages: number;
  initialPage?: number;
  initialScroll?: { x: number; y: number; scale: number };
  containerRef: React.RefObject<HTMLElement | null>;
  pageRefs: React.RefObject<Map<number, HTMLDivElement>>;
  displayScale: number;
  onPageChange?: (page: number) => void;
  onProgressChange?: (page: number, x: number, y: number, scale: number) => void;
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
}: UsePDFNavigationOptions) {
  const [currentPage, setCurrentPage] = useState(initialPage);
  const [isRestored, setIsRestored] = useState(false);

  const goToPage = useCallback(
    (page: number) => {
      if (!totalPages) return;
      const newPage = Math.max(1, Math.min(page, totalPages));
      setCurrentPage(newPage);
      onPageChange?.(newPage);
      pageRefs.current.get(newPage)?.scrollIntoView({ behavior: "smooth", block: "start" });
    },
    [totalPages, onPageChange, pageRefs]
  );

  const nextPage = useCallback(() => goToPage(currentPage + 1), [currentPage, goToPage]);
  const prevPage = useCallback(() => goToPage(currentPage - 1), [currentPage, goToPage]);

  const progress = totalPages > 0 ? (currentPage / totalPages) * 100 : 0;

  // Scroll to initial page
  useEffect(() => {
    if (!totalPages) return;
    const targetPage = Math.min(Math.max(initialPage, 1), totalPages);
    pageRefs.current.get(targetPage)?.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [initialPage, totalPages, pageRefs]);

  // Track current page via IntersectionObserver
  useEffect(() => {
    if (!containerRef.current || totalPages === 0) return;

    const observer = new IntersectionObserver(
      (entries) => {
        let maxRatio = 0;
        let mostVisiblePage = currentPage;

        entries.forEach((entry) => {
          if (entry.isIntersecting && entry.intersectionRatio > maxRatio) {
            const pageNum = Number(entry.target.getAttribute("data-page-number"));
            if (pageNum >= 1) {
              maxRatio = entry.intersectionRatio;
              mostVisiblePage = pageNum;
            }
          }
        });

        if (mostVisiblePage !== currentPage && maxRatio > 0) {
          setCurrentPage(mostVisiblePage);
          onPageChange?.(mostVisiblePage);
        }
      },
      {
        root: containerRef.current,
        threshold: [0, 0.25, 0.5, 0.75, 1],
        rootMargin: "-10% 0px -10% 0px",
      }
    );

    pageRefs.current.forEach((el) => observer.observe(el));
    return () => observer.disconnect();
  }, [totalPages, onPageChange, currentPage, containerRef, pageRefs]);

  // Restore initial scroll position
  useEffect(() => {
    if (!containerRef.current || totalPages === 0 || isRestored || !initialScroll) return;

    const timer = setTimeout(() => {
      pageRefs.current.get(initialPage)?.scrollIntoView({ behavior: "auto", block: "start" });
      setIsRestored(true);
    }, 500);

    return () => clearTimeout(timer);
  }, [totalPages, initialScroll, isRestored, initialPage, containerRef, pageRefs]);

  // Progress reporting (debounced scroll handler)
  useEffect(() => {
    const container = containerRef.current;
    if (!container || !onProgressChange) return;

    let timeoutId: ReturnType<typeof setTimeout>;
    const handleScroll = () => {
      clearTimeout(timeoutId);
      timeoutId = setTimeout(() => {
        const pageElement = pageRefs.current.get(currentPage);
        let offsetX = 0;
        let offsetY = 0;

        if (pageElement) {
          const containerRect = container.getBoundingClientRect();
          const pageRect = pageElement.getBoundingClientRect();
          offsetY = Math.max(0, containerRect.top - pageRect.top) / displayScale;
          offsetX = Math.max(0, containerRect.left - pageRect.left) / displayScale;
        }

        onProgressChange(currentPage, offsetX, offsetY, displayScale);
      }, 500);
    };

    container.addEventListener("scroll", handleScroll);
    return () => {
      container.removeEventListener("scroll", handleScroll);
      clearTimeout(timeoutId);
    };
  }, [currentPage, displayScale, onProgressChange, containerRef, pageRefs]);

  return {
    currentPage,
    totalPages,
    goToPage,
    nextPage,
    prevPage,
    progress,
    setCurrentPage,
  };
}
