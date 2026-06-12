// Reader toolbar: page navigation, zoom, highlight colors, translation/chat/fullscreen toggles
'use client';

// Highlight colors (shortcuts 1-4 are handled by the reader page)
export const HIGHLIGHT_COLORS = [
    { name: 'Sarı', value: '#fef08a', shortcut: '1' },
    { name: 'Yeşil', value: '#bbf7d0', shortcut: '2' },
    { name: 'Mavi', value: '#bae6fd', shortcut: '3' },
    { name: 'Pembe', value: '#fbcfe8', shortcut: '4' },
];

interface PDFToolbarProps {
    currentPage: number;
    totalPages: number;
    displayScale: number;
    goToPage: (page: number) => void;
    zoomIn: () => void;
    zoomOut: () => void;
    resetZoom: () => void;
    selectedColor: string;
    onColorChange?: (color: string) => void;
    onQuickHighlight?: (color: string) => void;
    isQuickTranslationMode: boolean;
    onToggleTranslation?: () => void;
    isChatOpen: boolean;
    onToggleChat?: () => void;
    isFullscreen: boolean;
    onToggleFullscreen?: () => void;
    isNavHidden: boolean;
}

export function PDFToolbar({
    currentPage,
    totalPages,
    displayScale,
    goToPage,
    zoomIn,
    zoomOut,
    resetZoom,
    selectedColor,
    onColorChange,
    onQuickHighlight,
    isQuickTranslationMode,
    onToggleTranslation,
    isChatOpen,
    onToggleChat,
    isFullscreen,
    onToggleFullscreen,
    isNavHidden,
}: PDFToolbarProps) {
    return (
        <div className={`pdf-toolbar ${isNavHidden ? 'toolbar-hidden' : ''}`} data-pdf-toolbar="true">
            {/* Page Navigation */}
            <div className="pdf-toolbar-group">
                <button
                    className="pdf-toolbar-btn"
                    onClick={() => goToPage(currentPage - 1)}
                    disabled={currentPage <= 1}
                    title="Önceki sayfa"
                >
                    ←
                </button>
                <span className="pdf-page-info">
                    <input
                        type="number"
                        value={currentPage}
                        onChange={(e) => goToPage(parseInt(e.target.value) || 1)}
                        min={1}
                        max={totalPages}
                        className="pdf-page-input"
                    />
                    <span>/ {totalPages || 0}</span>
                </span>
                <button
                    className="pdf-toolbar-btn"
                    onClick={() => goToPage(currentPage + 1)}
                    disabled={currentPage >= totalPages}
                    title="Sonraki sayfa"
                >
                    →
                </button>
            </div>

            {/* Zoom Controls */}
            <div className="pdf-toolbar-group">
                <button className="pdf-toolbar-btn" onClick={zoomOut} title="Uzaklaştır">−</button>
                <span className="pdf-zoom-info">{Math.round(displayScale * 100)}%</span>
                <button className="pdf-toolbar-btn" onClick={zoomIn} title="Yakınlaştır">+</button>
                <button className="pdf-toolbar-btn" onClick={resetZoom} title="Sıfırla">↺</button>
            </div>

            {/* Color Picker - Click to highlight selection */}
            <div className="pdf-toolbar-group pdf-color-group">
                {HIGHLIGHT_COLORS.map(({ name, value, shortcut }) => (
                    <button
                        key={value}
                        className={`pdf-color-btn ${selectedColor === value ? 'active' : ''}`}
                        style={{ backgroundColor: value }}
                        onMouseDown={(e) => e.preventDefault()} // Preserve text selection
                        onClick={() => {
                            onColorChange?.(value);
                            onQuickHighlight?.(value);
                        }}
                        title={`${name} (${shortcut})`}
                    />
                ))}
            </div>

            {/* Translation Toggle */}
            <div className="pdf-toolbar-group">
                <button
                    className={`pdf-toolbar-btn pdf-translation-btn ${isQuickTranslationMode ? 'active' : ''}`}
                    onClick={onToggleTranslation}
                    title={isQuickTranslationMode ? 'Hızlı çeviri modu açık' : 'Hızlı çeviri modu'}
                >
                    🌐
                </button>
                <button
                    className={`pdf-toolbar-btn pdf-chat-btn ${isChatOpen ? 'active' : ''}`}
                    onClick={onToggleChat}
                    title="AI Sohbet"
                >
                    ✨
                </button>
            </div>

            {/* Fullscreen Button */}
            <div className="pdf-toolbar-group">
                <button
                    className={`pdf-toolbar-btn pdf-fullscreen-btn ${isFullscreen ? 'active' : ''}`}
                    onClick={onToggleFullscreen}
                    title={isFullscreen ? 'Tam ekrandan çık (ESC)' : 'Tam ekran (F11)'}
                >
                    {isFullscreen ? '⛶' : '⛶'}
                </button>
            </div>

            <style jsx>{`
        .pdf-toolbar {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 24px;
          padding: 12px 16px;
          background: var(--bg-secondary);
          border-bottom: 1px solid var(--border-color);
          transition: opacity 0.3s ease, transform 0.3s ease;
          z-index: 100;
        }

        .pdf-toolbar-group {
          display: flex;
          align-items: center;
          gap: 8px;
        }

        .pdf-toolbar-btn {
          width: 32px;
          height: 32px;
          display: flex;
          align-items: center;
          justify-content: center;
          background: var(--bg-tertiary);
          border: 1px solid var(--border-color);
          border-radius: var(--radius-md);
          color: var(--text-primary);
          font-size: 1rem;
          cursor: pointer;
          transition: all var(--transition-fast);
        }

        .pdf-toolbar-btn:hover:not(:disabled) {
          background: var(--color-primary-500);
          color: white;
          border-color: var(--color-primary-500);
        }

        .pdf-toolbar-btn:disabled {
          opacity: 0.4;
          cursor: not-allowed;
        }

        /* Auto-hide toolbar */
        .toolbar-hidden {
          opacity: 0;
          pointer-events: none;
          transform: translateY(-100%);
        }

        /* Color picker buttons */
        .pdf-color-group {
          gap: 6px;
          padding: 0 8px;
          border-left: 1px solid var(--border-color);
          border-right: 1px solid var(--border-color);
        }

        .pdf-color-btn {
          width: 24px;
          height: 24px;
          border-radius: 50%;
          border: 2px solid transparent;
          cursor: pointer;
          transition: all 0.2s ease;
          box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }

        .pdf-color-btn:hover {
          transform: scale(1.15);
          box-shadow: 0 2px 6px rgba(0,0,0,0.2);
        }

        .pdf-color-btn.active {
          border-color: var(--text-primary);
          transform: scale(1.1);
          box-shadow: 0 0 0 2px var(--bg-secondary), 0 0 0 4px var(--color-primary-500);
        }

        /* Fullscreen button */
        .pdf-fullscreen-btn {
          font-size: 1.25rem;
        }

        .pdf-fullscreen-btn.active,
        .pdf-translation-btn.active,
        .pdf-chat-btn.active {
          background: var(--color-primary-500);
          color: white;
          border-color: var(--color-primary-500);
        }

        .pdf-page-info {
          display: flex;
          align-items: center;
          gap: 4px;
          font-size: 0.875rem;
          color: var(--text-secondary);
        }

        .pdf-page-input {
          width: 48px;
          padding: 4px 8px;
          text-align: center;
          background: var(--bg-tertiary);
          border: 1px solid var(--border-color);
          border-radius: var(--radius-sm);
          color: var(--text-primary);
          font-size: 0.875rem;
        }

        .pdf-page-input:focus {
          outline: none;
          border-color: var(--color-primary-500);
        }

        .pdf-zoom-info {
          min-width: 48px;
          text-align: center;
          font-size: 0.875rem;
          color: var(--text-secondary);
        }
      `}</style>
        </div>
    );
}
