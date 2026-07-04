// OCR affordance for scanned pages: a floating button appears when the
// current page has no text layer (selection can't work there), and a side
// panel shows the Gemini-recognized text with the cached translate flow.
'use client';

import { useCallback, useState, type RefObject } from 'react';
import type { pdfjs } from 'react-pdf';
import { ScanText, Languages, Loader2, X } from 'lucide-react';
import { recognizePageText } from '@/lib/gemini';
import { translateTextCached } from '@/lib/translationCache';
import { useScannedPageDetection } from '@/hooks/useScannedPageDetection';

// OCR results per (document, page) survive panel close and page navigation so
// re-clicking an already recognized page is instant and costs no API call.
const ocrResultCache = new Map<string, string>();

interface OCRPanelProps {
    pdf: pdfjs.PDFDocumentProxy | null;
    currentPage: number;
    containerRef: RefObject<HTMLDivElement | null>;
    /** Stable identity of the open document (storage path or URL). */
    documentKey: string;
}

export function OCRPanel({ pdf, currentPage, containerRef, documentKey }: OCRPanelProps) {
    const isScanned = useScannedPageDetection(pdf, currentPage);

    const [isOpen, setIsOpen] = useState(false);
    // The page the panel content belongs to — scrolling away must not swap
    // the displayed result under the user.
    const [ocrPage, setOcrPage] = useState<number | null>(null);
    const [text, setText] = useState<string | null>(null);
    const [isRecognizing, setIsRecognizing] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const [translation, setTranslation] = useState<string | null>(null);
    const [isTranslating, setIsTranslating] = useState(false);

    const runOCR = useCallback(async () => {
        const page = currentPage;
        setIsOpen(true);
        setOcrPage(page);
        setError(null);
        setTranslation(null);

        const cacheKey = `${documentKey}::${page}`;
        const cached = ocrResultCache.get(cacheKey);
        if (cached !== undefined) {
            setText(cached);
            return;
        }

        // The current page is always inside the render window, so its canvas
        // exists once react-pdf finishes painting it.
        const canvas = containerRef.current?.querySelector<HTMLCanvasElement>(
            `[data-page-number="${page}"] canvas`
        );
        if (!canvas) {
            setText(null);
            setError('Sayfa henüz hazır değil. Sayfa yüklendikten sonra tekrar deneyin.');
            return;
        }

        setIsRecognizing(true);
        setText(null);
        try {
            const imageDataUrl = canvas.toDataURL('image/jpeg', 0.85);
            const recognized = await recognizePageText(imageDataUrl);
            ocrResultCache.set(cacheKey, recognized);
            setText(recognized);
        } catch (err) {
            console.error('OCR error:', err);
            setError('Metin tanınamadı. Lütfen tekrar deneyin.');
        } finally {
            setIsRecognizing(false);
        }
    }, [containerRef, currentPage, documentKey]);

    const handleTranslate = useCallback(async () => {
        if (!text || isTranslating) return;
        setIsTranslating(true);
        try {
            // Same two-layer cached flow as the selection popup's "Çevir".
            const result = await translateTextCached(text, 'tr');
            setTranslation(result);
        } catch (err) {
            console.error('OCR translation error:', err);
            setTranslation('Çeviri yapılamadı');
        } finally {
            setIsTranslating(false);
        }
    }, [text, isTranslating]);

    const handleClose = () => {
        setIsOpen(false);
        setError(null);
        setTranslation(null);
    };

    const hasEmptyResult = text !== null && text.trim().length === 0;

    return (
        <>
            {isScanned && !isOpen && (
                <button
                    onClick={runOCR}
                    className="absolute bottom-6 left-1/2 z-20 flex -translate-x-1/2 items-center gap-2 whitespace-nowrap rounded-full border border-corio-border bg-corio-surface-1 px-4 py-2 text-sm font-medium text-corio-fg shadow-lg transition-colors hover:bg-corio-surface-2"
                >
                    <ScanText className="size-4 text-corio-accent" />
                    Taranmış sayfa — metni tanı (OCR)
                </button>
            )}

            {isOpen && (
                <div className="flex h-full w-80 shrink-0 flex-col border-l border-corio-border bg-corio-surface-1">
                    <div className="flex items-center justify-between border-b border-corio-border px-3 py-2.5">
                        <div className="flex items-center gap-2 text-sm font-medium text-corio-fg">
                            <ScanText className="size-4 text-corio-accent" />
                            Metin Tanıma{ocrPage !== null && ` — Sayfa ${ocrPage}`}
                        </div>
                        <button
                            onClick={handleClose}
                            className="rounded-lg p-1 text-corio-fg/50 transition-colors hover:bg-corio-surface-2 hover:text-corio-fg"
                            aria-label="Metin tanımayı kapat"
                        >
                            <X className="size-4" />
                        </button>
                    </div>

                    <div className="flex-1 overflow-y-auto p-3">
                        {isRecognizing && (
                            <div className="flex items-center justify-center gap-2 py-10 text-sm text-corio-fg/50">
                                <Loader2 className="size-4 animate-spin" />
                                Metin tanınıyor...
                            </div>
                        )}
                        {error && (
                            <div className="px-2 py-10 text-center text-sm text-corio-fg/50">{error}</div>
                        )}
                        {hasEmptyResult && (
                            <div className="px-2 py-10 text-center text-sm text-corio-fg/50">
                                Bu sayfada okunabilir metin bulunamadı.
                            </div>
                        )}
                        {text !== null && !hasEmptyResult && (
                            <>
                                <p className="select-text whitespace-pre-wrap text-sm leading-relaxed text-corio-fg/90">
                                    {text}
                                </p>
                                {translation && (
                                    <div className="mt-3 rounded-lg border border-corio-border bg-corio-surface-2 p-2.5">
                                        <div className="mb-1 text-xs font-semibold uppercase tracking-wide text-corio-accent">
                                            Çeviri
                                        </div>
                                        <p className="select-text whitespace-pre-wrap text-sm leading-relaxed text-corio-fg">
                                            {translation}
                                        </p>
                                    </div>
                                )}
                            </>
                        )}
                    </div>

                    {text !== null && !hasEmptyResult && (
                        <div className="border-t border-corio-border p-2">
                            <button
                                onClick={handleTranslate}
                                disabled={isTranslating}
                                className="flex w-full items-center justify-center gap-2 rounded-lg border border-corio-border bg-corio-bg py-2 text-sm font-medium text-corio-fg transition-colors hover:bg-corio-surface-2 disabled:cursor-not-allowed disabled:opacity-50"
                            >
                                {isTranslating ? (
                                    <Loader2 className="size-4 animate-spin" />
                                ) : (
                                    <Languages className="size-4 text-corio-accent" />
                                )}
                                Çevir
                            </button>
                        </div>
                    )}
                </div>
            )}
        </>
    );
}
