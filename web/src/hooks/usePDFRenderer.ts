// PDF document loading, caching, zoom/scale management
"use client";

import { useEffect, useMemo, useRef, useState, useCallback, type RefObject } from "react";
import { pdfjs } from "react-pdf";
import { pdfCache } from "@/lib/pdfCache";
import { getSupabase } from "@/lib/supabase";

export const DEFAULT_SCALE = 1.2;
export const MIN_SCALE = 0.5;
export const MAX_SCALE = 3;
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
  // The loaded document as state (not just the ref) so panels that read it —
  // outline, search, citation — render once it becomes available.
  const [pdfDocument, setPdfDocument] = useState<pdfjs.PDFDocumentProxy | null>(null);
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
    setPdfDocument(pdf);
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
    pdfDocument,
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

interface UsePinchZoomOptions {
  containerRef: RefObject<HTMLElement | null>;
  displayScale: number;
  handleZoom: (newScale: number, containerEl?: HTMLElement | null) => void;
}

/**
 * Pinch-to-zoom on the scroll container:
 * - trackpad pinch arrives as wheel events with ctrlKey set (browser
 *   convention); preventDefault stops the browser's page zoom,
 * - touch pinch is tracked via two-pointer distance with pointer events
 *   (the container needs `touch-action: pan-x pan-y` so the browser doesn't
 *   claim the gesture first).
 * Both feed the existing debounced handleZoom, clamped to MIN/MAX_SCALE.
 */
export function usePinchZoom({ containerRef, displayScale, handleZoom }: UsePinchZoomOptions) {
  // Ref mirror so the native listeners (attached once) always see the latest
  // scale without re-subscribing on every zoom step.
  const scaleRef = useRef(displayScale);
  useEffect(() => {
    scaleRef.current = displayScale;
  }, [displayScale]);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const applyScale = (next: number) => {
      const clamped = Math.min(Math.max(next, MIN_SCALE), MAX_SCALE);
      if (clamped === scaleRef.current) return;
      // Update the mirror immediately: continuous gestures fire faster than
      // React re-renders and would otherwise compound against a stale scale.
      scaleRef.current = clamped;
      handleZoom(clamped, container);
    };

    const handleWheel = (event: WheelEvent) => {
      if (!event.ctrlKey && !event.metaKey) return;
      event.preventDefault();
      // Exponential mapping keeps zoom speed proportional at any scale.
      applyScale(scaleRef.current * Math.exp(-event.deltaY * 0.0022));
    };

    const pointers = new Map<number, { x: number; y: number }>();
    let pinchStartDistance = 0;
    let pinchStartScale = 1;

    const pointerDistance = () => {
      const [a, b] = [...pointers.values()];
      return Math.hypot(a.x - b.x, a.y - b.y);
    };

    const handlePointerDown = (event: PointerEvent) => {
      if (event.pointerType !== "touch") return;
      pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
      if (pointers.size === 2) {
        pinchStartDistance = pointerDistance();
        pinchStartScale = scaleRef.current;
      }
    };

    const handlePointerMove = (event: PointerEvent) => {
      if (!pointers.has(event.pointerId)) return;
      pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
      if (pointers.size === 2 && pinchStartDistance > 0) {
        applyScale(pinchStartScale * (pointerDistance() / pinchStartDistance));
      }
    };

    const handlePointerEnd = (event: PointerEvent) => {
      pointers.delete(event.pointerId);
      if (pointers.size < 2) pinchStartDistance = 0;
    };

    // Non-passive: React delegates wheel as passive, which would ignore
    // preventDefault and let the browser zoom the whole page.
    container.addEventListener("wheel", handleWheel, { passive: false });
    container.addEventListener("pointerdown", handlePointerDown);
    container.addEventListener("pointermove", handlePointerMove);
    container.addEventListener("pointerup", handlePointerEnd);
    container.addEventListener("pointercancel", handlePointerEnd);

    return () => {
      container.removeEventListener("wheel", handleWheel);
      container.removeEventListener("pointerdown", handlePointerDown);
      container.removeEventListener("pointermove", handlePointerMove);
      container.removeEventListener("pointerup", handlePointerEnd);
      container.removeEventListener("pointercancel", handlePointerEnd);
    };
  }, [containerRef, handleZoom]);
}
