'use client';

import { useState, useEffect, useRef, useCallback } from 'react';
import { getAccessToken } from '@/lib/supabase';
import { useDraggable } from '@/hooks/useDraggable';
import {
    TranslateIcon,
    SparklesIcon,
    HighlighterIcon,
    CopyIcon,
    CheckIcon,
    XIcon,
    PinIcon,
} from './ReaderIcons';
import styles from './SmartSelectionPopup.module.css';

const HIGHLIGHT_COLORS = [
    { name: 'Sari', color: '#fef08a' },
    { name: 'Yesil', color: '#bbf7d0' },
    { name: 'Mavi', color: '#bae6fd' },
    { name: 'Pembe', color: '#fbcfe8' },
];

interface SmartSelectionPopupProps {
    text: string;
    position: { x: number; y: number };
    anchorBounds?: { x: number; y: number; width: number; height: number };
    selectionRange?: Range;
    isQuickTranslationMode?: boolean;
    onClose: () => void;
    onAskAI: (text: string) => void;
    onHighlight?: (color: string) => void;
}

export function SmartSelectionPopup({
    text,
    position,
    anchorBounds,
    selectionRange,
    isQuickTranslationMode = false,
    onClose,
    onAskAI,
    onHighlight,
}: SmartSelectionPopupProps) {
    const popupRef = useRef<HTMLDivElement>(null);
    const [translation, setTranslation] = useState<string | null>(null);
    const [isTranslating, setIsTranslating] = useState(false);
    const [translationError, setTranslationError] = useState<string | null>(null);
    const [showColors, setShowColors] = useState(false);
    const [copied, setCopied] = useState(false);
    const [isPinned, setIsPinned] = useState(false);
    const requestIdRef = useRef(0);

    // Compute sticky position from selection range
    const [stickyPosition, setStickyPosition] = useState(position);

    useEffect(() => {
        if (!selectionRange || isPinned) return;

        let raf: number;
        const update = () => {
            try {
                if (selectionRange.commonAncestorContainer.isConnected) {
                    const rect = selectionRange.getBoundingClientRect();
                    const viewerEl = popupRef.current?.offsetParent as HTMLElement;
                    if (viewerEl) {
                        const viewerRect = viewerEl.getBoundingClientRect();
                        setStickyPosition({
                            x: rect.left - viewerRect.left + rect.width / 2,
                            y: rect.top - viewerRect.top - 12,
                        });
                    }
                }
            } catch {
                // Range detached
            }
            raf = requestAnimationFrame(update);
        };
        raf = requestAnimationFrame(update);
        return () => cancelAnimationFrame(raf);
    }, [selectionRange, isPinned]);

    // Draggable
    const { position: dragPosition, isDragging, dragHandleProps } = useDraggable({
        initialPosition: stickyPosition,
        boundaryRef: popupRef.current?.offsetParent
            ? { current: popupRef.current.offsetParent as HTMLElement }
            : undefined,
    });

    // Auto-translate in quick mode
    useEffect(() => {
        if (!isQuickTranslationMode || !text.trim()) return;

        const timer = setTimeout(() => {
            handleTranslate();
        }, 300);

        return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [text, isQuickTranslationMode]);

    const handleTranslate = useCallback(async () => {
        if (isTranslating) return;

        const requestId = ++requestIdRef.current;
        setIsTranslating(true);
        setTranslationError(null);

        try {
            const token = await getAccessToken();
            const res = await fetch('/api/translate', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    ...(token ? { Authorization: `Bearer ${token}` } : {}),
                },
                body: JSON.stringify({ text, targetLang: 'tr' }),
            });
            const data = await res.json();

            if (requestIdRef.current !== requestId) return;
            if (data.error) throw new Error(data.error);

            setTranslation(data.translation?.trim() || 'Ceviri sonucu bos');
        } catch (err) {
            if (requestIdRef.current !== requestId) return;
            console.error('Translation error:', err);
            setTranslationError('Ceviri yapilamadi. Tekrar deneyin.');
        } finally {
            if (requestIdRef.current === requestId) {
                setIsTranslating(false);
            }
        }
    }, [isTranslating, text]);

    const handleAskAI = useCallback(() => {
        onAskAI(text);
        onClose();
    }, [onAskAI, text, onClose]);

    const handleHighlight = useCallback((color: string) => {
        onHighlight?.(color);
        onClose();
    }, [onHighlight, onClose]);

    const handleCopy = useCallback(() => {
        navigator.clipboard.writeText(text);
        setCopied(true);
        setTimeout(() => setCopied(false), 1500);
    }, [text]);

    // Close on click outside
    useEffect(() => {
        const handleOutsideClick = (e: MouseEvent | TouchEvent) => {
            if (isDragging) return;
            const target = e.target as HTMLElement;
            if (!target || !popupRef.current) return;
            if (popupRef.current.contains(target)) return;
            if (target.closest('[data-chat-panel="true"]')) return;
            if (target.closest('[data-pdf-toolbar="true"]')) return;
            if (isPinned) return;
            onClose();
        };

        const handleEscape = (e: KeyboardEvent) => {
            if (e.key === 'Escape') onClose();
        };

        document.addEventListener('mousedown', handleOutsideClick);
        document.addEventListener('touchstart', handleOutsideClick);
        document.addEventListener('keydown', handleEscape);

        return () => {
            document.removeEventListener('mousedown', handleOutsideClick);
            document.removeEventListener('touchstart', handleOutsideClick);
            document.removeEventListener('keydown', handleEscape);
        };
    }, [onClose, isDragging, isPinned]);

    // Keyboard shortcuts
    useEffect(() => {
        const handleKey = (e: KeyboardEvent) => {
            if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) return;

            switch (e.key.toLowerCase()) {
                case 't':
                    e.preventDefault();
                    handleTranslate();
                    break;
                case 'a':
                    e.preventDefault();
                    handleAskAI();
                    break;
                case 'c':
                    if (!e.ctrlKey && !e.metaKey) {
                        e.preventDefault();
                        handleCopy();
                    }
                    break;
            }
        };

        document.addEventListener('keydown', handleKey);
        return () => document.removeEventListener('keydown', handleKey);
    }, [handleTranslate, handleAskAI, handleCopy]);

    // Quick translation mode layout
    if (isQuickTranslationMode) {
        return (
            <div
                ref={popupRef}
                className={`${styles.popup} ${styles.quickMode}`}
                style={{
                    left: dragPosition.x,
                    top: dragPosition.y,
                    transform: 'translateX(-50%) translateY(-100%)',
                }}
            >
                <div className={styles.dragHandle} {...dragHandleProps}>
                    <div className={styles.dragIndicator} />
                </div>

                <div className={styles.quickModeHeader}>
                    <span className={styles.quickModeTitle}>
                        <TranslateIcon size={14} />
                        Ceviri
                    </span>
                    <button className={styles.quickModeClose} onClick={onClose} title="Kapat">
                        <XIcon size={14} />
                    </button>
                </div>

                <div className={styles.translationSection}>
                    <div className={styles.translationContent}>
                        {isTranslating ? (
                            <span className={styles.loadingDots}>
                                <span className={styles.dot} />
                                <span className={styles.dot} />
                                <span className={styles.dot} />
                            </span>
                        ) : translationError ? (
                            <span className={styles.translationText} style={{ color: 'var(--color-error)' }}>
                                {translationError}
                            </span>
                        ) : translation ? (
                            <span className={styles.translationText}>{translation}</span>
                        ) : null}
                    </div>
                </div>

                {/* Secondary actions */}
                <div className={styles.actions}>
                    <button className={styles.actionBtn} onClick={handleAskAI}>
                        <span className={styles.actionIcon}><SparklesIcon size={16} /></span>
                        <span>AI&apos;a Sor</span>
                    </button>
                    {onHighlight && (
                        <button
                            className={`${styles.actionBtn} ${showColors ? styles.actionBtnActive : ''}`}
                            onClick={() => setShowColors(!showColors)}
                        >
                            <span className={styles.actionIcon}><HighlighterIcon size={16} /></span>
                            <span>Isaretle</span>
                        </button>
                    )}
                    <button className={styles.actionBtn} onClick={handleCopy}>
                        <span className={styles.actionIcon}>
                            {copied ? <CheckIcon size={16} /> : <CopyIcon size={16} />}
                        </span>
                        <span>{copied ? 'Kopyalandi' : 'Kopyala'}</span>
                    </button>
                </div>

                {showColors && onHighlight && (
                    <div className={styles.colorPicker}>
                        {HIGHLIGHT_COLORS.map(({ name, color }) => (
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
            </div>
        );
    }

    // Standard mode layout
    return (
        <div
            ref={popupRef}
            className={`${styles.popup} ${isPinned ? styles.popupPinned : ''}`}
            style={{
                left: dragPosition.x,
                top: dragPosition.y,
                transform: 'translateX(-50%) translateY(-100%)',
            }}
        >
            <div className={styles.dragHandle} {...dragHandleProps}>
                <div className={styles.dragIndicator} />
                <button
                    className={`${styles.pinBtn} ${isPinned ? styles.pinBtnActive : ''}`}
                    onClick={() => setIsPinned(!isPinned)}
                    title={isPinned ? 'Sabitlemeyi kaldir' : 'Sabitle'}
                >
                    <PinIcon size={12} />
                </button>
            </div>

            {/* Main actions */}
            <div className={styles.actions}>
                <button
                    className={`${styles.actionBtn} ${(translation || isTranslating) ? styles.actionBtnActive : ''}`}
                    onClick={handleTranslate}
                    disabled={isTranslating}
                >
                    <span className={styles.actionIcon}>
                        {isTranslating ? <span className={styles.spinner} /> : <TranslateIcon size={18} />}
                    </span>
                    <span>Cevir</span>
                </button>

                <button className={styles.actionBtn} onClick={handleAskAI}>
                    <span className={styles.actionIcon}><SparklesIcon size={18} /></span>
                    <span>AI&apos;a Sor</span>
                </button>

                {onHighlight && (
                    <button
                        className={`${styles.actionBtn} ${showColors ? styles.actionBtnActive : ''}`}
                        onClick={() => setShowColors(!showColors)}
                    >
                        <span className={styles.actionIcon}><HighlighterIcon size={18} /></span>
                        <span>Isaretle</span>
                    </button>
                )}

                <button className={styles.actionBtn} onClick={handleCopy}>
                    <span className={styles.actionIcon}>
                        {copied ? <CheckIcon size={18} /> : <CopyIcon size={18} />}
                    </span>
                    <span>{copied ? 'Kopyalandi' : 'Kopyala'}</span>
                </button>
            </div>

            {/* Color picker */}
            {showColors && onHighlight && (
                <div className={styles.colorPicker}>
                    {HIGHLIGHT_COLORS.map(({ name, color }) => (
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

            {/* Inline translation result */}
            {(translation || translationError) && (
                <div className={styles.translationSection}>
                    <div className={styles.translationHeader}>
                        <span className={styles.translationLabel}>Ceviri</span>
                        <button
                            className={styles.translationClose}
                            onClick={() => {
                                setTranslation(null);
                                setTranslationError(null);
                            }}
                        >
                            <XIcon size={12} />
                        </button>
                    </div>
                    <div className={styles.translationContent}>
                        <span className={styles.translationText}>
                            {translationError || translation}
                        </span>
                    </div>
                </div>
            )}

            {/* Selected text preview */}
            <div className={styles.preview}>
                <p className={styles.previewText}>
                    {text.length > 120 ? text.slice(0, 120) + '...' : text}
                </p>
            </div>
        </div>
    );
}
