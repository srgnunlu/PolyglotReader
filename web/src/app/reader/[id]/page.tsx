'use client';

import { use, useState, useEffect, useCallback, useRef } from 'react';
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
import { AnnotationProvider, useAnnotations } from '@/contexts/AnnotationContext';
import { AnnotationToolbar } from '@/components/annotations/AnnotationToolbar';
import { getSupabase } from '@/lib/supabase';
import { PDFDocumentMetadata, Annotation } from '@/types/models';
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

interface ReaderContentProps {
    documentId: string;
}

function ReaderContent({ documentId }: ReaderContentProps) {
    const router = useRouter();
    const supabase = getSupabase();
    const viewerRef = useRef<HTMLDivElement>(null);
    const { annotations, selectedTool, selectedColor, addAnnotation } = useAnnotations();

    const [document, setDocument] = useState<PDFDocumentMetadata | null>(null);
    const [pdfUrl, setPdfUrl] = useState<string | null>(null);
    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [initialProgress, setInitialProgress] = useState<{ page: number; x: number; y: number; scale: number } | null>(null);

    // Selection popup state
    const [selectedText, setSelectedText] = useState<string | null>(null);
    const [selectionPosition, setSelectionPosition] = useState<{ x: number; y: number } | null>(null);
    const [selectedPageNumber, setSelectedPageNumber] = useState<number>(1);
    const [selectionRects, setSelectionRects] = useState<{ x: number; y: number; width: number; height: number }[]>([]);
    const [selectionBounds, setSelectionBounds] = useState<{ x: number; y: number; width: number; height: number } | null>(null);
    const [selectionRange, setSelectionRange] = useState<Range | null>(null);
    const [selectedImage, setSelectedImage] = useState<string | null>(null);
    const [imageSelectionPos, setImageSelectionPos] = useState<{ x: number; y: number } | null>(null);

    // Persistent chat selection (survives when browser clears visual selection)
    const [chatSelectedText, setChatSelectedText] = useState<string | null>(null);
    // Persistent highlight rects for visual indication on PDF when browser selection clears
    const [persistentHighlightRects, setPersistentHighlightRects] = useState<{ x: number; y: number; width: number; height: number }[]>([]);
    const [persistentHighlightPage, setPersistentHighlightPage] = useState<number | null>(null);
    // Store page dimensions for coordinate conversion to iOS format
    const [currentPageDimensions, setCurrentPageDimensions] = useState<{ width: number; height: number } | null>(null);

    const [isQuickTranslationMode, setIsQuickTranslationMode] = useState(false);
    const [pdfScale, setPdfScale] = useState(1.2);
    const [viewerSize, setViewerSize] = useState<{ width: number; height: number } | null>(null);

    // Chat panel state
    const [isChatOpen, setIsChatOpen] = useState(false);
    const [chatInitialMessage, setChatInitialMessage] = useState<string | undefined>();
    const [chatInitialImage, setChatInitialImage] = useState<string | undefined>();
    const [documentContext, setDocumentContext] = useState<string>('');

    // ... (existing code)

    // Handle text selection from PDF
    const handleTextSelect = useCallback((
        text: string,
        pageNumber: number,
        position: { x: number; y: number },
        rects?: { x: number; y: number; width: number; height: number }[],
        bounds?: { x: number; y: number; width: number; height: number },
        range?: Range,
        pageDimensions?: { width: number; height: number }
    ) => {
        setSelectedText(text);
        setSelectionPosition(position);
        setSelectedPageNumber(pageNumber);
        setSelectionRects(rects ?? []);
        setSelectionBounds(bounds ?? null);
        setSelectionRange(range ?? null);
        setCurrentPageDimensions(pageDimensions ?? null); // Store for coordinate conversion

        // Also set persistent chat selection and persistent highlight
        setChatSelectedText(text);
        setPersistentHighlightRects(rects ?? []);
        setPersistentHighlightPage(pageNumber);

        // Clear image selection
        setSelectedImage(null);
        setImageSelectionPos(null);
    }, []);

    // Handle image selection
    const handleImageSelect = useCallback((
        imageBase64: string,
        pageNumber: number,
        position: { x: number; y: number }
    ) => {
        setSelectedImage(imageBase64);
        setImageSelectionPos(position);
        setSelectedPageNumber(pageNumber);

        // Clear text selection
        setSelectedText(null);
        setSelectionPosition(null);
        window.getSelection()?.removeAllRanges();
    }, []);

    // Handle AI question from selection
    const handleAskAI = useCallback((text: string) => {
        setChatInitialMessage(text);
        // Clear selections
        setSelectedText(null);
        setSelectionPosition(null);
        setIsChatOpen(true);
    }, []);

    // Handle AI question from image
    const handleAskAIWithImage = useCallback((imageBase64: string) => {
        setChatInitialImage(imageBase64);
        // Clear selections
        setSelectedImage(null);
        setImageSelectionPos(null);
        setIsChatOpen(true);
    }, []);

    const clearSelection = useCallback(() => {
        setSelectedText(null);
        setSelectionPosition(null);
        setSelectionRects([]);
        setSelectionBounds(null);
        setSelectionRange(null);
        setSelectedImage(null);
        setImageSelectionPos(null);
        setSelectedPageNumber(1);
        // Also clear chat selection and persistent highlight when PDF selection is cleared
        setChatSelectedText(null);
        setPersistentHighlightRects([]);
        setPersistentHighlightPage(null);
    }, []);

    // Handle clearing chat selection (from chat X button)
    const handleClearChatSelection = useCallback(() => {
        setChatSelectedText(null);
        // Also clear browser selection
        window.getSelection()?.removeAllRanges();
        // Clear popup state
        setSelectedText(null);
        setSelectionPosition(null);
        setSelectionRects([]);
        setSelectionBounds(null);
        setSelectionRange(null);
        // Also clear persistent highlight
        setPersistentHighlightRects([]);
        setPersistentHighlightPage(null);
    }, []);

    // ... (existing code until return)


    useEffect(() => {
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

                if (docError) throw docError;
                if (!docData) throw new Error('Dosya bulunamadı');

                setDocument({
                    id: docData.id,
                    name: docData.name,
                    size: docData.size,
                    uploadedAt: new Date(docData.created_at),
                    storagePath: docData.storage_path,
                    thumbnailData: undefined, // Not stored in files table
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

                if (urlError) throw urlError;
                setPdfUrl(signedUrl.signedUrl);

                // Annotations are now loaded by AnnotationProvider via context

                // Fetch document context for AI
                const { data: chunks } = await supabase
                    .from('document_chunks')
                    .select('content')
                    .eq('file_id', documentId)
                    .limit(10);

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

                if (progressData) {
                    setInitialProgress({
                        page: progressData.page,
                        x: progressData.offset_x,
                        y: progressData.offset_y,
                        scale: progressData.zoom_scale
                    });
                    setPdfScale(progressData.zoom_scale);
                    setSelectedPageNumber(progressData.page); // Set initial page
                }

            } catch (err) {
                console.error('Load error:', err);
                setError(err instanceof Error ? err.message : 'Dosya yüklenemedi');
            } finally {
                setIsLoading(false);
            }
        };

        loadDocument();
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

        const domDocument = window.document; // Use window.document to get DOM document

        const handleSelectionChange = () => {
            const selection = window.getSelection();
            // If selection is collapsed (empty) and we have chat text selected, clear it
            if (selection?.isCollapsed && chatSelectedText) {
                // Check if the active element is inside the chat panel - if so, don't clear
                const activeElement = domDocument.activeElement;
                if (activeElement?.closest('[data-chat-panel="true"]')) {
                    return; // Don't clear selection when interacting with chat
                }

                // Small delay to avoid clearing during text selection process
                setTimeout(() => {
                    const currentSelection = window.getSelection();
                    // Re-check if still collapsed and not in chat panel
                    const currentActiveElement = domDocument.activeElement;
                    if (currentSelection?.isCollapsed && !currentActiveElement?.closest('[data-chat-panel="true"]')) {
                        setChatSelectedText(null);
                        setSelectedText(null);
                        setSelectionPosition(null);
                        setSelectionRects([]);
                        setSelectionBounds(null);
                        setSelectionRange(null);
                        setPersistentHighlightRects([]);
                        setPersistentHighlightPage(null);
                    }
                }, 100);
            }
        };

        domDocument.addEventListener('selectionchange', handleSelectionChange);
        return () => domDocument.removeEventListener('selectionchange', handleSelectionChange);
    }, [chatSelectedText]);

    // Handle highlight - save via annotation context
    const handleHighlight = useCallback(async (color: string) => {
        if (!selectedText || !documentId || !selectionRects || selectionRects.length === 0) {
            console.error('Invalid selection for highlighting');
            return;
        }

        try {
            // Save percentage rects for web display
            // iOS PDFAnnotationHandler will ignore these (values ≤100 appear invalid)
            // and fall back to text search using the text field
            await addAnnotation({
                fileId: documentId,
                pageNumber: selectedPageNumber,
                type: selectedTool || 'highlight',
                color: color || selectedColor,  // Popup color takes priority
                rects: selectionRects,  // Percentage coords for web, iOS ignores and uses text search
                text: selectedText,  // Required for iOS text search fallback
            });

            // Clear selection after successful highlight
            window.getSelection()?.removeAllRanges();
            clearSelection();
        } catch (err) {
            console.error('Highlight error:', err);
        }
    }, [addAnnotation, clearSelection, documentId, selectedPageNumber, selectedText, selectionRects, selectedTool, selectedColor]);

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

            // Updated debounce logic or just upsert
            // Since onProgressChange is already debounced in PDFViewer, we can just save
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
                >
                    ← Kütüphane
                </button>

                <h1 className={styles.title}>{document.name}</h1>

                <div className={styles.headerActions}>
                    <button
                        className={`${styles.translationToggle} ${isQuickTranslationMode ? styles.translationToggleActive : ''}`}
                        onClick={toggleQuickTranslationMode}
                        title={isQuickTranslationMode ? 'Hızlı çeviri modu açık' : 'Hızlı çeviri modu kapalı'}
                    >
                        <span className={styles.translationIcon}>🌐</span>
                        {isQuickTranslationMode && (
                            <span className={styles.translationLabel}>Çeviri Açık</span>
                        )}
                    </button>
                    <button
                        className={`${styles.headerBtn} ${isChatOpen ? styles.headerBtnActive : ''}`}
                        onClick={() => setIsChatOpen(!isChatOpen)}
                        title="AI Sohbet"
                    >
                        ✨
                    </button>
                </div>
            </header>

            {/* Annotation Toolbar */}
            <AnnotationToolbar />

            {/* Main content */}
            <div className={styles.content}>
                {/* PDF Viewer */}
                {/* PDF Viewer */}
                <div ref={viewerRef} className={styles.viewer}>
                    <PDFViewer
                        pdfUrl={pdfUrl}
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
                        persistentHighlightRects={persistentHighlightRects}
                        persistentHighlightPageNumber={persistentHighlightPage}
                    />

                    {/* Text Selection Popup */}
                    {selectedText && selectionPosition && !isQuickTranslationMode && (
                        <SelectionPopup
                            text={selectedText}
                            position={selectionPosition}
                            onClose={clearSelection}
                            onAskAI={handleAskAI}
                            onHighlight={handleHighlight}
                            selectionRange={selectionRange ?? undefined}
                        />
                    )}

                    {/* Image Selection Popup */}
                    {selectedImage && imageSelectionPos && (
                        <ImageSelectionPopup
                            imageBase64={selectedImage}
                            position={imageSelectionPos}
                            onClose={clearSelection}
                            onAskAI={handleAskAIWithImage}
                        />
                    )}

                    {selectedText && selectionBounds && isQuickTranslationMode && (
                        <QuickTranslationPopup
                            text={selectedText}
                            anchorBounds={selectionBounds}
                            zoomScale={pdfScale}
                            containerSize={viewerSize ?? undefined}
                            onClose={clearSelection}
                            selectionRange={selectionRange ?? undefined}
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
                    activeSelection={chatSelectedText}
                    onClearInitialMessage={() => {
                        setChatInitialMessage(undefined);
                        setChatInitialImage(undefined);
                    }}
                    onClearSelection={handleClearChatSelection}
                />
            </div>
        </div>
    );
}
