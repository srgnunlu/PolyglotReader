'use client';

import React, { useEffect, useRef, useState, useMemo } from 'react';
import { Annotation, AnnotationType } from '@/types/models';

interface AnnotationLayerProps {
    pageNumber: number;
    annotations: Annotation[];
    scale: number;
    pageWidth: number;
    pageHeight: number;
    onAnnotationClick?: (annotation: Annotation, position: { x: number; y: number }) => void;
}

const AnnotationLayerInner = ({
    pageNumber,
    annotations,
    scale,
    pageWidth,
    pageHeight,
    onAnnotationClick,
}: AnnotationLayerProps) => {
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const offscreenRef = useRef<HTMLCanvasElement | null>(null);
    const [isVisible, setIsVisible] = useState(false);

    // Pre-filter annotations for this page so the filter doesn't run on every render
    const pageAnnotations = useMemo(
        () => annotations.filter(a => a.pageNumber === pageNumber),
        [annotations, pageNumber]
    );

    // Fade in after a small delay to ensure canvas is painted
    useEffect(() => {
        setIsVisible(false);
        const timer = setTimeout(() => setIsVisible(true), 50);
        return () => clearTimeout(timer);
    }, [pageNumber, scale]);

    useEffect(() => {
        const canvas = canvasRef.current;
        if (!canvas) return;

        const ctx = canvas.getContext('2d');
        if (!ctx) return;

        // Clear canvas
        ctx.clearRect(0, 0, canvas.width, canvas.height);

        // Lazily create the reusable offscreen canvas
        if (!offscreenRef.current) {
            offscreenRef.current = document.createElement('canvas');
        }
        const offscreen = offscreenRef.current;

        // Resize the offscreen canvas to match the main canvas dimensions
        offscreen.width = canvas.width;
        offscreen.height = canvas.height;

        // Draw each annotation using the reusable offscreen canvas to prevent overlapping opacity
        pageAnnotations.forEach(annotation => {
            const offCtx = offscreen.getContext('2d');
            if (!offCtx) return;

            // Clear the offscreen canvas for this annotation
            offCtx.clearRect(0, 0, offscreen.width, offscreen.height);

            // Use solid color for offscreen (we'll apply opacity when compositing)
            offCtx.fillStyle = annotation.color;
            offCtx.strokeStyle = annotation.color;
            offCtx.lineWidth = 2 * scale;

            annotation.rects.forEach(rect => {
                let x: number, y: number, width: number, height: number;

                // Detect coordinate system by checking if values are percentage (0-100) or PDF points (larger values)
                const isPercentage = rect.x <= 100 && rect.y <= 100 && rect.width <= 100 && rect.height <= 100;

                if (isPercentage) {
                    // Web percentage coordinates - convert to pixels
                    x = (rect.x / 100) * pageWidth * scale;
                    y = (rect.y / 100) * pageHeight * scale;
                    width = (rect.width / 100) * pageWidth * scale;
                    height = (rect.height / 100) * pageHeight * scale;
                } else {
                    // iOS PDFKit point coordinates - need to flip Y axis
                    const flippedY = pageHeight - rect.y - rect.height;
                    x = rect.x * scale;
                    y = flippedY * scale;
                    width = rect.width * scale;
                    height = rect.height * scale;
                }

                switch (annotation.type) {
                    case 'highlight':
                        offCtx.fillRect(x, y, width, height);
                        break;

                    case 'underline':
                        offCtx.beginPath();
                        offCtx.moveTo(x, y + height);
                        offCtx.lineTo(x + width, y + height);
                        offCtx.stroke();
                        break;

                    case 'strikethrough':
                        offCtx.beginPath();
                        offCtx.moveTo(x, y + height / 2);
                        offCtx.lineTo(x + width, y + height / 2);
                        offCtx.stroke();
                        break;
                }
            });

            // Composite offscreen canvas onto main canvas with transparency
            // Match iOS opacity (0.4) for consistent appearance across platforms
            ctx.globalAlpha = 0.4;
            ctx.drawImage(offscreen, 0, 0);
            ctx.globalAlpha = 1.0; // Reset alpha
        });
    }, [pageAnnotations, scale, pageWidth, pageHeight]);

    const getAnnotationBounds = (annotation: Annotation) => {
        if (annotation.rects.length === 0) return null;
        let minX = Infinity, minY = Infinity, maxX = 0, maxY = 0;
        annotation.rects.forEach(rect => {
            const isPct = rect.x <= 100 && rect.y <= 100 && rect.width <= 100 && rect.height <= 100;
            const x = isPct ? (rect.x / 100) * pageWidth : rect.x;
            const y = isPct ? (rect.y / 100) * pageHeight : (pageHeight - rect.y - rect.height);
            const w = isPct ? (rect.width / 100) * pageWidth : rect.width;
            const h = isPct ? (rect.height / 100) * pageHeight : rect.height;
            minX = Math.min(minX, x); minY = Math.min(minY, y);
            maxX = Math.max(maxX, x + w); maxY = Math.max(maxY, y + h);
        });
        return { x: minX * scale, y: minY * scale, w: (maxX - minX) * scale, h: (maxY - minY) * scale };
    };

    return (
        <div style={{ position: 'absolute', top: 0, left: 0, width: '100%', height: '100%', zIndex: 1 }}>
            <canvas
                ref={canvasRef}
                width={pageWidth * scale}
                height={pageHeight * scale}
                style={{
                    position: 'absolute',
                    top: 0,
                    left: 0,
                    width: '100%',
                    height: '100%',
                    pointerEvents: 'none',
                    opacity: isVisible ? 1 : 0,
                    transition: 'opacity 0.15s ease-in',
                }}
            />
            {onAnnotationClick && pageAnnotations.map(annotation => {
                const bounds = getAnnotationBounds(annotation);
                if (!bounds) return null;
                return (
                    <div
                        key={annotation.id}
                        onClick={(e) => {
                            e.stopPropagation();
                            onAnnotationClick(annotation, { x: bounds.x + bounds.w / 2, y: bounds.y });
                        }}
                        style={{
                            position: 'absolute',
                            left: bounds.x,
                            top: bounds.y,
                            width: bounds.w,
                            height: bounds.h,
                            cursor: 'pointer',
                            zIndex: 2,
                        }}
                    />
                );
            })}
        </div>
    );
};

export const AnnotationLayer = React.memo(AnnotationLayerInner, (prev, next) => {
    return (
        prev.annotations === next.annotations &&
        prev.pageNumber === next.pageNumber &&
        prev.scale === next.scale &&
        prev.pageWidth === next.pageWidth &&
        prev.pageHeight === next.pageHeight &&
        prev.onAnnotationClick === next.onAnnotationClick
    );
});
