'use client';

import { useEffect, useRef, useCallback } from 'react';
import { Document, Page, pdfjs } from 'react-pdf';
import { Annotation } from '@/types/models';
import { AnnotationLayer } from './AnnotationLayer';
import { PDFToolbar } from './PDFToolbar';
import { usePDFRenderer } from '@/hooks/usePDFRenderer';
import { usePDFNavigation } from '@/hooks/usePDFNavigation';
import { useTextSelection } from '@/hooks/useTextSelection';
import { usePDFImageSelection } from '@/hooks/usePDFImageSelection';
import '@/lib/pdfjs-config'; // Initialize PDF.js worker configuration

const overscanPages = 10;

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
}

export function PDFViewer({
    pdfUrl,
    storagePath,
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
}: PDFViewerProps) {
    const wrapperRef = useRef<HTMLDivElement>(null);
    const containerRef = useRef<HTMLDivElement>(null);
    const pageRefs = useRef<Map<number, HTMLDivElement>>(new Map());

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

    const zoomIn = () => handleZoom(Math.min(displayScale + 0.2, 3), containerRef.current);
    const zoomOut = () => handleZoom(Math.max(displayScale - 0.2, 0.5), containerRef.current);
    const resetZoom = () => handleZoom(1.2, containerRef.current);

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
            <PDFToolbar
                currentPage={currentPage}
                totalPages={totalPages}
                displayScale={displayScale}
                goToPage={goToPage}
                zoomIn={zoomIn}
                zoomOut={zoomOut}
                resetZoom={resetZoom}
                selectedColor={selectedColor}
                onColorChange={onColorChange}
                onQuickHighlight={onQuickHighlight}
                isQuickTranslationMode={isQuickTranslationMode}
                onToggleTranslation={onToggleTranslation}
                isChatOpen={isChatOpen}
                onToggleChat={onToggleChat}
                isFullscreen={isFullscreen}
                onToggleFullscreen={onToggleFullscreen}
                isNavHidden={isNavHidden}
            />

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
