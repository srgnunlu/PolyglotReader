'use client';

import { useEffect, useMemo, useRef, useState, useCallback } from 'react';
import { Document, Page, pdfjs } from 'react-pdf';
import { Annotation } from '@/types/models';
import { AnnotationLayer } from './AnnotationLayer';
import { PDFToolbar } from './PDFToolbar';
import { usePDFLoader } from '@/hooks/usePDFLoader';
import { useTextSelection } from '@/hooks/useTextSelection';
import '@/lib/pdfjs-config';
import styles from './PDFViewer.module.css';

const defaultScale = 1.2;
const minScale = 0.5;
const maxScale = 3;
const pdfjsVersion = pdfjs.version || '5.4.296';
const overscanPages = 2;
const fallbackPageSize = { width: 595, height: 842 };

function useIsMobile() {
    const [isMobile, setIsMobile] = useState(false);
    useEffect(() => {
        const check = () => setIsMobile(window.innerWidth <= 768);
        check();
        window.addEventListener('resize', check);
        return () => window.removeEventListener('resize', check);
    }, []);
    return isMobile;
}

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
    selectedColor?: string;
    onColorChange?: (color: string) => void;
    onQuickHighlight?: (color: string) => void;
    isFullscreen?: boolean;
    onToggleFullscreen?: () => void;
    isNavHidden?: boolean;
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
    const isMobile = useIsMobile();

    const [currentPage, setCurrentPage] = useState(initialPage);
    const [totalPages, setTotalPages] = useState(0);
    const [displayScale, setDisplayScale] = useState(initialScroll?.scale || defaultScale);
    const [renderScale, setRenderScale] = useState(initialScroll?.scale || defaultScale);
    const [isRestored, setIsRestored] = useState(false);
    const [pageDimensions, setPageDimensions] = useState<Map<number, { width: number; height: number }>>(new Map());
    const [defaultPageSize, setDefaultPageSize] = useState<{ width: number; height: number } | null>(null);
    const fitToWidthApplied = useRef(false);

    // PDF Loading via hook
    const { pdfDataUrl } = usePDFLoader({ pdfUrl, storagePath });

    const documentOptions = useMemo(() => ({
        cMapUrl: `https://cdn.jsdelivr.net/npm/pdfjs-dist@${pdfjsVersion}/cmaps/`,
        cMapPacked: true,
        standardFontDataUrl: `https://cdn.jsdelivr.net/npm/pdfjs-dist@${pdfjsVersion}/standard_fonts/`,
        verbosity: 0,
    }), []);

    // Text selection via hook
    const { handleSelectionEnd } = useTextSelection({
        containerRef,
        wrapperRef,
        pageDimensions,
        onSelect: useCallback((result) => {
            if (onTextSelect) {
                onTextSelect(
                    result.text,
                    result.pageNumber,
                    result.position,
                    result.rects,
                    result.bounds,
                    result.range,
                    result.pageDimensions
                );
            }
            setCurrentPage(result.pageNumber);
            onPageChange?.(result.pageNumber);
        }, [onTextSelect, onPageChange]),
        onPageChange,
    });

    // Fit-to-width on mobile when first page loads
    useEffect(() => {
        if (!isMobile || fitToWidthApplied.current || !defaultPageSize || !containerRef.current) return;
        if (initialScroll?.scale) return;

        const containerWidth = containerRef.current.clientWidth;
        const padding = 8;
        const fitScale = (containerWidth - padding * 2) / defaultPageSize.width;
        const clampedScale = Math.max(minScale, Math.min(maxScale, fitScale));

        fitToWidthApplied.current = true;
        setDisplayScale(clampedScale);
        setRenderScale(clampedScale);
    }, [isMobile, defaultPageSize, initialScroll]);

    const fitToWidth = useCallback(() => {
        if (!containerRef.current || !defaultPageSize) return;
        const containerWidth = containerRef.current.clientWidth;
        const padding = isMobile ? 8 : 32;
        const fitScale = (containerWidth - padding * 2) / defaultPageSize.width;
        const clampedScale = Math.max(minScale, Math.min(maxScale, fitScale));
        handleZoom(clampedScale);
    }, [defaultPageSize, isMobile]);

    useEffect(() => {
        onScaleChange?.(displayScale);
    }, [onScaleChange, displayScale]);

    useEffect(() => {
        if (!totalPages) return;
        const targetPage = Math.min(Math.max(initialPage, 1), totalPages);
        const pageElement = pageRefs.current.get(targetPage);
        pageElement?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }, [initialPage, totalPages]);

    // Track current page via IntersectionObserver
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

        pageRefs.current.forEach((el) => observer.observe(el));
        return () => observer.disconnect();
    }, [totalPages, onPageChange, currentPage]);

    // Scroll restoration
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

    // Progress tracking
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
        if (err.message?.includes('Worker was terminated')) return;
        console.error('PDF load error:', err);
    }, []);

    const handleImageContextMenu = useCallback(async (e: React.MouseEvent) => {
        if (e.type !== 'contextmenu') return;
        e.preventDefault();

        if (!onImageSelect || !containerRef.current) return;

        const selection = window.getSelection();
        if (selection && !selection.isCollapsed) return;

        const target = e.target as HTMLElement;
        const pageElement = target.closest(`.${styles.page}`) as HTMLElement;
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

            const multiply = (m1: number[], m2: number[]) => [
                m1[0] * m2[0] + m1[1] * m2[2],
                m1[0] * m2[1] + m1[1] * m2[3],
                m1[2] * m2[0] + m1[3] * m2[2],
                m1[2] * m2[1] + m1[3] * m2[3],
                m1[4] * m2[0] + m1[5] * m2[2] + m2[4],
                m1[4] * m2[1] + m1[5] * m2[3] + m2[5],
            ];

            const transform = (p: { x: number; y: number }, m: number[]) => ({
                x: m[0] * p.x + m[2] * p.y + m[4],
                y: m[1] * p.x + m[3] * p.y + m[5],
            });

            let ctm = [1, 0, 0, 1, 0, 0];
            const ctmStack: number[][] = [];

            for (let i = 0; i < ops.fnArray.length; i++) {
                const fn = ops.fnArray[i];
                const args = ops.argsArray[i];

                if (fn === pdfjs.OPS.save) {
                    ctmStack.push([...ctm]);
                } else if (fn === pdfjs.OPS.restore) {
                    if (ctmStack.length > 0) ctm = ctmStack.pop()!;
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

                        tempCtx.drawImage(canvas, cMinX, cMinY, cropW, cropH, 0, 0, cropW, cropH);
                        const imageBase64 = tempCanvas.toDataURL('image/png').split(',')[1];

                        onImageSelect(imageBase64, pageNumber, { x: e.clientX, y: e.clientY });
                        return;
                    }
                }
            }
        } catch (err) {
            console.error('Error selecting image:', err);
        }
    }, [onImageSelect, pdfUrl, displayScale, renderScale]);

    const goToPage = useCallback((page: number) => {
        if (!totalPages) return;
        const newPage = Math.max(1, Math.min(page, totalPages));
        setCurrentPage(newPage);
        onPageChange?.(newPage);
        const pageElement = pageRefs.current.get(newPage);
        pageElement?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }, [totalPages, onPageChange]);

    const handleZoom = useCallback((newScale: number) => {
        const container = containerRef.current;
        if (!container) {
            setDisplayScale(newScale);
            setRenderScale(newScale);
            return;
        }

        const currentScrollTop = container.scrollTop;
        const currentScrollHeight = container.scrollHeight || 1;
        const scrollRatio = currentScrollTop / currentScrollHeight;

        setDisplayScale(newScale);
        setRenderScale(newScale);

        requestAnimationFrame(() => {
            const newScrollHeight = container.scrollHeight || 1;
            container.scrollTop = scrollRatio * newScrollHeight;
        });
    }, []);

    const zoomIn = useCallback(() => handleZoom(Math.min(displayScale + 0.2, maxScale)), [handleZoom, displayScale]);
    const zoomOut = useCallback(() => handleZoom(Math.max(displayScale - 0.2, minScale)), [handleZoom, displayScale]);

    const handlePageLoadSuccess = useCallback((page: pdfjs.PDFPageProxy) => {
        const viewport = page.getViewport({ scale: 1 });
        setPageDimensions(prev => {
            const next = new Map(prev);
            next.set(page.pageNumber, { width: viewport.width, height: viewport.height });
            return next;
        });
        setDefaultPageSize(prev => prev ?? { width: viewport.width, height: viewport.height });
    }, []);

    const renderPersistentHighlight = (pageNum: number) => {
        if (persistentHighlightPageNumber !== pageNum || persistentHighlightRects.length === 0) {
            return null;
        }

        return (
            <div className={styles.persistentHighlightLayer}>
                {persistentHighlightRects.map((rect, idx) => (
                    <div
                        key={`persistent-${idx}`}
                        className={styles.persistentHighlight}
                        style={{
                            left: `${rect.x}%`,
                            top: `${rect.y}%`,
                            width: `${rect.width}%`,
                            height: `${rect.height}%`,
                        }}
                    />
                ))}
            </div>
        );
    };

    const loadingFallback = (
        <div className={styles.loading}>
            <div className="spinner" style={{ width: 40, height: 40 }} />
            <p>PDF yukleniyor...</p>
        </div>
    );

    const errorFallback = (
        <div className={styles.error}>
            <span>!</span>
            <p>PDF yuklenemedi</p>
        </div>
    );

    return (
        <div ref={wrapperRef} className={styles.wrapper}>
            <PDFToolbar
                currentPage={currentPage}
                totalPages={totalPages}
                displayScale={displayScale}
                selectedColor={selectedColor}
                isFullscreen={isFullscreen}
                isNavHidden={isNavHidden}
                isQuickTranslationMode={isQuickTranslationMode}
                isChatOpen={isChatOpen}
                isMobile={isMobile}
                onGoToPage={goToPage}
                onZoomIn={zoomIn}
                onZoomOut={zoomOut}
                onFitToWidth={fitToWidth}
                onColorChange={onColorChange || (() => {})}
                onQuickHighlight={onQuickHighlight || (() => {})}
                onToggleFullscreen={onToggleFullscreen || (() => {})}
                onToggleTranslation={onToggleTranslation || (() => {})}
                onToggleChat={onToggleChat || (() => {})}
            />

            <div
                ref={containerRef}
                className={styles.container}
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

                        return (
                            <div
                                key={pageNum}
                                id={`page-${pageNum}`}
                                data-page-number={pageNum}
                                className={styles.page}
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
                                        <div className={styles.pageInner}>
                                            <Page
                                                pageNumber={pageNum}
                                                scale={displayScale}
                                                renderTextLayer={true}
                                                renderAnnotationLayer={true}
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
                                    <div className={styles.pagePlaceholder} />
                                )}
                            </div>
                        );
                    })}
                </Document>
            </div>
        </div>
    );
}
