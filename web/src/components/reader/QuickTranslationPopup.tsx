'use client';

import { useEffect, useRef, useState } from 'react';
import type { CSSProperties } from 'react';
import { translateText } from '@/lib/gemini';
import styles from './QuickTranslationPopup.module.css';

interface QuickTranslationPopupProps {
    text: string;
    anchorBounds: { x: number; y: number; width: number; height: number };
    zoomScale?: number;
    containerSize?: { width: number; height: number };
    targetLang?: string;
    selectionRange?: Range;
    onClose: () => void;
}

export function QuickTranslationPopup({
    text,
    anchorBounds,
    zoomScale = 1,
    containerSize,
    targetLang = 'tr',
    selectionRange,
    onClose,
}: QuickTranslationPopupProps) {
    const popupRef = useRef<HTMLDivElement>(null);
    const [translation, setTranslation] = useState<string>('');
    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const requestIdRef = useRef(0);

    // Initial position based on anchorBounds (used as fallback or initial)
    const initialPosition = useRef({
        x: anchorBounds.x + anchorBounds.width / 2,
        y: anchorBounds.y + anchorBounds.height + 12,
    });

    const [currentPosition, setCurrentPosition] = useState(initialPosition.current);
    const [dragOffset, setDragOffset] = useState({ x: 0, y: 0 });
    const isDragging = useRef(false);
    const dragStart = useRef({ x: 0, y: 0 });

    const resolvedContainerWidth = containerSize?.width ?? (typeof window !== 'undefined' ? window.innerWidth : 0);
    const resolvedContainerHeight = containerSize?.height ?? (typeof window !== 'undefined' ? window.innerHeight : 0);
    const maxWidth = Math.max(220, Math.min(760, resolvedContainerWidth - 32));
    const minWidth = Math.min(maxWidth, Math.max(260, Math.round(resolvedContainerWidth * 0.45)));
    const preferredWidth = Math.min(maxWidth, Math.max(minWidth, anchorBounds.width + 120));
    const availableHeight = resolvedContainerHeight - currentPosition.y - 16;
    const maxHeight = Math.max(120, Math.min(resolvedContainerHeight * 0.45, availableHeight));
    const fontSize = Math.min(20, Math.max(14, 12 + zoomScale * 3.2));
    const lineHeight = Math.round(fontSize * 1.45);
    const paddingX = Math.round(fontSize * 0.9);
    const paddingY = Math.round(fontSize * 0.55);

    // Sticky positioning effect
    useEffect(() => {
        if (!selectionRange) return;

        let animationFrameId: number;

        const updatePosition = () => {
            try {
                // Check if range is still valid and in document
                if (selectionRange.commonAncestorContainer.isConnected) {
                    const params = selectionRange.getBoundingClientRect();
                    // Just check if optimization needed: only update if changed significantly?
                    // For smooth sticky behavior, we usually need to update every frame on scroll

                    // We need to convert viewport coordinates (getBoundingClientRect) 
                    // to the coordinate system used by the popup.
                    // Assuming the popup is fixed or absolute relative to viewport/body:

                    // However, our anchorBounds were likely relative to the PDF container or wrapper.
                    // If the popup is in the same container, we need relative coordinates.
                    // But usually these popups are in a specialized layer or body.
                    // Let's check where QuickTranslationPopup is mounted.
                    // It's in ReaderContent, alongside PDFViewer.

                    // If ReaderContent has `position: relative` (which `.viewer` class might have),
                    // then we need coords relative to that.
                    // But `Range.getBoundingClientRect()` returns viewport coords.

                    // Let's assume we need to convert to the container's coordinate space if it's relative.
                    // The viewer div has `ref={viewerRef}`. 
                    // QuickTranslationPopup is rendered inside `.viewer`.

                    const viewerElement = popupRef.current?.offsetParent as HTMLElement;
                    if (viewerElement) {
                        const viewerRect = viewerElement.getBoundingClientRect();
                        const x = params.left - viewerRect.left + params.width / 2;
                        const y = params.top - viewerRect.top + params.height + 12; // 12px gap

                        setCurrentPosition({ x, y });
                    }
                }
            } catch (e) {
                // Range might be detached
            }
            animationFrameId = requestAnimationFrame(updatePosition);
        };

        animationFrameId = requestAnimationFrame(updatePosition);
        return () => cancelAnimationFrame(animationFrameId);
    }, [selectionRange]);

    useEffect(() => {
        if (!text.trim()) {
            setTranslation('');
            setIsLoading(false);
            setError(null);
            return;
        }

        // Debounce translation
        const timer = setTimeout(() => {
            let isActive = true;
            const requestId = requestIdRef.current + 1;
            requestIdRef.current = requestId;
            setIsLoading(true);
            setError(null);

            translateText(text, targetLang)
                .then(result => {
                    if (!isActive || requestIdRef.current !== requestId) return;
                    setTranslation(result.trim());
                    setIsLoading(false);
                })
                .catch(err => {
                    if (!isActive || requestIdRef.current !== requestId) return;
                    console.error('Quick translation error:', err);
                    setError('Çeviri yapılamadı');
                    setIsLoading(false);
                });

            // Cleanup for the active request scope
            return () => {
                isActive = false;
            };
        }, 500); // 500ms delay

        return () => {
            clearTimeout(timer);
        };
    }, [text, targetLang]);

    // Cleanup click outside
    useEffect(() => {
        const handleOutsideClick = (event: MouseEvent | TouchEvent) => {
            if (isDragging.current) return; // Don't close while dragging

            const target = event.target as HTMLElement | null;
            if (!target || !popupRef.current) return;

            // Don't close if clicking inside the popup itself
            if (popupRef.current.contains(target)) return;

            // Don't close if clicking inside the chat panel
            if (target.closest('[data-chat-panel="true"]')) return;

            // Don't close if clicking on PDF toolbar (for quick highlighting)
            if (target.closest('[data-pdf-toolbar="true"]')) return;

            onClose();
        };

        const handleEscape = (event: KeyboardEvent) => {
            if (event.key === 'Escape') onClose();
        };

        document.addEventListener('mousedown', handleOutsideClick);
        document.addEventListener('touchstart', handleOutsideClick);
        document.addEventListener('keydown', handleEscape);

        return () => {
            document.removeEventListener('mousedown', handleOutsideClick);
            document.removeEventListener('touchstart', handleOutsideClick);
            document.removeEventListener('keydown', handleEscape);
        };
    }, [onClose]);

    // Drag handlers
    const handleDragStart = (e: React.MouseEvent | React.TouchEvent) => {
        e.preventDefault(); // Prevent text selection
        isDragging.current = true;

        const clientX = 'touches' in e ? e.touches[0].clientX : e.clientX;
        const clientY = 'touches' in e ? e.touches[0].clientY : e.clientY;

        dragStart.current = {
            x: clientX - dragOffset.x,
            y: clientY - dragOffset.y
        };

        document.addEventListener('mousemove', handleDragMove);
        document.addEventListener('touchmove', handleDragMove);
        document.addEventListener('mouseup', handleDragEnd);
        document.addEventListener('touchend', handleDragEnd);
    };

    const handleDragMove = (e: MouseEvent | TouchEvent) => {
        if (!isDragging.current) return;

        const clientX = 'touches' in e ? e.touches[0].clientX : e.clientX;
        const clientY = 'touches' in e ? e.touches[0].clientY : e.clientY;

        setDragOffset({
            x: clientX - dragStart.current.x,
            y: clientY - dragStart.current.y
        });
    };

    const handleDragEnd = () => {
        isDragging.current = false;
        document.removeEventListener('mousemove', handleDragMove);
        document.removeEventListener('touchmove', handleDragMove);
        document.removeEventListener('mouseup', handleDragEnd);
        document.removeEventListener('touchend', handleDragEnd);
    };

    const styleVars = {
        '--qt-font-size': `${fontSize}px`,
        '--qt-line-height': `${lineHeight}px`,
        '--qt-padding-x': `${paddingX}px`,
        '--qt-padding-y': `${paddingY}px`,
        '--qt-width': `${preferredWidth}px`,
        '--qt-max-width': `${maxWidth}px`,
        '--qt-min-width': `${minWidth}px`,
        '--qt-max-height': `${Math.max(120, maxHeight)}px`,
    } as CSSProperties;

    // Calculate final position
    // We center the popup horizontally on the calculate point, then apply drag offset
    const finalLeft = currentPosition.x + dragOffset.x;
    const finalTop = currentPosition.y + dragOffset.y;

    return (
        <div
            ref={popupRef}
            className={styles.popup}
            style={{
                left: finalLeft,
                top: finalTop,
                transform: 'translateX(-50%)', // Center horizontally
                ...styleVars,
            }}
        >
            <div
                className={styles.dragHandle}
                onMouseDown={handleDragStart}
                onTouchStart={handleDragStart}
            >
                <div className={styles.dragIndicator} />
            </div>

            <div className={styles.content}>
                {isLoading ? (
                    <span className={styles.loading}>
                        <span className={styles.dot} />
                        <span className={styles.dot} />
                        <span className={styles.dot} />
                    </span>
                ) : (
                    <span className={styles.text}>{error || translation}</span>
                )}
            </div>
        </div>
    );
}
