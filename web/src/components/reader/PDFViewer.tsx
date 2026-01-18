'use client';

import { useEffect, useMemo, useRef, useState, useCallback } from 'react';
import { Document, Page, pdfjs } from 'react-pdf';
import { Annotation } from '@/types/models';
import { AnnotationLayer } from './AnnotationLayer';
import { pdfCache } from '@/lib/pdfCache';
import { getSupabase } from '@/lib/supabase';
import '@/lib/pdfjs-config'; // Initialize PDF.js worker configuration

const defaultScale = 1.2;
const minScale = 0.5;
const maxScale = 3;
const pdfjsVersion = pdfjs.version || '5.4.296';
const overscanPages = 2;
const fallbackPageSize = { width: 595, height: 842 };

// Highlight colors
const HIGHLIGHT_COLORS = [
    { name: 'Sarı', value: '#fef08a', shortcut: '1' },
    { name: 'Yeşil', value: '#bbf7d0', shortcut: '2' },
    { name: 'Mavi', value: '#bae6fd', shortcut: '3' },
    { name: 'Pembe', value: '#fbcfe8', shortcut: '4' },
];

interface PDFViewerProps {
    pdfUrl: string;
    storagePath?: string;
    annotations?: Annotation[];
    onTextSelect?: (
        text: string,
        pageNumber: number,
        rect: { x: number; y: number },
        selectionRects?: { x: number; y: number; width: number; height: number }[],
        selectionBounds?: { x: number; y: number; width: number; height: number },
        selectionRange?: Range,
        pageDimensions?: { width: number; height: number }
    ) => void;
    onImageSelect?: (
        imageBase64: string,
        pageNumber: number,
        position: { x: number; y: number }
    ) => void;
    onPageChange?: (page: number) => void;
    onScaleChange?: (scale: number) => void;
    onProgressChange?: (page: number, x: number, y: number, scale: number) => void;
    initialPage?: number;
    initialScroll?: { x: number; y: number; scale: number };
    persistentHighlightRects?: { x: number; y: number; width: number; height: number }[];
    persistentHighlightPageNumber?: number | null;
    // Annotation colors and fullscreen
    selectedColor?: string;
    onColorChange?: (color: string) => void;
    onQuickHighlight?: (color: string) => void; // Quick highlight from toolbar
    isFullscreen?: boolean;
    onToggleFullscreen?: () => void;
    isNavHidden?: boolean;
    // Translation and chat
    isQuickTranslationMode?: boolean;
    onToggleTranslation?: () => void;
    isChatOpen?: boolean;
    onToggleChat?: () => void;
}

type DocumentLoadSuccess = pdfjs.PDFDocumentProxy;

export function PDFViewer({
    pdfUrl,
    storagePath,
    annotations = [],
    onTextSelect,
    onImageSelect,
    onPageChange,
    onScaleChange,
    onProgressChange,
    initialPage = 1,
    initialScroll,
    persistentHighlightRects = [],
    persistentHighlightPageNumber = null,
    selectedColor = '#fef08a',
    onColorChange,
    onQuickHighlight,
    isFullscreen = false,
    onToggleFullscreen,
    isNavHidden = false,
    isQuickTranslationMode = false,
    onToggleTranslation,
    isChatOpen = false,
    onToggleChat,
}: PDFViewerProps) {
    const wrapperRef = useRef<HTMLDivElement>(null);
    const containerRef = useRef<HTMLDivElement>(null);
    const pageRefs = useRef<Map<number, HTMLDivElement>>(new Map());
    const pdfDocumentRef = useRef<pdfjs.PDFDocumentProxy | null>(null);
    const [currentPage, setCurrentPage] = useState(initialPage);
    const [totalPages, setTotalPages] = useState(0);
    const [displayScale, setDisplayScale] = useState(initialScroll?.scale || defaultScale);
    const [renderScale, setRenderScale] = useState(initialScroll?.scale || defaultScale);
    const [isRestored, setIsRestored] = useState(false);
    const [pageDimensions, setPageDimensions] = useState<Map<number, { width: number; height: number }>>(new Map());
    const [defaultPageSize, setDefaultPageSize] = useState<{ width: number; height: number } | null>(null);
    const [isZooming, setIsZooming] = useState(false);
    const zoomTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
    const initialScaleRef = useRef(initialScroll?.scale || defaultScale);

    // Cache-first PDF loading
    const [pdfDataUrl, setPdfDataUrl] = useState<string | null>(null);
    const [isLoadingPDF, setIsLoadingPDF] = useState(true);
    const [loadError, setLoadError] = useState<string | null>(null);

    const documentOptions = useMemo(() => ({
        cMapUrl: `https://cdn.jsdelivr.net/npm/pdfjs-dist@${pdfjsVersion}/cmaps/`,
        cMapPacked: true,
        standardFontDataUrl: `https://cdn.jsdelivr.net/npm/pdfjs-dist@${pdfjsVersion}/standard_fonts/`,
        verbosity: 0,
    }), []);

    // Cache-first PDF loading
    useEffect(() => {
        let objectUrl: string | null = null;

        const loadPDF = async () => {
            setIsLoadingPDF(true);
            setLoadError(null);

            try {
                // If we have a storagePath, try cache-first strategy
                if (storagePath) {
                    // 1. Check cache first
                    const cachedBlob = await pdfCache.getCachedPDF(storagePath);

                    if (cachedBlob) {
                        objectUrl = URL.createObjectURL(cachedBlob);
                        setPdfDataUrl(objectUrl);
                        setIsLoadingPDF(false);
                        return;
                    }

                    // 2. Cache miss - download from Supabase
                    console.log('[PDFViewer] Cache miss, downloading from Supabase...');
                    const supabase = getSupabase();
                    const { data: blob, error } = await supabase.storage
                        .from('user_files')
                        .download(storagePath);

                    if (error) throw error;
                    if (!blob) throw new Error('No blob returned from Supabase');

                    // 3. Cache for next time
                    await pdfCache.cachePDF(blob, storagePath);

                    // 4. Create object URL and set
                    objectUrl = URL.createObjectURL(blob);
                    setPdfDataUrl(objectUrl);
                } else {
                    // Fallback: use pdfUrl directly (no caching)
                    setPdfDataUrl(pdfUrl);
                }

                setIsLoadingPDF(false);
            } catch (error) {
                console.error('[PDFViewer] Error loading PDF:', error);
                setLoadError(error instanceof Error ? error.message : 'Failed to load PDF');
                setIsLoadingPDF(false);
                // Fallback to direct URL
                setPdfDataUrl(pdfUrl);
            }
        };

        loadPDF();

        // Cleanup: revoke object URL to prevent memory leaks
        return () => {
            if (objectUrl) {
                URL.revokeObjectURL(objectUrl);
            }
        };
    }, [pdfUrl, storagePath]);

    useEffect(() => {
        onScaleChange?.(displayScale);
    }, [onScaleChange, displayScale]);

    useEffect(() => {
        if (!totalPages) return;
        const targetPage = Math.min(Math.max(initialPage, 1), totalPages);
        const pageElement = pageRefs.current.get(targetPage);
        pageElement?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }, [initialPage, totalPages]);

    // Track current page based on scroll position
    useEffect(() => {
        if (!containerRef.current || totalPages === 0) return;

        const observerOptions = {
            root: containerRef.current,
            threshold: [0, 0.25, 0.5, 0.75, 1],
            rootMargin: '-10% 0px -10% 0px',
        };

        const observer = new IntersectionObserver((entries) => {
            let maxRatio = 0;
            let mostVisiblePage = currentPage;

            entries.forEach((entry) => {
                if (entry.isIntersecting && entry.intersectionRatio > maxRatio) {
                    const pageNum = Number(entry.target.getAttribute('data-page-number'));
                    if (pageNum && pageNum >= 1) {
                        maxRatio = entry.intersectionRatio;
                        mostVisiblePage = pageNum;
                    }
                }
            });

            if (mostVisiblePage !== currentPage && maxRatio > 0) {
                setCurrentPage(mostVisiblePage);
                onPageChange?.(mostVisiblePage);
            }
        }, observerOptions);

        pageRefs.current.forEach((el) => {
            observer.observe(el);
        });

        return () => observer.disconnect();
    }, [totalPages, onPageChange, currentPage]);

    // Handle initial scroll restoration
    useEffect(() => {
        if (!containerRef.current || totalPages === 0 || isRestored || !initialScroll) return;

        const timer = setTimeout(() => {
            if (initialScroll && containerRef.current) {
                if (initialScroll.scale !== displayScale) {
                    setDisplayScale(initialScroll.scale);
                    setRenderScale(initialScroll.scale);
                }

                const pageElement = pageRefs.current.get(initialPage);
                if (pageElement) {
                    pageElement.scrollIntoView({ behavior: 'auto', block: 'start' });
                }
            }
            setIsRestored(true);
        }, 500);

        return () => clearTimeout(timer);
    }, [totalPages, initialScroll, isRestored, initialPage, displayScale]);

    // Monitor scroll for progress updates
    useEffect(() => {
        const container = containerRef.current;
        if (!container || !onProgressChange) return;

        const handleScroll = () => {
            if (!container) return;

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
        };

        let timeoutId: NodeJS.Timeout;
        const debouncedScroll = () => {
            clearTimeout(timeoutId);
            timeoutId = setTimeout(handleScroll, 500);
        };

        container.addEventListener('scroll', debouncedScroll);
        return () => {
            container.removeEventListener('scroll', debouncedScroll);
            clearTimeout(timeoutId);
        };
    }, [currentPage, displayScale, onProgressChange]);

    const handleDocumentLoadSuccess = useCallback((pdf: DocumentLoadSuccess) => {
        pdfDocumentRef.current = pdf;
        setTotalPages(pdf.numPages);
        setCurrentPage(prev => Math.min(Math.max(prev, 1), pdf.numPages));
    }, []);

    const handleDocumentLoadError = useCallback((err: Error) => {
        if (err.message && err.message.includes('Worker was terminated')) {
            return;
        }
        console.error('PDF load error:', err);
    }, []);

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

        setCurrentPage(pageNumber);
        onPageChange?.(pageNumber);
    }, [onPageChange, onTextSelect, pageDimensions]);

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
    }, [onImageSelect, pdfUrl, displayScale, renderScale]);

    const goToPage = (page: number) => {
        if (!totalPages) return;
        const newPage = Math.max(1, Math.min(page, totalPages));
        setCurrentPage(newPage);
        onPageChange?.(newPage);

        const pageElement = pageRefs.current.get(newPage);
        pageElement?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    };

    // Scroll-aware zoom: maintain scroll position relative to current page
    const handleZoom = useCallback((newScale: number) => {
        const container = containerRef.current;
        if (!container) {
            setDisplayScale(newScale);
            setRenderScale(newScale);
            return;
        }

        // Get current scroll position ratio
        const currentScrollTop = container.scrollTop;
        const currentScrollHeight = container.scrollHeight || 1;
        const scrollRatio = currentScrollTop / currentScrollHeight;

        // Apply new scale
        setDisplayScale(newScale);
        setIsZooming(true);
        if (zoomTimeoutRef.current) {
            clearTimeout(zoomTimeoutRef.current);
        }
        zoomTimeoutRef.current = setTimeout(() => {
            setRenderScale(newScale);
            setIsZooming(false);
        }, 180);

        // After render, restore scroll position
        requestAnimationFrame(() => {
            const newScrollHeight = container.scrollHeight || 1;
            container.scrollTop = scrollRatio * newScrollHeight;
        });
    }, []);

    const zoomIn = () => handleZoom(Math.min(displayScale + 0.2, maxScale));
    const zoomOut = () => handleZoom(Math.max(displayScale - 0.2, minScale));
    const resetZoom = () => handleZoom(defaultScale);

    // Page load success callback
    const handlePageLoadSuccess = useCallback((page: pdfjs.PDFPageProxy) => {
        const viewport = page.getViewport({ scale: 1 });
        setPageDimensions(prev => {
            const next = new Map(prev);
            next.set(page.pageNumber, { width: viewport.width, height: viewport.height });
            return next;
        });
        setDefaultPageSize(prev => prev ?? { width: viewport.width, height: viewport.height });
    }, []);

    useEffect(() => {
        return () => {
            if (zoomTimeoutRef.current) {
                clearTimeout(zoomTimeoutRef.current);
            }
        };
    }, []);

    // Render persistent highlight
    const renderPersistentHighlight = (pageNum: number) => {
        if (persistentHighlightPageNumber !== pageNum || persistentHighlightRects.length === 0) {
            return null;
        }

        return (
            <div className="persistent-highlight-layer">
                {persistentHighlightRects.map((rect, idx) => (
                    <div
                        key={`persistent-${idx}`}
                        className="persistent-highlight"
                        style={{
                            left: `${rect.x}%`,
                            top: `${rect.y}%`,
                            width: `${rect.width}%`,
                            height: `${rect.height}%`,
                            backgroundColor: 'rgba(99, 102, 241, 0.3)',
                            position: 'absolute',
                            pointerEvents: 'none',
                            borderRadius: '2px',
                        }}
                    />
                ))}
            </div>
        );
    };

    const loadingFallback = (
        <div className="pdf-loading">
            <div className="spinner" style={{ width: 40, height: 40 }} />
            <p>PDF yükleniyor...</p>
        </div>
    );

    const errorFallback = (
        <div className="pdf-error">
            <span>⚠️</span>
            <p>PDF yüklenemedi</p>
        </div>
    );

    return (
        <div ref={wrapperRef} className="pdf-viewer-wrapper">
            <div className={`pdf-toolbar ${isNavHidden ? 'toolbar-hidden' : ''}`} data-pdf-toolbar="true">
                {/* Page Navigation */}
                <div className="pdf-toolbar-group">
                    <button
                        className="pdf-toolbar-btn"
                        onClick={() => goToPage(currentPage - 1)}
                        disabled={currentPage <= 1}
                        title="Önceki sayfa"
                    >
                        ←
                    </button>
                    <span className="pdf-page-info">
                        <input
                            type="number"
                            value={currentPage}
                            onChange={(e) => goToPage(parseInt(e.target.value) || 1)}
                            min={1}
                            max={totalPages}
                            className="pdf-page-input"
                        />
                        <span>/ {totalPages || 0}</span>
                    </span>
                    <button
                        className="pdf-toolbar-btn"
                        onClick={() => goToPage(currentPage + 1)}
                        disabled={currentPage >= totalPages}
                        title="Sonraki sayfa"
                    >
                        →
                    </button>
                </div>

                {/* Zoom Controls */}
                <div className="pdf-toolbar-group">
                    <button className="pdf-toolbar-btn" onClick={zoomOut} title="Uzaklaştır">−</button>
                    <span className="pdf-zoom-info">{Math.round(displayScale * 100)}%</span>
                    <button className="pdf-toolbar-btn" onClick={zoomIn} title="Yakınlaştır">+</button>
                    <button className="pdf-toolbar-btn" onClick={resetZoom} title="Sıfırla">↺</button>
                </div>

                {/* Color Picker - Click to highlight selection */}
                <div className="pdf-toolbar-group pdf-color-group">
                    {HIGHLIGHT_COLORS.map(({ name, value, shortcut }) => (
                        <button
                            key={value}
                            className={`pdf-color-btn ${selectedColor === value ? 'active' : ''}`}
                            style={{ backgroundColor: value }}
                            onMouseDown={(e) => e.preventDefault()} // Preserve text selection
                            onClick={() => {
                                onColorChange?.(value);
                                onQuickHighlight?.(value);
                            }}
                            title={`${name} (${shortcut})`}
                        />
                    ))}
                </div>

                {/* Translation Toggle */}
                <div className="pdf-toolbar-group">
                    <button
                        className={`pdf-toolbar-btn pdf-translation-btn ${isQuickTranslationMode ? 'active' : ''}`}
                        onClick={onToggleTranslation}
                        title={isQuickTranslationMode ? 'Hızlı çeviri modu açık' : 'Hızlı çeviri modu'}
                    >
                        🌐
                    </button>
                    <button
                        className={`pdf-toolbar-btn pdf-chat-btn ${isChatOpen ? 'active' : ''}`}
                        onClick={onToggleChat}
                        title="AI Sohbet"
                    >
                        ✨
                    </button>
                </div>

                {/* Fullscreen Button */}
                <div className="pdf-toolbar-group">
                    <button
                        className={`pdf-toolbar-btn pdf-fullscreen-btn ${isFullscreen ? 'active' : ''}`}
                        onClick={onToggleFullscreen}
                        title={isFullscreen ? 'Tam ekrandan çık (ESC)' : 'Tam ekran (F11)'}
                    >
                        {isFullscreen ? '⛶' : '⛶'}
                    </button>
                </div>
            </div>

            <div
                ref={containerRef}
                className="pdf-container"
                onMouseUp={handleSelectionEnd}
                onTouchEnd={handleSelectionEnd}
                onContextMenu={handleImageContextMenu}
            >
                <Document
                    file={pdfDataUrl}
                    onLoadSuccess={handleDocumentLoadSuccess}
                    onLoadError={handleDocumentLoadError}
                    onSourceError={handleDocumentLoadError}
                    options={documentOptions}
                    loading={loadingFallback}
                    error={errorFallback}
                >
                    {Array.from({ length: totalPages }, (_, i) => i + 1).map(pageNum => {
                        const renderStart = Math.max(1, currentPage - overscanPages);
                        const renderEnd = Math.min(totalPages, currentPage + overscanPages);
                        const shouldRender = pageNum >= renderStart && pageNum <= renderEnd;
                        const pageSize = pageDimensions.get(pageNum) ?? defaultPageSize ?? fallbackPageSize;
                        const displayWidth = pageSize.width * displayScale;
                        const displayHeight = pageSize.height * displayScale;
                        const scaleRatio = displayScale / renderScale;

                        return (
                            <div
                                key={pageNum}
                                id={`page-${pageNum}`}
                                data-page-number={pageNum}
                                className="pdf-page"
                                ref={(el) => {
                                    if (el) pageRefs.current.set(pageNum, el);
                                }}
                                style={{
                                    position: 'relative',
                                    width: `${displayWidth}px`,
                                    height: `${displayHeight}px`,
                                }}
                            >
                                {shouldRender ? (
                                    <>
                                        <div
                                            className="pdf-page-inner"
                                            style={{
                                                transform: scaleRatio === 1 ? undefined : `scale(${scaleRatio})`,
                                                transformOrigin: 'top left',
                                            }}
                                        >
                                            <Page
                                                pageNumber={pageNum}
                                                scale={renderScale}
                                                renderTextLayer={!isZooming}
                                                renderAnnotationLayer={!isZooming}
                                                onLoadSuccess={handlePageLoadSuccess}
                                            />
                                        </div>
                                        {pageDimensions.has(pageNum) && (
                                            <AnnotationLayer
                                                pageNumber={pageNum}
                                                annotations={annotations}
                                                scale={displayScale}
                                                pageWidth={pageDimensions.get(pageNum)!.width}
                                                pageHeight={pageDimensions.get(pageNum)!.height}
                                            />
                                        )}
                                        {renderPersistentHighlight(pageNum)}
                                    </>
                                ) : (
                                    <div className="pdf-page-placeholder" />
                                )}
                            </div>
                        );
                    })}
                </Document>
            </div>

            <style jsx>{`
        .pdf-viewer-wrapper {
          display: flex;
          flex-direction: column;
          height: 100%;
          background: var(--color-gray-800);
        }

        .pdf-toolbar {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 24px;
          padding: 12px 16px;
          background: var(--bg-secondary);
          border-bottom: 1px solid var(--border-color);
          transition: opacity 0.3s ease, transform 0.3s ease;
          z-index: 100;
        }

        .pdf-toolbar-group {
          display: flex;
          align-items: center;
          gap: 8px;
        }

        .pdf-toolbar-btn {
          width: 32px;
          height: 32px;
          display: flex;
          align-items: center;
          justify-content: center;
          background: var(--bg-tertiary);
          border: 1px solid var(--border-color);
          border-radius: var(--radius-md);
          color: var(--text-primary);
          font-size: 1rem;
          cursor: pointer;
          transition: all var(--transition-fast);
        }

        .pdf-toolbar-btn:hover:not(:disabled) {
          background: var(--color-primary-500);
          color: white;
          border-color: var(--color-primary-500);
        }

        .pdf-toolbar-btn:disabled {
          opacity: 0.4;
          cursor: not-allowed;
        }

        /* Auto-hide toolbar */
        .toolbar-hidden {
          opacity: 0;
          pointer-events: none;
          transform: translateY(-100%);
        }

        /* Color picker buttons */
        .pdf-color-group {
          gap: 6px;
          padding: 0 8px;
          border-left: 1px solid var(--border-color);
          border-right: 1px solid var(--border-color);
        }

        .pdf-color-btn {
          width: 24px;
          height: 24px;
          border-radius: 50%;
          border: 2px solid transparent;
          cursor: pointer;
          transition: all 0.2s ease;
          box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }

        .pdf-color-btn:hover {
          transform: scale(1.15);
          box-shadow: 0 2px 6px rgba(0,0,0,0.2);
        }

        .pdf-color-btn.active {
          border-color: var(--text-primary);
          transform: scale(1.1);
          box-shadow: 0 0 0 2px var(--bg-secondary), 0 0 0 4px var(--color-primary-500);
        }

        /* Fullscreen button */
        .pdf-fullscreen-btn {
          font-size: 1.25rem;
        }

        .pdf-fullscreen-btn.active,
        .pdf-translation-btn.active,
        .pdf-chat-btn.active {
          background: var(--color-primary-500);
          color: white;
          border-color: var(--color-primary-500);
        }

        .pdf-page-info {
          display: flex;
          align-items: center;
          gap: 4px;
          font-size: 0.875rem;
          color: var(--text-secondary);
        }

        .pdf-page-input {
          width: 48px;
          padding: 4px 8px;
          text-align: center;
          background: var(--bg-tertiary);
          border: 1px solid var(--border-color);
          border-radius: var(--radius-sm);
          color: var(--text-primary);
          font-size: 0.875rem;
        }

        .pdf-page-input:focus {
          outline: none;
          border-color: var(--color-primary-500);
        }

        .pdf-zoom-info {
          min-width: 48px;
          text-align: center;
          font-size: 0.875rem;
          color: var(--text-secondary);
        }

        .pdf-container {
          flex: 1;
          overflow: auto;
          padding: 24px;
          position: relative;
        }

        .pdf-page {
          position: relative;
          background: white;
          box-shadow: var(--shadow-lg);
          border-radius: var(--radius-sm);
          display: inline-block;
          overflow: hidden;
        }

        .pdf-page-inner {
          position: absolute;
          top: 0;
          left: 0;
          will-change: transform;
        }

        .pdf-page-placeholder {
          width: 100%;
          height: 100%;
          background: linear-gradient(90deg, rgba(0, 0, 0, 0.04) 25%, rgba(0, 0, 0, 0.08) 50%, rgba(0, 0, 0, 0.04) 75%);
          background-size: 200% 100%;
          animation: shimmer 1.4s ease infinite;
        }

        :global(.react-pdf__Document) {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 16px;
        }

        :global(.react-pdf__Page__canvas) {
          display: block;
          position: relative;
        }

        @keyframes shimmer {
          0% { background-position: 200% 0; }
          100% { background-position: -200% 0; }
        }

        .persistent-highlight-layer {
          position: absolute;
          top: 0;
          left: 0;
          width: 100%;
          height: 100%;
          pointer-events: none;
          z-index: 9;
        }

        .pdf-loading,
        .pdf-error {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          min-height: 320px;
          gap: 16px;
          color: var(--text-secondary);
        }

        .pdf-error span {
          font-size: 2rem;
        }
      `}</style>
        </div>
    );
}
