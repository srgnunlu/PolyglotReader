'use client';

import { useState, useEffect, useLayoutEffect, useRef } from 'react';
import { Languages, Sparkles, Highlighter, Copy } from 'lucide-react';
import { translateTextCached } from '@/lib/translationCache';
import styles from './SelectionPopup.module.css';

interface SelectionPopupProps {
    text: string;
    position: { x: number; y: number };
    onClose: () => void;
    onAskAI: (text: string) => void;
    onHighlight?: (color: string) => void;
    selectionRange?: Range;
}

// Anchor points (offsetParent-relative) the popup positions itself against:
// centered on x, sitting above yAbove, or below yBelow when flipped.
interface Anchor {
    x: number;
    yAbove: number;
    yBelow: number;
}

const VIEWPORT_MARGIN = 8; // min gap between popup and viewport edges
const DRAG_KEEP_VISIBLE = 40; // px of popup that must stay on-screen while dragged
const ANCHOR_GAP = 12; // gap between the selection and the popup

function clamp(value: number, min: number, max: number): number {
    if (max < min) return min; // degenerate viewport smaller than the popup
    return Math.min(Math.max(value, min), max);
}

export function SelectionPopup({
    text,
    position,
    onClose,
    onAskAI,
    onHighlight,
    selectionRange,
}: SelectionPopupProps) {
    const [translation, setTranslation] = useState<string | null>(null);
    const [isTranslating, setIsTranslating] = useState(false);
    const [showColors, setShowColors] = useState(false);
    const popupRef = useRef<HTMLDivElement>(null);

    // Anchor derived from the selection (sticky-follow) or the initial prop.
    // Without a Range we don't know the selection height, so approximate the
    // below-anchor from the point the parent gave us.
    const [anchor, setAnchor] = useState<Anchor>(() => ({
        x: position.x,
        yAbove: position.y,
        yBelow: position.y + 40,
    }));
    const [dragOffset, setDragOffset] = useState({ x: 0, y: 0 });

    const isDragging = useRef(false);
    const dragStart = useRef({ x: 0, y: 0 });
    // Mirrors for the document-level drag listeners and the layout pass.
    const anchorRef = useRef(anchor);
    anchorRef.current = anchor;
    const placementRef = useRef<'above' | 'below'>('above');

    const highlightColors = [
        { name: 'Sarı', color: '#fef08a' },
        { name: 'Yeşil', color: '#bbf7d0' },
        { name: 'Mavi', color: '#bae6fd' },
        { name: 'Pembe', color: '#fbcfe8' },
    ];

    const handleTranslate = async () => {
        if (isTranslating) return;

        setIsTranslating(true);
        try {
            // Two-layer cache (memory + Supabase) — repeated selections
            // resolve instantly without re-billing Gemini.
            const result = await translateTextCached(text, 'tr');
            setTranslation(result);
        } catch (err) {
            console.error('Translation error:', err);
            setTranslation('Çeviri yapılamadı');
        } finally {
            setIsTranslating(false);
        }
    };

    const handleAskAI = () => {
        onAskAI(text);
        onClose();
    };

    const handleHighlight = (color: string) => {
        onHighlight?.(color);
        onClose();
    };

    // Sticky positioning effect — follow the live selection rect every frame.
    useEffect(() => {
        if (!selectionRange) return;

        let animationFrameId: number;

        const updatePosition = () => {
            try {
                if (selectionRange.commonAncestorContainer.isConnected) {
                    const params = selectionRange.getBoundingClientRect();
                    const viewerElement = popupRef.current?.offsetParent as HTMLElement;

                    if (viewerElement) {
                        const viewerRect = viewerElement.getBoundingClientRect();
                        const x = params.left - viewerRect.left + params.width / 2;
                        const yAbove = params.top - viewerRect.top - ANCHOR_GAP;
                        const yBelow = params.bottom - viewerRect.top + ANCHOR_GAP;

                        // Only commit real movement — a fresh object every
                        // frame would re-render the popup at 60fps for nothing.
                        setAnchor(prev =>
                            prev.x === x && prev.yAbove === yAbove && prev.yBelow === yBelow
                                ? prev
                                : { x, yAbove, yBelow }
                        );
                    }
                }
            } catch {
                // Range detached
            }
            animationFrameId = requestAnimationFrame(updatePosition);
        };

        animationFrameId = requestAnimationFrame(updatePosition);
        return () => cancelAnimationFrame(animationFrameId);
    }, [selectionRange]);

    // Clamp the popup into the viewport after every render: content changes
    // (translation result, color row) change its size, so measure each time.
    // Position is written straight to the DOM node — no state, so re-renders
    // can't cascade — and starts hidden so the first paint is already clamped.
    useLayoutEffect(() => {
        const popup = popupRef.current;
        const viewer = popup?.offsetParent as HTMLElement | null;
        if (!popup || !viewer) return;

        const width = popup.offsetWidth;
        const height = popup.offsetHeight;
        const viewerRect = viewer.getBoundingClientRect();
        const viewportWidth = window.innerWidth;
        const viewportHeight = window.innerHeight;

        const dragged = dragOffset.x !== 0 || dragOffset.y !== 0;

        // Ideal viewport coordinates: centered on the anchor, above by default.
        let leftV = viewerRect.left + anchor.x + dragOffset.x - width / 2;
        let topV;

        if (!dragged) {
            topV = viewerRect.top + anchor.yAbove + dragOffset.y - height;
            // Flip below the selection when the popup would poke past the top.
            if (topV < VIEWPORT_MARGIN) {
                topV = viewerRect.top + anchor.yBelow + dragOffset.y;
                placementRef.current = 'below';
            } else {
                placementRef.current = 'above';
            }
            leftV = clamp(leftV, VIEWPORT_MARGIN, viewportWidth - width - VIEWPORT_MARGIN);
            topV = clamp(topV, VIEWPORT_MARGIN, viewportHeight - height - VIEWPORT_MARGIN);
        } else {
            // While dragged, respect the user's placement but keep enough of
            // the popup (and its top drag handle) reachable on-screen.
            topV =
                placementRef.current === 'below'
                    ? viewerRect.top + anchor.yBelow + dragOffset.y
                    : viewerRect.top + anchor.yAbove + dragOffset.y - height;
            leftV = clamp(leftV, DRAG_KEEP_VISIBLE - width, viewportWidth - DRAG_KEEP_VISIBLE);
            topV = clamp(topV, 0, viewportHeight - DRAG_KEEP_VISIBLE);
        }

        popup.style.left = `${leftV - viewerRect.left}px`;
        popup.style.top = `${topV - viewerRect.top}px`;
        popup.style.visibility = 'visible';
    });

    // Cleanup click interactions
    useEffect(() => {
        const handleClickOutside = (e: MouseEvent | TouchEvent) => {
            if (isDragging.current) return;

            const target = e.target as HTMLElement;

            // Don't close popup if clicking inside the popup itself
            if (target.closest(`.${styles.popup}`)) {
                return;
            }

            // Don't close popup if clicking inside the ChatPanel
            // Using data attribute for reliable detection (CSS Modules hash class names)
            if (target.closest('[data-chat-panel="true"]')) {
                return;
            }

            // Don't close popup if clicking on PDF toolbar (for quick highlighting)
            if (target.closest('[data-pdf-toolbar="true"]')) {
                return;
            }

            onClose();
        };

        document.addEventListener('mousedown', handleClickOutside);
        document.addEventListener('touchstart', handleClickOutside);
        return () => {
            document.removeEventListener('mousedown', handleClickOutside);
            document.removeEventListener('touchstart', handleClickOutside);
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

        let offsetX = clientX - dragStart.current.x;
        let offsetY = clientY - dragStart.current.y;

        // Clamp the offset itself (not just the rendered position) so there is
        // no dead zone when dragging back from an edge.
        const popup = popupRef.current;
        const viewer = popup?.offsetParent as HTMLElement | null;
        if (popup && viewer) {
            const width = popup.offsetWidth;
            const height = popup.offsetHeight;
            const viewerRect = viewer.getBoundingClientRect();
            const currentAnchor = anchorRef.current;

            const baseLeft = viewerRect.left + currentAnchor.x - width / 2;
            const baseTop =
                placementRef.current === 'below'
                    ? viewerRect.top + currentAnchor.yBelow
                    : viewerRect.top + currentAnchor.yAbove - height;

            offsetX =
                clamp(baseLeft + offsetX, DRAG_KEEP_VISIBLE - width, window.innerWidth - DRAG_KEEP_VISIBLE) -
                baseLeft;
            offsetY = clamp(baseTop + offsetY, 0, window.innerHeight - DRAG_KEEP_VISIBLE) - baseTop;
        }

        setDragOffset({ x: offsetX, y: offsetY });
    };

    const handleDragEnd = () => {
        isDragging.current = false;
        document.removeEventListener('mousemove', handleDragMove);
        document.removeEventListener('touchmove', handleDragMove);
        document.removeEventListener('mouseup', handleDragEnd);
        document.removeEventListener('touchend', handleDragEnd);
    };

    return (
        <div
            ref={popupRef}
            className={styles.popup}
            // Hidden until the layout effect measures and writes the clamped
            // left/top directly on the node (before the browser paints).
            style={{ visibility: 'hidden' }}
        >
            <div
                className={styles.dragHandle}
                onMouseDown={handleDragStart}
                onTouchStart={handleDragStart}
            >
                <div className={styles.dragIndicator} />
            </div>

            {/* Main actions */}
            <div className={styles.actions}>
                <button
                    className={styles.actionBtn}
                    onClick={handleTranslate}
                    disabled={isTranslating}
                >
                    {isTranslating ? (
                        <span className={styles.spinner} />
                    ) : (
                        <>
                            <Languages className={styles.icon} size={16} />
                            <span>Çevir</span>
                        </>
                    )}
                </button>

                <button
                    className={styles.actionBtn}
                    onClick={handleAskAI}
                >
                    <Sparkles className={styles.icon} size={16} />
                    <span>AI&apos;a Sor</span>
                </button>

                {onHighlight && (
                    <button
                        className={styles.actionBtn}
                        onClick={() => setShowColors(!showColors)}
                    >
                        <Highlighter className={styles.icon} size={16} />
                        <span>İşaretle</span>
                    </button>
                )}

                <button
                    className={styles.actionBtn}
                    onClick={() => {
                        navigator.clipboard.writeText(text);
                        onClose();
                    }}
                >
                    <Copy className={styles.icon} size={16} />
                    <span>Kopyala</span>
                </button>
            </div>

            {/* Color picker */}
            {showColors && onHighlight && (
                <div className={styles.colorPicker}>
                    {highlightColors.map(({ name, color }) => (
                        <button
                            key={color}
                            className={styles.colorBtn}
                            style={{ backgroundColor: color }}
                            onClick={() => handleHighlight(color)}
                            title={name}
                        />
                    ))}
                </div>
            )}

            {/* Translation result */}
            {translation && (
                <div className={styles.translation}>
                    <div className={styles.translationHeader}>
                        <span className={styles.translationLabel}>Çeviri</span>
                        <button
                            className={styles.closeTranslation}
                            onClick={() => setTranslation(null)}
                        >
                            ×
                        </button>
                    </div>
                    <p className={styles.translationText}>{translation}</p>
                </div>
            )}

            {/* Selected text preview */}
            <div className={styles.preview}>
                <p className={styles.previewText}>
                    {text.length > 100 ? text.slice(0, 100) + '...' : text}
                </p>
            </div>
        </div>
    );
}
