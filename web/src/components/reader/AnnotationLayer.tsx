'use client';

import { useEffect, useRef, useState } from 'react';
import { Annotation, AnnotationType } from '@/types/models';

interface AnnotationLayerProps {
    pageNumber: number;
    annotations: Annotation[];
    scale: number;
    pageWidth: number;
    pageHeight: number;
}

export function AnnotationLayer({
    pageNumber,
    annotations,
    scale,
    pageWidth,
    pageHeight,
}: AnnotationLayerProps) {
    const canvasRef = useRef<HTMLCanvasElement>(null);
    const [isVisible, setIsVisible] = useState(false);

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

        // Filter annotations for this page
        const pageAnnotations = annotations.filter(a => a.pageNumber === pageNumber);

        // Draw each annotation using offscreen canvas to prevent overlapping opacity
        pageAnnotations.forEach(annotation => {
            // Create offscreen canvas for this annotation
            const offscreen = document.createElement('canvas');
            offscreen.width = canvas.width;
            offscreen.height = canvas.height;
            const offCtx = offscreen.getContext('2d');
            if (!offCtx) return;

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
    }, [annotations, pageNumber, scale, pageWidth, pageHeight]);

    return (
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
                zIndex: 1,
                opacity: isVisible ? 1 : 0,
                transition: 'opacity 0.15s ease-in',
            }}
        />
    );
}

