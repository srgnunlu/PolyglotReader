'use client';

import { useState, useRef, useEffect } from 'react';
import {
    ChevronLeftIcon,
    ChevronRightIcon,
    ZoomInIcon,
    ZoomOutIcon,
    FitWidthIcon,
    MaximizeIcon,
    MinimizeIcon,
    TranslateIcon,
    SparklesIcon,
    MoreHorizontalIcon,
} from './ReaderIcons';
import styles from './PDFToolbar.module.css';

const HIGHLIGHT_COLORS = [
    { name: 'Sari', value: '#fef08a', shortcut: '1' },
    { name: 'Yesil', value: '#bbf7d0', shortcut: '2' },
    { name: 'Mavi', value: '#bae6fd', shortcut: '3' },
    { name: 'Pembe', value: '#fbcfe8', shortcut: '4' },
];

interface PDFToolbarProps {
    currentPage: number;
    totalPages: number;
    displayScale: number;
    selectedColor: string;
    isFullscreen: boolean;
    isNavHidden: boolean;
    isQuickTranslationMode: boolean;
    isChatOpen: boolean;
    isMobile: boolean;
    onGoToPage: (page: number) => void;
    onZoomIn: () => void;
    onZoomOut: () => void;
    onFitToWidth: () => void;
    onColorChange: (color: string) => void;
    onQuickHighlight: (color: string) => void;
    onToggleFullscreen: () => void;
    onToggleTranslation: () => void;
    onToggleChat: () => void;
}

export function PDFToolbar({
    currentPage,
    totalPages,
    displayScale,
    selectedColor,
    isFullscreen,
    isNavHidden,
    isQuickTranslationMode,
    isChatOpen,
    isMobile,
    onGoToPage,
    onZoomIn,
    onZoomOut,
    onFitToWidth,
    onColorChange,
    onQuickHighlight,
    onToggleFullscreen,
    onToggleTranslation,
    onToggleChat,
}: PDFToolbarProps) {
    const [showMoreTools, setShowMoreTools] = useState(false);
    const moreToolsRef = useRef<HTMLDivElement>(null);

    // Close more tools dropdown when clicking outside
    useEffect(() => {
        if (!showMoreTools) return;
        const handleClick = (e: MouseEvent) => {
            if (moreToolsRef.current && !moreToolsRef.current.contains(e.target as Node)) {
                setShowMoreTools(false);
            }
        };
        document.addEventListener('mousedown', handleClick);
        return () => document.removeEventListener('mousedown', handleClick);
    }, [showMoreTools]);

    return (
        <div
            className={`${styles.toolbar} ${isNavHidden ? styles.toolbarHidden : ''}`}
            data-pdf-toolbar="true"
        >
            {/* Page Navigation */}
            <div className={styles.group}>
                <button
                    className={styles.btn}
                    onClick={() => onGoToPage(currentPage - 1)}
                    disabled={currentPage <= 1}
                    title="Onceki sayfa"
                >
                    <ChevronLeftIcon size={16} />
                </button>
                <span className={styles.pageInfo}>
                    <input
                        type="number"
                        value={currentPage}
                        onChange={(e) => onGoToPage(parseInt(e.target.value) || 1)}
                        min={1}
                        max={totalPages}
                        className={styles.pageInput}
                    />
                    <span>/ {totalPages || 0}</span>
                </span>
                <button
                    className={styles.btn}
                    onClick={() => onGoToPage(currentPage + 1)}
                    disabled={currentPage >= totalPages}
                    title="Sonraki sayfa"
                >
                    <ChevronRightIcon size={16} />
                </button>
            </div>

            <div className={styles.divider} />

            {/* Zoom Controls */}
            <div className={styles.group}>
                <button className={styles.btn} onClick={onZoomOut} title="Uzaklastir">
                    <ZoomOutIcon size={16} />
                </button>
                <span className={styles.zoomInfo}>{Math.round(displayScale * 100)}%</span>
                <button className={styles.btn} onClick={onZoomIn} title="Yakinlastir">
                    <ZoomInIcon size={16} />
                </button>
                <button className={styles.btn} onClick={onFitToWidth} title="Sigdir">
                    <FitWidthIcon size={16} />
                </button>
            </div>

            <div className={styles.divider} />

            {/* Desktop: all tools inline */}
            {!isMobile && (
                <>
                    {/* Color Picker */}
                    <div className={`${styles.group} ${styles.colorGroup}`}>
                        {HIGHLIGHT_COLORS.map(({ name, value, shortcut }) => (
                            <button
                                key={value}
                                className={`${styles.colorBtn} ${selectedColor === value ? styles.colorBtnActive : ''}`}
                                style={{ backgroundColor: value }}
                                onMouseDown={(e) => e.preventDefault()}
                                onClick={() => {
                                    onColorChange(value);
                                    onQuickHighlight(value);
                                }}
                                title={`${name} (${shortcut})`}
                            />
                        ))}
                    </div>

                    <div className={styles.divider} />

                    {/* Translation & Chat */}
                    <div className={styles.group}>
                        <button
                            className={`${styles.btn} ${isQuickTranslationMode ? styles.btnActive : ''}`}
                            onClick={onToggleTranslation}
                            title={isQuickTranslationMode ? 'Hizli ceviri modu acik' : 'Hizli ceviri modu'}
                        >
                            <TranslateIcon size={16} />
                        </button>
                        <button
                            className={`${styles.btn} ${isChatOpen ? styles.btnActive : ''}`}
                            onClick={onToggleChat}
                            title="AI Sohbet"
                        >
                            <SparklesIcon size={16} />
                        </button>
                    </div>

                    <div className={styles.divider} />

                    {/* Fullscreen */}
                    <div className={styles.group}>
                        <button
                            className={`${styles.btn} ${isFullscreen ? styles.btnActive : ''}`}
                            onClick={onToggleFullscreen}
                            title={isFullscreen ? 'Tam ekrandan cik (ESC)' : 'Tam ekran (F11)'}
                        >
                            {isFullscreen ? <MinimizeIcon size={16} /> : <MaximizeIcon size={16} />}
                        </button>
                    </div>
                </>
            )}

            {/* Mobile: overflow menu */}
            {isMobile && (
                <>
                    <div className={styles.group}>
                        <button
                            className={`${styles.btn} ${isQuickTranslationMode ? styles.btnActive : ''}`}
                            onClick={onToggleTranslation}
                            title="Hizli ceviri"
                        >
                            <TranslateIcon size={16} />
                        </button>
                        <button
                            className={`${styles.btn} ${isChatOpen ? styles.btnActive : ''}`}
                            onClick={onToggleChat}
                            title="AI Sohbet"
                        >
                            <SparklesIcon size={16} />
                        </button>
                    </div>

                    <div className={`${styles.group} ${styles.moreContainer}`} ref={moreToolsRef}>
                        <button
                            className={`${styles.btn} ${showMoreTools ? styles.btnActive : ''}`}
                            onClick={() => setShowMoreTools(!showMoreTools)}
                            title="Daha fazla"
                        >
                            <MoreHorizontalIcon size={16} />
                        </button>
                        {showMoreTools && (
                            <div className={styles.moreDropdown}>
                                <div className={styles.moreSection}>
                                    <span className={styles.moreLabel}>Renk</span>
                                    <div className={styles.moreColors}>
                                        {HIGHLIGHT_COLORS.map(({ name, value }) => (
                                            <button
                                                key={value}
                                                className={`${styles.colorBtn} ${selectedColor === value ? styles.colorBtnActive : ''}`}
                                                style={{ backgroundColor: value }}
                                                onMouseDown={(e) => e.preventDefault()}
                                                onClick={() => {
                                                    onColorChange(value);
                                                    onQuickHighlight(value);
                                                    setShowMoreTools(false);
                                                }}
                                                title={name}
                                            />
                                        ))}
                                    </div>
                                </div>
                                <button
                                    className={styles.moreItem}
                                    onClick={() => {
                                        onToggleFullscreen();
                                        setShowMoreTools(false);
                                    }}
                                >
                                    {isFullscreen ? <MinimizeIcon size={16} /> : <MaximizeIcon size={16} />}
                                    <span>{isFullscreen ? 'Tam ekrandan cik' : 'Tam ekran'}</span>
                                </button>
                            </div>
                        )}
                    </div>
                </>
            )}
        </div>
    );
}
