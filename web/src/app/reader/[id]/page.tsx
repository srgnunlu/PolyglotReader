'use client';

import { use, useState, useEffect, useCallback, useRef, useReducer } from 'react';
import { useRouter } from 'next/navigation';
import dynamic from 'next/dynamic';
import { ProtectedRoute } from '@/components/auth/ProtectedRoute';

// Dynamically import PDFViewer with SSR disabled to avoid DOMMatrix errors
const PDFViewer = dynamic(() => import('@/components/reader/PDFViewer').then(mod => mod.PDFViewer), {
    ssr: false,
    loading: () => <div className="pdf-loading-placeholder">PDF görüntüleyici yükleniyor...</div>
});
import { QuickTranslationPopup } from '@/components/reader/QuickTranslationPopup';
import { SelectionPopup } from '@/components/reader/SelectionPopup';
import { ImageSelectionPopup } from '@/components/reader/ImageSelectionPopup';
import { ChatPanel } from '@/components/chat/ChatPanel';
import { AnnotationDetailPopup } from '@/components/reader/AnnotationDetailPopup';
import { SummaryPanel } from '@/components/reader/SummaryPanel';
import { AnnotationProvider, useAnnotations } from '@/contexts/AnnotationContext';
import { Annotation } from '@/types/models';
import { getSupabase } from '@/lib/supabase';
import { PDFDocumentMetadata } from '@/types/models';
import styles from './reader.module.css';

interface PageParams {
    id: string;
}

export default function ReaderPage({ params }: { params: Promise<PageParams> }) {
    const resolvedParams = use(params);
    return (
        <ProtectedRoute>
            <AnnotationProvider fileId={resolvedParams.id}>
                <ReaderContent documentId={resolvedParams.id} />
            </AnnotationProvider>
        </ProtectedRoute>
    );
}

// Consolidated selection state
type Rect = { x: number; y: number; width: number; height: number };

interface SelectionState {
    text: string | null;
    position: { x: number; y: number } | null;
    pageNumber: number;
    rects: Rect[];
    bounds: Rect | null;
    range: Range | null;
    pageDimensions: { width: number; height: number } | null;
    image: string | null;
    imagePosition: { x: number; y: number } | null;
    chatText: string | null;
    persistentRects: Rect[];
    persistentPage: number | null;
}

type SelectionAction =
    | { type: 'TEXT_SELECT'; text: string; position: { x: number; y: number }; pageNumber: number; rects: Rect[]; bounds: Rect | null; range: Range | null; pageDimensions: { width: number; height: number } | null }
    | { type: 'IMAGE_SELECT'; image: string; position: { x: number; y: number }; pageNumber: number }
    | { type: 'CLEAR_ALL' }
    | { type: 'CLEAR_CHAT' }
    | { type: 'CLEAR_TEXT_POPUP' };

const initialSelection: SelectionState = {
    text: null, position: null, pageNumber: 1, rects: [], bounds: null,
    range: null, pageDimensions: null, image: null, imagePosition: null,
    chatText: null, persistentRects: [], persistentPage: null,
};

function selectionReducer(state: SelectionState, action: SelectionAction): SelectionState {
    switch (action.type) {
        case 'TEXT_SELECT':
            return {
                ...state,
                text: action.text, position: action.position, pageNumber: action.pageNumber,
                rects: action.rects, bounds: action.bounds, range: action.range,
                pageDimensions: action.pageDimensions,
                chatText: action.text, persistentRects: action.rects, persistentPage: action.pageNumber,
                image: null, imagePosition: null,
            };
        case 'IMAGE_SELECT':
            return {
                ...state,
                image: action.image, imagePosition: action.position, pageNumber: action.pageNumber,
                text: null, position: null,
            };
        case 'CLEAR_ALL':
            return { ...initialSelection, pageNumber: state.pageNumber };
        case 'CLEAR_CHAT':
            return {
                ...state,
                chatText: null, text: null, position: null, rects: [], bounds: null,
                range: null, persistentRects: [], persistentPage: null,
            };
        case 'CLEAR_TEXT_POPUP':
            return {
                ...state,
                text: null, position: null, rects: [], bounds: null, range: null,
                chatText: null, persistentRects: [], persistentPage: null,
            };
        default:
            return state;
    }
}

interface ReaderContentProps {
    documentId: string;
}

function ReaderContent({ documentId }: ReaderContentProps) {
    const router = useRouter();
    const supabase = getSupabase();
    const viewerRef = useRef<HTMLDivElement>(null);
    const mouseIdleTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
    const { annotations, selectedColor, setSelectedColor, addAnnotation } = useAnnotations();

    const [document, setDocument] = useState<PDFDocumentMetadata | null>(null);
    const [pdfUrl, setPdfUrl] = useState<string | null>(null);
    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [initialProgress, setInitialProgress] = useState<{ page: number; x: number; y: number; scale: number } | null>(null);

    // Consolidated selection state
    const [sel, dispatchSel] = useReducer(selectionReducer, initialSelection);

    const [isQuickTranslationMode, setIsQuickTranslationMode] = useState(false);
    const [pdfScale, setPdfScale] = useState(1.2);
    const [viewerSize, setViewerSize] = useState<{ width: number; height: number } | null>(null);

    // Chat panel state
    const [isChatOpen, setIsChatOpen] = useState(false);
    const [chatInitialMessage, setChatInitialMessage] = useState<string | undefined>();
    const [chatInitialImage, setChatInitialImage] = useState<string | undefined>();
    const [documentContext, setDocumentContext] = useState<string>('');

    // Fullscreen and auto-hide state
    const [isFullscreen, setIsFullscreen] = useState(false);
    const [isNavHidden, setIsNavHidden] = useState(false);

    // Summary panel state
    const [showSummary, setShowSummary] = useState(false);

    // Annotation detail popup
    const [selectedAnnotation, setSelectedAnnotation] = useState<{ annotation: Annotation; position: { x: number; y: number } } | null>(null);

    const handleAnnotationClick = useCallback((annotation: Annotation, position: { x: number; y: number }) => {
        setSelectedAnnotation({ annotation, position });
    }, []);

    // Handle text selection from PDF
    const handleTextSelect = useCallback((
        text: string,
        pageNumber: number,
        position: { x: number; y: number },
        rects?: Rect[],
        bounds?: Rect,
        range?: Range,
        pageDimensions?: { width: number; height: number }
    ) => {
        dispatchSel({
            type: 'TEXT_SELECT', text, position, pageNumber,
            rects: rects ?? [], bounds: bounds ?? null,
            range: range ?? null, pageDimensions: pageDimensions ?? null,
        });
    }, []);

    // Handle image selection
    const handleImageSelect = useCallback((
        imageBase64: string,
        pageNumber: number,
        position: { x: number; y: number }
    ) => {
        dispatchSel({ type: 'IMAGE_SELECT', image: imageBase64, position, pageNumber });
        window.getSelection()?.removeAllRanges();
    }, []);

    // Handle AI question from selection
    const handleAskAI = useCallback((text: string) => {
        setChatInitialMessage(text);
        dispatchSel({ type: 'CLEAR_TEXT_POPUP' });
        setIsChatOpen(true);
    }, []);

    // Handle AI question from image
    const handleAskAIWithImage = useCallback((imageBase64: string) => {
        setChatInitialImage(imageBase64);
        dispatchSel({ type: 'CLEAR_ALL' });
        setIsChatOpen(true);
    }, []);

    const clearSelection = useCallback(() => {
        dispatchSel({ type: 'CLEAR_ALL' });
    }, []);

    // Handle clearing chat selection (from chat X button)
    const handleClearChatSelection = useCallback(() => {
        window.getSelection()?.removeAllRanges();
        dispatchSel({ type: 'CLEAR_CHAT' });
    }, []);

    // Load document with AbortController
    useEffect(() => {
        const controller = new AbortController();

        const loadDocument = async () => {
            setIsLoading(true);
            setError(null);

            try {
                // Fetch document metadata
                const { data: docData, error: docError } = await supabase
                    .from('files')
                    .select('*')
                    .eq('id', documentId)
                    .single();

                if (controller.signal.aborted) return;
                if (docError) throw docError;
                if (!docData) throw new Error('Dosya bulunamadı');

                setDocument({
                    id: docData.id,
                    name: docData.name,
                    size: docData.size,
                    uploadedAt: new Date(docData.created_at),
                    storagePath: docData.storage_path,
                    thumbnailData: undefined,
                    summary: docData.summary,
                    folderId: docData.folder_id,
                    aiCategory: docData.ai_category,
                    tags: [],
                });

                // Get signed URL for PDF
                const { data: signedUrl, error: urlError } = await supabase
                    .storage
                    .from('user_files')
                    .createSignedUrl(docData.storage_path, 3600);

                if (controller.signal.aborted) return;
                if (urlError) throw urlError;
                setPdfUrl(signedUrl.signedUrl);

                // Fetch document context for AI
                const { data: chunks } = await supabase
                    .from('document_chunks')
                    .select('content')
                    .eq('file_id', documentId)
                    .limit(10);

                if (controller.signal.aborted) return;
                if (chunks) {
                    setDocumentContext(chunks.map((c: { content: string }) => c.content).join('\n\n'));
                }

                // Fetch reading progress
                const { data: progressData } = await supabase
                    .from('reading_progress')
                    .select('*')
                    .eq('file_id', documentId)
                    .eq('user_id', (await supabase.auth.getUser()).data.user?.id)
                    .maybeSingle();

                if (controller.signal.aborted) return;
                if (progressData) {
                    setInitialProgress({
                        page: progressData.page,
                        x: progressData.offset_x,
                        y: progressData.offset_y,
                        scale: progressData.zoom_scale
                    });
                    setPdfScale(progressData.zoom_scale);
                }

            } catch (err) {
                if (controller.signal.aborted) return;
                console.error('Load error:', err);
                setError(err instanceof Error ? err.message : 'Dosya yüklenemedi');
            } finally {
                if (!controller.signal.aborted) {
                    setIsLoading(false);
                }
            }
        };

        loadDocument();
        return () => controller.abort();
    }, [documentId, supabase]);

    useEffect(() => {
        if (!viewerRef.current) return;
        const observer = new ResizeObserver(entries => {
            const entry = entries[0];
            if (!entry) return;
            setViewerSize({
                width: entry.contentRect.width,
                height: entry.contentRect.height,
            });
        });
        observer.observe(viewerRef.current);
        return () => observer.disconnect();
    }, []);

    // Listen for selection changes to sync chat selection with PDF selection
    useEffect(() => {
        if (typeof window === 'undefined') return;

        const domDocument = window.document;

        const handleSelectionChange = () => {
            const selection = window.getSelection();
            if (selection?.isCollapsed && sel.chatText) {
                const activeElement = domDocument.activeElement;
                if (activeElement?.closest('[data-chat-panel="true"]')) {
                    return;
                }

                setTimeout(() => {
                    const currentSelection = window.getSelection();
                    const currentActiveElement = domDocument.activeElement;
                    if (currentSelection?.isCollapsed && !currentActiveElement?.closest('[data-chat-panel="true"]')) {
                        dispatchSel({ type: 'CLEAR_TEXT_POPUP' });
                    }
                }, 100);
            }
        };

        domDocument.addEventListener('selectionchange', handleSelectionChange);
        return () => domDocument.removeEventListener('selectionchange', handleSelectionChange);
    }, [sel.chatText]);

    // Handle highlight - save via annotation context
    const handleHighlight = useCallback(async (color: string) => {
        if (!sel.text || !documentId || !sel.rects || sel.rects.length === 0) {
            return;
        }

        try {
            await addAnnotation({
                fileId: documentId,
                pageNumber: sel.pageNumber,
                type: 'highlight',
                color: color || selectedColor,
                rects: sel.rects,
                text: sel.text,
            });

            window.getSelection()?.removeAllRanges();
            clearSelection();
        } catch (err) {
            console.error('Highlight error:', err);
        }
    }, [addAnnotation, clearSelection, documentId, sel.pageNumber, sel.text, sel.rects, selectedColor]);

    const toggleQuickTranslationMode = useCallback(() => {
        setIsQuickTranslationMode(prev => !prev);
        clearSelection();
    }, [clearSelection]);

    // Handle progress save
    const handleProgressChange = useCallback(async (page: number, x: number, y: number, scale: number) => {
        if (!documentId) return;

        try {
            const { data: { user } } = await supabase.auth.getUser();
            if (!user) return;

            await supabase
                .from('reading_progress')
                .upsert({
                    user_id: user.id,
                    file_id: documentId,
                    page,
                    offset_x: x,
                    offset_y: y,
                    zoom_scale: scale,
                    updated_at: new Date().toISOString()
                }, { onConflict: 'user_id,file_id' });

        } catch (err) {
            console.error('Error saving progress:', err);
        }
    }, [documentId, supabase]);

    // Fullscreen toggle handler
    const toggleFullscreen = useCallback(() => {
        if (!viewerRef.current) return;

        if (!globalThis.document.fullscreenElement) {
            viewerRef.current.requestFullscreen().catch(err => {
                console.error('Fullscreen error:', err);
            });
        } else {
            globalThis.document.exitFullscreen();
        }
    }, []);

    // Listen for fullscreen changes
    useEffect(() => {
        const handleFullscreenChange = () => {
            setIsFullscreen(!!globalThis.document.fullscreenElement);
            if (!globalThis.document.fullscreenElement) {
                setIsNavHidden(false);
            }
        };

        globalThis.document.addEventListener('fullscreenchange', handleFullscreenChange);
        return () => globalThis.document.removeEventListener('fullscreenchange', handleFullscreenChange);
    }, []);

    // Auto-hide navigation on mouse idle (only in fullscreen)
    const handleMouseMove = useCallback(() => {
        if (!isFullscreen) return;

        setIsNavHidden(false);

        if (mouseIdleTimeoutRef.current) {
            clearTimeout(mouseIdleTimeoutRef.current);
        }

        mouseIdleTimeoutRef.current = setTimeout(() => {
            if (isFullscreen) {
                setIsNavHidden(true);
            }
        }, 3000);
    }, [isFullscreen]);

    // Cleanup mouse idle timeout
    useEffect(() => {
        return () => {
            if (mouseIdleTimeoutRef.current) {
                clearTimeout(mouseIdleTimeoutRef.current);
            }
        };
    }, []);

    // Keyboard shortcuts (F11 for fullscreen, 1-4 for colors)
    useEffect(() => {
        const handleKeyDown = (e: KeyboardEvent) => {
            if (e.key === 'F11') {
                e.preventDefault();
                toggleFullscreen();
                return;
            }

            const target = e.target as HTMLElement;
            if (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA') return;

            const colorMap: Record<string, string> = {
                '1': '#fef08a',
                '2': '#bbf7d0',
                '3': '#bae6fd',
                '4': '#fbcfe8',
            };

            if (colorMap[e.key]) {
                setSelectedColor(colorMap[e.key]);
            }
        };

        window.addEventListener('keydown', handleKeyDown);
        return () => window.removeEventListener('keydown', handleKeyDown);
    }, [toggleFullscreen, setSelectedColor]);

    if (isLoading) {
        return (
            <div className={styles.loading}>
                <div className="spinner" style={{ width: 40, height: 40 }} />
                <p>Dosya yükleniyor...</p>
            </div>
        );
    }

    if (error || !document || !pdfUrl) {
        return (
            <div className={styles.error}>
                <span>⚠️</span>
                <p>{error || 'Dosya bulunamadı'}</p>
                <button className="btn btn-primary" onClick={() => router.push('/library')}>
                    Kütüphaneye Dön
                </button>
            </div>
        );
    }

    return (
        <div className={styles.layout}>
            {/* Header */}
            <header className={styles.header}>
                <button
                    className={styles.backBtn}
                    onClick={() => router.push('/library')}
                    title="Kütüphane"
                >
                    ←
                </button>

                <h1 className={styles.title}>{document.name}</h1>

                <button
                    onClick={() => setShowSummary(true)}
                    style={{
                        padding: '5px 12px', borderRadius: 8,
                        background: 'rgba(99,102,241,0.1)', color: 'var(--color-primary-500)',
                        border: '1px solid rgba(99,102,241,0.2)', cursor: 'pointer',
                        fontSize: '0.75rem', fontWeight: 600, whiteSpace: 'nowrap',
                        transition: 'all 0.15s', flexShrink: 0,
                    }}
                >
                    Özetle
                </button>
            </header>

            {/* Main content */}
            <div className={styles.content} onMouseMove={handleMouseMove}>
                {/* PDF Viewer */}
                <div ref={viewerRef} className={styles.viewer}>
                    <PDFViewer
                        pdfUrl={pdfUrl}
                        storagePath={document.storagePath}
                        annotations={annotations}
                        onTextSelect={handleTextSelect}
                        onImageSelect={handleImageSelect}
                        onScaleChange={setPdfScale}
                        onProgressChange={handleProgressChange}
                        initialPage={initialProgress?.page || 1}
                        initialScroll={initialProgress ? {
                            x: initialProgress.x,
                            y: initialProgress.y,
                            scale: initialProgress.scale
                        } : undefined}
                        persistentHighlightRects={sel.persistentRects}
                        persistentHighlightPageNumber={sel.persistentPage}
                        selectedColor={selectedColor}
                        onColorChange={setSelectedColor}
                        onQuickHighlight={handleHighlight}
                        isFullscreen={isFullscreen}
                        onToggleFullscreen={toggleFullscreen}
                        isNavHidden={isNavHidden}
                        isQuickTranslationMode={isQuickTranslationMode}
                        onToggleTranslation={toggleQuickTranslationMode}
                        isChatOpen={isChatOpen}
                        onToggleChat={() => setIsChatOpen(!isChatOpen)}
                    />

                    {/* Text Selection Popup */}
                    {sel.text && sel.position && !isQuickTranslationMode && (
                        <SelectionPopup
                            text={sel.text}
                            position={sel.position}
                            onClose={clearSelection}
                            onAskAI={handleAskAI}
                            onHighlight={handleHighlight}
                            selectionRange={sel.range ?? undefined}
                        />
                    )}

                    {/* Image Selection Popup */}
                    {sel.image && sel.imagePosition && (
                        <ImageSelectionPopup
                            imageBase64={sel.image}
                            position={sel.imagePosition}
                            onClose={clearSelection}
                            onAskAI={handleAskAIWithImage}
                        />
                    )}

                    {sel.text && sel.bounds && isQuickTranslationMode && (
                        <QuickTranslationPopup
                            text={sel.text}
                            anchorBounds={sel.bounds}
                            zoomScale={pdfScale}
                            containerSize={viewerSize ?? undefined}
                            onClose={clearSelection}
                            selectionRange={sel.range ?? undefined}
                        />
                    )}
                </div>

                {/* Chat Panel */}
                <ChatPanel
                    isOpen={isChatOpen}
                    onClose={() => setIsChatOpen(false)}
                    documentId={documentId}
                    documentContext={documentContext}
                    initialMessage={chatInitialMessage}
                    initialImage={chatInitialImage}
                    activeSelection={sel.chatText}
                    onClearInitialMessage={() => {
                        setChatInitialMessage(undefined);
                        setChatInitialImage(undefined);
                    }}
                    onClearSelection={handleClearChatSelection}
                />
            </div>

            {/* Summary Panel */}
            {showSummary && (
                <SummaryPanel
                    fileId={documentId}
                    documentText={documentContext}
                    existingSummary={document.summary}
                    onClose={() => setShowSummary(false)}
                />
            )}

            {/* Annotation Detail Popup */}
            {selectedAnnotation && (
                <AnnotationDetailPopup
                    annotation={selectedAnnotation.annotation}
                    position={selectedAnnotation.position}
                    onClose={() => setSelectedAnnotation(null)}
                />
            )}
        </div>
    );
}
