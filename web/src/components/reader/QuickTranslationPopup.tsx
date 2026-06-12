'use client';

// Quick translation popup — "Frosted Light" design from the Corio redesign
// spec: frosted-glass card with a drag header, copy action and Literata body.
import { useEffect, useRef, useState } from 'react';
import type { CSSProperties } from 'react';
import { Languages, Copy, Check, X, GripHorizontal } from 'lucide-react';
import { translateText } from '@/lib/gemini';

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
    const [isCopied, setIsCopied] = useState(false);
    const requestIdRef = useRef(0);

    const [currentPosition, setCurrentPosition] = useState(() => ({
        x: anchorBounds.x + anchorBounds.width / 2,
        y: anchorBounds.y + anchorBounds.height + 12,
    }));
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

    // Sticky positioning — follows the selected text while the PDF scrolls.
    useEffect(() => {
        if (!selectionRange) return;

        let animationFrameId: number;

        const updatePosition = () => {
            try {
                if (selectionRange.commonAncestorContainer.isConnected) {
                    const rangeRect = selectionRange.getBoundingClientRect();
                    // Range gives viewport coords; the popup is positioned
                    // relative to its offsetParent (the reader viewer).
                    const viewerElement = popupRef.current?.offsetParent as HTMLElement | null;
                    if (viewerElement) {
                        const viewerRect = viewerElement.getBoundingClientRect();
                        setCurrentPosition({
                            x: rangeRect.left - viewerRect.left + rangeRect.width / 2,
                            y: rangeRect.top - viewerRect.top + rangeRect.height + 12,
                        });
                    }
                }
            } catch {
                // Range might be detached — keep the last known position.
            }
            animationFrameId = requestAnimationFrame(updatePosition);
        };

        animationFrameId = requestAnimationFrame(updatePosition);
        return () => cancelAnimationFrame(animationFrameId);
    }, [selectionRange]);

    // Debounced translation request
    useEffect(() => {
        const timer = setTimeout(() => {
            if (!text.trim()) {
                setTranslation('');
                setIsLoading(false);
                setError(null);
                return;
            }

            const requestId = requestIdRef.current + 1;
            requestIdRef.current = requestId;
            setIsLoading(true);
            setError(null);

            translateText(text, targetLang)
                .then(result => {
                    if (requestIdRef.current !== requestId) return;
                    setTranslation(result.trim());
                    setIsLoading(false);
                })
                .catch(err => {
                    if (requestIdRef.current !== requestId) return;
                    console.error('Quick translation error:', err);
                    setError('Çeviri yapılamadı');
                    setIsLoading(false);
                });
        }, 500);

        return () => clearTimeout(timer);
    }, [text, targetLang]);

    // Close on outside click / Escape
    useEffect(() => {
        const handleOutsideClick = (event: MouseEvent | TouchEvent) => {
            if (isDragging.current) return;

            const target = event.target as HTMLElement | null;
            if (!target || !popupRef.current) return;
            if (popupRef.current.contains(target)) return;
            if (target.closest('[data-chat-panel="true"]')) return;
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
        e.preventDefault();
        isDragging.current = true;

        const clientX = 'touches' in e ? e.touches[0].clientX : e.clientX;
        const clientY = 'touches' in e ? e.touches[0].clientY : e.clientY;

        dragStart.current = {
            x: clientX - dragOffset.x,
            y: clientY - dragOffset.y,
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
            y: clientY - dragStart.current.y,
        });
    };

    const handleDragEnd = () => {
        isDragging.current = false;
        document.removeEventListener('mousemove', handleDragMove);
        document.removeEventListener('touchmove', handleDragMove);
        document.removeEventListener('mouseup', handleDragEnd);
        document.removeEventListener('touchend', handleDragEnd);
    };

    const handleCopy = async () => {
        if (!translation) return;
        try {
            await navigator.clipboard.writeText(translation);
            setIsCopied(true);
            setTimeout(() => setIsCopied(false), 1500);
        } catch {
            // Clipboard unavailable (permissions) — nothing to do.
        }
    };

    const sizeStyle: CSSProperties = {
        left: currentPosition.x + dragOffset.x,
        top: currentPosition.y + dragOffset.y,
        transform: 'translateX(-50%)',
        width: preferredWidth,
        maxWidth,
        minWidth,
    };

    return (
        <div
            ref={popupRef}
            className="absolute z-50 overflow-hidden rounded-2xl border border-corio-border bg-corio-surface-1/90 shadow-xl shadow-black/10 backdrop-blur-xl"
            style={sizeStyle}
        >
            {/* Header — drag handle + actions */}
            <div
                className="flex cursor-grab select-none items-center gap-2 border-b border-corio-border-subtle bg-corio-surface-2/60 px-3 py-1.5 active:cursor-grabbing"
                onMouseDown={handleDragStart}
                onTouchStart={handleDragStart}
            >
                <Languages className="size-3.5 shrink-0 text-corio-accent" />
                <span className="text-xs font-medium text-corio-fg/70">Çeviri</span>
                <GripHorizontal className="mx-auto size-4 text-corio-fg/25" />
                <button
                    onClick={handleCopy}
                    onMouseDown={e => e.stopPropagation()}
                    onTouchStart={e => e.stopPropagation()}
                    disabled={!translation || isLoading}
                    className="rounded-md p-1 text-corio-fg/50 transition-colors hover:bg-corio-surface-3 hover:text-corio-fg disabled:opacity-40"
                    title="Çeviriyi kopyala"
                >
                    {isCopied ? <Check className="size-3.5 text-green-600" /> : <Copy className="size-3.5" />}
                </button>
                <button
                    onClick={onClose}
                    onMouseDown={e => e.stopPropagation()}
                    onTouchStart={e => e.stopPropagation()}
                    className="rounded-md p-1 text-corio-fg/50 transition-colors hover:bg-corio-surface-3 hover:text-corio-fg"
                    title="Kapat"
                >
                    <X className="size-3.5" />
                </button>
            </div>

            {/* Content */}
            <div
                className="overflow-y-auto px-4 py-3"
                style={{ maxHeight: Math.max(120, maxHeight) }}
            >
                {isLoading ? (
                    <div className="flex items-center gap-1.5 py-1">
                        <span className="size-1.5 animate-bounce rounded-full bg-corio-accent [animation-delay:0ms]" />
                        <span className="size-1.5 animate-bounce rounded-full bg-corio-accent [animation-delay:150ms]" />
                        <span className="size-1.5 animate-bounce rounded-full bg-corio-accent [animation-delay:300ms]" />
                    </div>
                ) : error ? (
                    <p className="text-sm text-red-600">{error}</p>
                ) : (
                    <p
                        className="font-reading leading-relaxed text-corio-fg"
                        style={{ fontSize }}
                    >
                        {translation}
                    </p>
                )}
            </div>
        </div>
    );
}
