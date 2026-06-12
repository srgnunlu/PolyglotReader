// PDF document loading, caching, zoom/scale management
"use client";

import { useEffect, useMemo, useRef, useState, useCallback } from "react";
import { pdfjs } from "react-pdf";
import { pdfCache } from "@/lib/pdfCache";
import { getSupabase } from "@/lib/supabase";

const DEFAULT_SCALE = 1.2;
const MIN_SCALE = 0.5;
const MAX_SCALE = 3;
const FALLBACK_PAGE_SIZE = { width: 595, height: 842 };

interface UsePDFRendererOptions {
  pdfUrl: string;
  storagePath?: string;
  initialScale?: number;
}

export function usePDFRenderer({ pdfUrl, storagePath, initialScale }: UsePDFRendererOptions) {
  const pdfDocumentRef = useRef<pdfjs.PDFDocumentProxy | null>(null);
  const zoomTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const [pdfDataUrl, setPdfDataUrl] = useState<string | null>(null);
  const [isLoadingPDF, setIsLoadingPDF] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [displayScale, setDisplayScale] = useState(initialScale ?? DEFAULT_SCALE);
  const [renderScale, setRenderScale] = useState(initialScale ?? DEFAULT_SCALE);
  const [isZooming, setIsZooming] = useState(false);
  const [totalPages, setTotalPages] = useState(0);
  const [pageDimensions, setPageDimensions] = useState<Map<number, { width: number; height: number }>>(new Map());
  const [defaultPageSize, setDefaultPageSize] = useState<{ width: number; height: number } | null>(null);

  const documentOptions = useMemo(() => ({
    // Self-hosted assets (scripts/copy-pdf-assets.mjs) — no CDN dependency.
    cMapUrl: "/pdfjs/cmaps/",
    cMapPacked: true,
    standardFontDataUrl: "/pdfjs/standard_fonts/",
    verbosity: 0,
  }), []);

  // Cache-first PDF loading
  useEffect(() => {
    let objectUrl: string | null = null;

    const loadPDF = async () => {
      setIsLoadingPDF(true);
      setLoadError(null);

      try {
        if (storagePath) {
          const cachedBlob = await pdfCache.getCachedPDF(storagePath);
          if (cachedBlob) {
            objectUrl = URL.createObjectURL(cachedBlob);
            setPdfDataUrl(objectUrl);
            setIsLoadingPDF(false);
            return;
          }

          const supabase = getSupabase();
          const { data: blob, error } = await supabase.storage
            .from("user_files")
            .download(storagePath);

          if (error) throw error;
          if (!blob) throw new Error("No blob returned from Supabase");

          await pdfCache.cachePDF(blob, storagePath);
          objectUrl = URL.createObjectURL(blob);
          setPdfDataUrl(objectUrl);
        } else {
          setPdfDataUrl(pdfUrl);
        }
        setIsLoadingPDF(false);
      } catch (error) {
        setLoadError(error instanceof Error ? error.message : "Failed to load PDF");
        setIsLoadingPDF(false);
        setPdfDataUrl(pdfUrl);
      }
    };

    loadPDF();
    return () => {
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [pdfUrl, storagePath]);

  const handleDocumentLoadSuccess = useCallback((pdf: pdfjs.PDFDocumentProxy) => {
    pdfDocumentRef.current = pdf;
    setTotalPages(pdf.numPages);
  }, []);

  const handleDocumentLoadError = useCallback((err: Error) => {
    if (err.message?.includes("Worker was terminated")) return;
    console.error("PDF load error:", err);
  }, []);

  const handlePageLoadSuccess = useCallback((page: pdfjs.PDFPageProxy) => {
    const viewport = page.getViewport({ scale: 1 });
    setPageDimensions((prev) => {
      const next = new Map(prev);
      next.set(page.pageNumber, { width: viewport.width, height: viewport.height });
      return next;
    });
    setDefaultPageSize((prev) => prev ?? { width: viewport.width, height: viewport.height });
  }, []);

  // Scroll-aware zoom: maintain scroll position relative to content
  const handleZoom = useCallback((newScale: number, containerEl?: HTMLElement | null) => {
    const container = containerEl;
    if (!container) {
      setDisplayScale(newScale);
      setRenderScale(newScale);
      return;
    }

    const scrollRatio = container.scrollTop / (container.scrollHeight || 1);
    setDisplayScale(newScale);
    setIsZooming(true);

    if (zoomTimeoutRef.current) clearTimeout(zoomTimeoutRef.current);
    zoomTimeoutRef.current = setTimeout(() => {
      setRenderScale(newScale);
      setIsZooming(false);
    }, 180);

    requestAnimationFrame(() => {
      container.scrollTop = scrollRatio * (container.scrollHeight || 1);
    });
  }, []);

  const zoomIn = useCallback((containerEl?: HTMLElement | null) => {
    handleZoom(Math.min(displayScale + 0.2, MAX_SCALE), containerEl);
  }, [displayScale, handleZoom]);

  const zoomOut = useCallback((containerEl?: HTMLElement | null) => {
    handleZoom(Math.max(displayScale - 0.2, MIN_SCALE), containerEl);
  }, [displayScale, handleZoom]);

  const resetZoom = useCallback((containerEl?: HTMLElement | null) => {
    handleZoom(DEFAULT_SCALE, containerEl);
  }, [handleZoom]);

  // Set both scales at once without the zoom debounce — used when restoring
  // a saved reading position
  const setScaleImmediate = useCallback((scale: number) => {
    setDisplayScale(scale);
    setRenderScale(scale);
  }, []);

  // Cleanup
  useEffect(() => {
    return () => {
      if (zoomTimeoutRef.current) clearTimeout(zoomTimeoutRef.current);
    };
  }, []);

  return {
    pdfDataUrl,
    isLoadingPDF,
    loadError,
    displayScale,
    renderScale,
    isZooming,
    totalPages,
    pageDimensions,
    defaultPageSize: defaultPageSize ?? FALLBACK_PAGE_SIZE,
    documentOptions,
    pdfDocumentRef,
    handleDocumentLoadSuccess,
    handleDocumentLoadError,
    handlePageLoadSuccess,
    handleZoom,
    zoomIn,
    zoomOut,
    resetZoom,
    setScaleImmediate,
  };
}
