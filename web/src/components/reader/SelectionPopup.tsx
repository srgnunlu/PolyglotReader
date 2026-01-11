'use client';

import { useState, useEffect, useRef } from 'react';
import { translateText } from '@/lib/gemini';
import styles from './SelectionPopup.module.css';

interface SelectionPopupProps {
    text: string;
    position: { x: number; y: number };
    onClose: () => void;
    onAskAI: (text: string) => void;
    onHighlight?: (color: string) => void;
    selectionRange?: Range;
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

    // Initial positioning state
    const [currentPosition, setCurrentPosition] = useState(position);
    const [dragOffset, setDragOffset] = useState({ x: 0, y: 0 });
    const isDragging = useRef(false);
    const dragStart = useRef({ x: 0, y: 0 });

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
            const result = await translateText(text, 'tr');
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

    // Sticky positioning effect
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

                        // Center horizontally, position above by default
                        let x = params.left - viewerRect.left + params.width / 2;
                        let y = params.top - viewerRect.top - 12; // 12px padding above

                        // Check limits if we can get popup dimensions
                        // For now just basic tracking

                        setCurrentPosition({ x, y });
                    }
                }
            } catch (e) {
                // Range detached
            }
            animationFrameId = requestAnimationFrame(updatePosition);
        };

        animationFrameId = requestAnimationFrame(updatePosition);
        return () => cancelAnimationFrame(animationFrameId);
    }, [selectionRange]);


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

    const finalLeft = currentPosition.x + dragOffset.x;
    const finalTop = currentPosition.y + dragOffset.y;

    return (
        <div
            ref={popupRef}
            className={styles.popup}
            style={{
                left: finalLeft,
                top: finalTop,
                transform: 'translateX(-50%) translateY(-100%)', // Centered and above
            }}
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
                            <span className={styles.icon}>🌐</span>
                            <span>Çevir</span>
                        </>
                    )}
                </button>

                <button
                    className={styles.actionBtn}
                    onClick={handleAskAI}
                >
                    <span className={styles.icon}>✨</span>
                    <span>AI&apos;a Sor</span>
                </button>

                {onHighlight && (
                    <button
                        className={styles.actionBtn}
                        onClick={() => setShowColors(!showColors)}
                    >
                        <span className={styles.icon}>🖍️</span>
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
                    <span className={styles.icon}>📋</span>
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
