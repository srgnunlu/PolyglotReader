'use client';

import { useEffect, useRef, useCallback, useMemo, useState } from 'react';
import { Document, Page, pdfjs } from 'react-pdf';
import { Annotation } from '@/types/models';
import { AnnotationLayer } from './AnnotationLayer';
import { ReaderToolbar, ReaderPanel } from './ReaderToolbar';
import { PageNavigation } from './PageNavigation';
import { DocumentOutline } from './DocumentOutline';
import { DocumentSearchPanel } from './DocumentSearchPanel';
import { CitationDialog } from './CitationDialog';
import { QuizDialog } from './QuizDialog';
import { OCRPanel } from './OCRPanel';
import { usePDFRenderer, usePinchZoom, MIN_SCALE, MAX_SCALE, DEFAULT_SCALE } from '@/hooks/usePDFRenderer';
import { usePDFNavigation } from '@/hooks/usePDFNavigation';
import { useTextSelection } from '@/hooks/useTextSelection';
import { usePDFImageSelection } from '@/hooks/usePDFImageSelection';
import '@/lib/pdfjs-config'; // Initialize PDF.js worker configuration

// Only the current page ± this many neighbours mount a real react-pdf <Page>
// (canvas + text + annotation layers). Everything outside the window is a
// lightweight spacer that preserves scroll geometry. Keep this small — each
// live page is expensive in RAM and paint cost (Phase B perf — P1/P3).
const overscanPages = 2;

// Stable reference for pages with no annotations, so their memoized layer
// never re-renders just because a new empty array was created.
const EMPTY_ANNOTATIONS: Annotation[] = [];

interface PDFViewerProps {
    pdfUrl: string;
    storagePath?: string;
    documentName?: string;
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
    onTotalPagesChange?: (total: number) => void;
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
    /** Exposes the internal goToPage to the parent (chat citation jumps). */
    onRegisterGoToPage?: (goToPage: (page: number) => void) => void;
}

export function PDFViewer({
    pdfUrl,
    storagePath,
    documentName = '',
    annotations = [],
    onTextSelect,
    onImageSelect,
    onPageChange,
    onTotalPagesChange,
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
    onRegisterGoToPage,
}: PDFViewerProps) {
    const wrapperRef = useRef<HTMLDivElement>(null);
    const containerRef = useRef<HTMLDivElement>(null);
    const pageRefs = useRef<Map<number, HTMLDivElement>>(new Map());

    // Side panels (outline / search) and the citation dialog.
    const [activePanel, setActivePanel] = useState<ReaderPanel>(null);
    const [citationOpen, setCitationOpen] = useState(false);
    const [quizOpen, setQuizOpen] = useState(false);
    const togglePanel = useCallback((panel: Exclude<ReaderPanel, null>) => {
        setActivePanel(prev => (prev === panel ? null : panel));
    }, []);

    // Group annotations by page once per annotations change. Each page gets a
    // stable array reference across scroll/zoom renders, so memoized
    // AnnotationLayers only redraw when their own page's data changes (P5).
    const annotationsByPage = useMemo(() => {
        const map = new Map<number, Annotation[]>();
        for (const annotation of annotations) {
            const list = map.get(annotation.pageNumber);
            if (list) list.push(annotation);
            else map.set(annotation.pageNumber, [annotation]);
        }
        return map;
    }, [annotations]);

    // Document loading, zoom and page dimensions
    const {
        pdfDataUrl,
        displayScale,
        renderScale,
        isZooming,
        totalPages,
        pageDimensions,
        defaultPageSize,
        documentOptions,
        pdfDocumentRef,
        pdfDocument,
        handleDocumentLoadSuccess,
        handleDocumentLoadError,
        handlePageLoadSuccess,
        handleZoom,
        setScaleImmediate,
    } = usePDFRenderer({
        pdfUrl,
        storagePath,
        initialScale: initialScroll?.scale,
    });

    // Page tracking, scroll restoration and progress reporting
    const { currentPage, setCurrentPage, goToPage } = usePDFNavigation({
        totalPages,
        initialPage,
        initialScroll,
        containerRef,
        pageRefs,
        displayScale,
        onPageChange,
        onProgressChange,
        restoreScale: setScaleImmediate,
    });

    useEffect(() => {
        onScaleChange?.(displayScale);
    }, [onScaleChange, displayScale]);

    // Let the parent (reader page) drive page jumps — used by chat citations.
    useEffect(() => {
        onRegisterGoToPage?.(goToPage);
    }, [onRegisterGoToPage, goToPage]);

    const handleLoadSuccess = useCallback((pdf: pdfjs.PDFDocumentProxy) => {
        handleDocumentLoadSuccess(pdf);
        setCurrentPage(prev => Math.min(Math.max(prev, 1), pdf.numPages));
        onTotalPagesChange?.(pdf.numPages);
    }, [handleDocumentLoadSuccess, setCurrentPage, onTotalPagesChange]);

    // Text selection — selecting also moves the current page
    const handleSelectPage = useCallback((pageNumber: number) => {
        setCurrentPage(pageNumber);
        onPageChange?.(pageNumber);
    }, [setCurrentPage, onPageChange]);

    const { handleSelectionEnd } = useTextSelection({
        wrapperRef,
        containerRef,
        pageDimensions,
        onTextSelect,
        onSelectPage: handleSelectPage,
    });

    // Right-click image extraction
    const { handleImageContextMenu } = usePDFImageSelection({
        pdfUrl,
        displayScale,
        renderScale,
        pdfDocumentRef,
        containerRef,
        onImageSelect,
    });

    // Trackpad (ctrl+wheel) and touch two-finger pinch zoom on the container
    usePinchZoom({ containerRef, displayScale, handleZoom });

    const zoomIn = () => handleZoom(Math.min(displayScale + 0.2, MAX_SCALE), containerRef.current);
    const zoomOut = () => handleZoom(Math.max(displayScale - 0.2, MIN_SCALE), containerRef.current);
    const resetZoom = () => handleZoom(DEFAULT_SCALE, containerRef.current);

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
                            backgroundColor: 'rgba(212, 113, 60, 0.3)',
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
            <div
                data-pdf-toolbar="true"
                className={`flex flex-wrap items-center justify-between gap-x-2 gap-y-1 border-b border-corio-border bg-corio-surface-1 transition-all duration-300 ${
                    isNavHidden ? 'pointer-events-none -translate-y-full opacity-0' : ''
                }`}
            >
                <PageNavigation
                    currentPage={currentPage}
                    totalPages={totalPages}
                    displayScale={displayScale}
                    onGoToPage={goToPage}
                    onZoomIn={zoomIn}
                    onZoomOut={zoomOut}
                    onResetZoom={resetZoom}
                />
                <ReaderToolbar
                    selectedColor={selectedColor}
                    onColorChange={onColorChange ?? (() => {})}
                    onQuickHighlight={onQuickHighlight}
                    isQuickTranslationMode={isQuickTranslationMode}
                    onToggleTranslation={onToggleTranslation ?? (() => {})}
                    isChatOpen={isChatOpen}
                    onToggleChat={onToggleChat ?? (() => {})}
                    isFullscreen={isFullscreen}
                    onToggleFullscreen={onToggleFullscreen ?? (() => {})}
                    activePanel={activePanel}
                    onToggleOutline={() => togglePanel('outline')}
                    onToggleSearch={() => togglePanel('search')}
                    onOpenCitation={() => setCitationOpen(true)}
                    onOpenQuiz={() => setQuizOpen(true)}
                />
            </div>

            <div className="reader-body">
                {activePanel === 'outline' && (
                    <DocumentOutline
                        pdf={pdfDocument}
                        currentPage={currentPage}
                        onNavigate={goToPage}
                        onClose={() => setActivePanel(null)}
                    />
                )}
                {activePanel === 'search' && (
                    <DocumentSearchPanel
                        pdf={pdfDocument}
                        onNavigate={goToPage}
                        onClose={() => setActivePanel(null)}
                    />
                )}
                <div
                    ref={containerRef}
                    className="pdf-container"
                    onMouseUp={handleSelectionEnd}
                    onTouchEnd={handleSelectionEnd}
                    onContextMenu={handleImageContextMenu}
                >
                <Document
                    file={pdfDataUrl}
                    onLoadSuccess={handleLoadSuccess}
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
                        const pageSize = pageDimensions.get(pageNum) ?? defaultPageSize;
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
                                                // Text layer stays mounted during zoom so an active
                                                // selection survives pinch/zoom; it lives inside the
                                                // CSS-transformed wrapper and scales with the canvas.
                                                renderTextLayer={true}
                                                renderAnnotationLayer={!isZooming}
                                                onLoadSuccess={handlePageLoadSuccess}
                                            />
                                        </div>
                                        {pageDimensions.has(pageNum) && (
                                            <AnnotationLayer
                                                pageNumber={pageNum}
                                                annotations={annotationsByPage.get(pageNum) ?? EMPTY_ANNOTATIONS}
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
                {/* OCR affordance for scanned pages (floating button + side panel) */}
                <OCRPanel
                    pdf={pdfDocument}
                    currentPage={currentPage}
                    containerRef={containerRef}
                    documentKey={storagePath ?? pdfUrl}
                />
            </div>

            <CitationDialog
                pdf={pdfDocument}
                documentName={documentName}
                open={citationOpen}
                onOpenChange={setCitationOpen}
            />

            <QuizDialog
                pdf={pdfDocument}
                open={quizOpen}
                onOpenChange={setQuizOpen}
            />

            <style jsx>{`
        .pdf-viewer-wrapper {
          display: flex;
          flex-direction: column;
          height: 100%;
          background: var(--corio-reader-bg);
        }

        .reader-body {
          display: flex;
          flex: 1;
          min-height: 0;
          overflow: hidden;
          /* Anchor for the floating OCR button (absolute, non-scrolling) */
          position: relative;
        }

        .pdf-container {
          flex: 1;
          min-width: 0;
          overflow: auto;
          padding: 24px;
          position: relative;
          /* Allow scroll panning but keep two-finger pinch for our own
             pointer-event zoom instead of the browser's page zoom */
          touch-action: pan-x pan-y;
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

        /* Static spacer for windowed-out pages. Intentionally NOT animated:
           a long PDF can have hundreds of these at once and a perpetual
           shimmer on each would burn paint/GPU for content nobody is looking
           at (Phase B perf — P1/P3). */
        .pdf-page-placeholder {
          width: 100%;
          height: 100%;
          background: rgba(0, 0, 0, 0.03);
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

        .pdf-loading .spinner {
          border: 3px solid var(--corio-border);
          border-top-color: var(--corio-accent);
          border-radius: 9999px;
          animation: spin 0.8s linear infinite;
        }

        @keyframes spin {
          to { transform: rotate(360deg); }
        }

        .pdf-error span {
          font-size: 2rem;
        }
      `}</style>
        </div>
    );
}
