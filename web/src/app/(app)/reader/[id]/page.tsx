// Reader page — PDF viewer with chat, annotations, translation popups
'use client';

import { use, useState, useEffect, useCallback, useRef } from 'react';
import { useRouter } from 'next/navigation';
import dynamic from 'next/dynamic';
import { ProtectedRoute } from '@/components/auth/ProtectedRoute';
import { ArrowLeft } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';

const PDFViewer = dynamic(() => import('@/components/reader/PDFViewer').then(mod => mod.PDFViewer), {
  ssr: false,
  loading: () => (
    <div className="flex flex-1 items-center justify-center bg-corio-reader">
      <Skeleton className="h-[600px] w-[450px] rounded-lg" />
    </div>
  ),
});
// Selection popups and the chat panel are pulled in lazily — they carry heavy
// deps (translation logic, react-markdown, RAG/Gemini clients) that aren't
// needed until the user actually selects text or opens chat (Phase B perf —
// route-level code splitting).
const QuickTranslationPopup = dynamic(
  () => import('@/components/reader/QuickTranslationPopup').then(mod => mod.QuickTranslationPopup),
  { ssr: false }
);
const SelectionPopup = dynamic(
  () => import('@/components/reader/SelectionPopup').then(mod => mod.SelectionPopup),
  { ssr: false }
);
const ImageSelectionPopup = dynamic(
  () => import('@/components/reader/ImageSelectionPopup').then(mod => mod.ImageSelectionPopup),
  { ssr: false }
);
const ChatPanel = dynamic(
  () => import('@/components/chat/ChatPanel').then(mod => mod.ChatPanel),
  { ssr: false }
);
import { ReadingProgress } from '@/components/reader/ReadingProgress';
import { useAnnotationStore } from '@/stores/useAnnotationStore';
import { useReaderStore } from '@/stores/useReaderStore';
import { getSupabase } from '@/lib/supabase';
import { PDFDocumentMetadata } from '@/types/models';

interface PageParams { id: string }

export default function ReaderPage({ params }: { params: Promise<PageParams> }) {
  const resolvedParams = use(params);
  return (
    <ProtectedRoute>
      <ReaderContent documentId={resolvedParams.id} />
    </ProtectedRoute>
  );
}

function ReaderContent({ documentId }: { documentId: string }) {
  const router = useRouter();
  const supabase = getSupabase();
  const viewerRef = useRef<HTMLDivElement>(null);
  const mouseIdleTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  // Chat citation'ları PDF'te sayfaya atlatır; PDFViewer register eder.
  const goToPageRef = useRef<((page: number) => void) | null>(null);
  const {
    annotations, selectedColor, setSelectedColor, addAnnotation,
    loadFileAnnotations, reset: resetAnnotations,
  } = useAnnotationStore();
  const {
    isChatOpen, isTranslationMode, toggleChat, toggleTranslationMode,
    setChatOpen, reset: resetReaderUI,
  } = useReaderStore();

  // Load annotations for this document; clear store state when leaving.
  useEffect(() => {
    loadFileAnnotations(documentId);
    return () => {
      resetAnnotations();
      resetReaderUI();
    };
  }, [documentId, loadFileAnnotations, resetAnnotations, resetReaderUI]);

  const [document, setDocument] = useState<PDFDocumentMetadata | null>(null);
  const [pdfUrl, setPdfUrl] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [initialProgress, setInitialProgress] = useState<{ page: number; x: number; y: number; scale: number } | null>(null);

  // Selection state
  const [selectedText, setSelectedText] = useState<string | null>(null);
  const [selectionPosition, setSelectionPosition] = useState<{ x: number; y: number } | null>(null);
  const [selectedPageNumber, setSelectedPageNumber] = useState<number>(1);
  const [selectionRects, setSelectionRects] = useState<{ x: number; y: number; width: number; height: number }[]>([]);
  const [selectionBounds, setSelectionBounds] = useState<{ x: number; y: number; width: number; height: number } | null>(null);
  const [selectionRange, setSelectionRange] = useState<Range | null>(null);
  const [selectedImage, setSelectedImage] = useState<string | null>(null);
  const [imageSelectionPos, setImageSelectionPos] = useState<{ x: number; y: number } | null>(null);

  // Persistent chat selection
  const [chatSelectedText, setChatSelectedText] = useState<string | null>(null);
  const [persistentHighlightRects, setPersistentHighlightRects] = useState<{ x: number; y: number; width: number; height: number }[]>([]);
  const [persistentHighlightPage, setPersistentHighlightPage] = useState<number | null>(null);
  // UI state
  const [pdfScale, setPdfScale] = useState(1.2);
  const [currentPage, setCurrentPage] = useState(1);
  const [totalPages, setTotalPages] = useState(0);
  const [viewerSize, setViewerSize] = useState<{ width: number; height: number } | null>(null);
  const [chatInitialMessage, setChatInitialMessage] = useState<string | undefined>();
  const [chatInitialImage, setChatInitialImage] = useState<string | undefined>();
  const [documentContext, setDocumentContext] = useState<string>('');
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [isNavHidden, setIsNavHidden] = useState(false);

  const readingProgress = totalPages > 0 ? (currentPage / totalPages) * 100 : 0;

  // Selection handlers
  const handleTextSelect = useCallback((
    text: string, pageNumber: number, position: { x: number; y: number },
    rects?: { x: number; y: number; width: number; height: number }[],
    bounds?: { x: number; y: number; width: number; height: number },
    range?: Range, _pageDimensions?: { width: number; height: number }
  ) => {
    setSelectedText(text);
    setSelectionPosition(position);
    setSelectedPageNumber(pageNumber);
    setSelectionRects(rects ?? []);
    setSelectionBounds(bounds ?? null);
    setSelectionRange(range ?? null);
    setChatSelectedText(text);
    setPersistentHighlightRects(rects ?? []);
    setPersistentHighlightPage(pageNumber);
    setSelectedImage(null);
    setImageSelectionPos(null);
  }, []);

  const handleImageSelect = useCallback((imageBase64: string, pageNumber: number, position: { x: number; y: number }) => {
    setSelectedImage(imageBase64);
    setImageSelectionPos(position);
    setSelectedPageNumber(pageNumber);
    setSelectedText(null);
    setSelectionPosition(null);
    window.getSelection()?.removeAllRanges();
  }, []);

  const handleAskAI = useCallback((text: string) => {
    setChatInitialMessage(text);
    setSelectedText(null);
    setSelectionPosition(null);
    setChatOpen(true);
  }, [setChatOpen]);

  const handleAskAIWithImage = useCallback((imageBase64: string) => {
    setChatInitialImage(imageBase64);
    setSelectedImage(null);
    setImageSelectionPos(null);
    setChatOpen(true);
  }, [setChatOpen]);

  const clearSelection = useCallback(() => {
    setSelectedText(null);
    setSelectionPosition(null);
    setSelectionRects([]);
    setSelectionBounds(null);
    setSelectionRange(null);
    setSelectedImage(null);
    setImageSelectionPos(null);
    setSelectedPageNumber(1);
    setChatSelectedText(null);
    setPersistentHighlightRects([]);
    setPersistentHighlightPage(null);
  }, []);

  const handleClearChatSelection = useCallback(() => {
    setChatSelectedText(null);
    window.getSelection()?.removeAllRanges();
    setSelectedText(null);
    setSelectionPosition(null);
    setSelectionRects([]);
    setSelectionBounds(null);
    setSelectionRange(null);
    setPersistentHighlightRects([]);
    setPersistentHighlightPage(null);
  }, []);

  // Document loading
  useEffect(() => {
    const loadDocument = async () => {
      setIsLoading(true);
      setError(null);
      try {
        const { data: docData, error: docError } = await supabase
          .from('files').select('*').eq('id', documentId).single();
        if (docError) throw docError;
        if (!docData) throw new Error('Dosya bulunamadı');

        setDocument({
          id: docData.id, name: docData.name, size: docData.size,
          uploadedAt: new Date(docData.created_at), storagePath: docData.storage_path,
          thumbnailData: undefined, summary: docData.summary,
          folderId: docData.folder_id, aiCategory: docData.ai_category, tags: [],
        });

        // Independent reads run together instead of in a serial waterfall.
        // reading_progress relies on RLS (auth.uid() = user_id) plus the
        // UNIQUE(user_id, file_id) constraint, so a file_id filter already
        // returns just this user's row — no getUser() round-trip needed.
        const [signedUrlRes, chunksRes, progressRes] = await Promise.all([
          supabase.storage.from('user_files').createSignedUrl(docData.storage_path, 3600),
          supabase.from('document_chunks').select('content').eq('file_id', documentId).limit(10),
          supabase.from('reading_progress').select('*').eq('file_id', documentId).maybeSingle(),
        ]);

        if (signedUrlRes.error) throw signedUrlRes.error;
        setPdfUrl(signedUrlRes.data.signedUrl);

        const chunks = chunksRes.data;
        if (chunks) setDocumentContext(chunks.map((c: { content: string }) => c.content).join('\n\n'));

        const progressData = progressRes.data;
        if (progressData) {
          setInitialProgress({ page: progressData.page, x: progressData.offset_x, y: progressData.offset_y, scale: progressData.zoom_scale });
          setPdfScale(progressData.zoom_scale);
          setSelectedPageNumber(progressData.page);
        }
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Dosya yüklenemedi');
      } finally {
        setIsLoading(false);
      }
    };
    loadDocument();
  }, [documentId, supabase]);

  // Viewer resize observer
  useEffect(() => {
    if (!viewerRef.current) return;
    const observer = new ResizeObserver(entries => {
      const entry = entries[0];
      if (entry) setViewerSize({ width: entry.contentRect.width, height: entry.contentRect.height });
    });
    observer.observe(viewerRef.current);
    return () => observer.disconnect();
  }, []);

  // Selection change listener — clears selection state when user clicks away
  const chatSelectedTextRef = useRef(chatSelectedText);
  chatSelectedTextRef.current = chatSelectedText;

  useEffect(() => {
    if (typeof window === 'undefined') return;
    const domDoc = window.document;
    let timeoutId: ReturnType<typeof setTimeout>;

    const handleSelectionChange = () => {
      const sel = window.getSelection();
      if (!sel?.isCollapsed || !chatSelectedTextRef.current) return;
      if (domDoc.activeElement?.closest('[data-chat-panel="true"]')) return;

      clearTimeout(timeoutId);
      timeoutId = setTimeout(() => {
        const current = window.getSelection();
        if (current?.isCollapsed && !domDoc.activeElement?.closest('[data-chat-panel="true"]')) {
          clearSelection();
        }
      }, 150);
    };

    domDoc.addEventListener('selectionchange', handleSelectionChange);
    return () => {
      domDoc.removeEventListener('selectionchange', handleSelectionChange);
      clearTimeout(timeoutId);
    };
  }, [clearSelection]);

  // Highlight handler
  const handleHighlight = useCallback(async (color: string) => {
    if (!selectedText || !documentId || !selectionRects.length) return;
    try {
      await addAnnotation({
        fileId: documentId, pageNumber: selectedPageNumber, type: 'highlight',
        color: color || selectedColor, rects: selectionRects, text: selectedText,
      });
      window.getSelection()?.removeAllRanges();
      clearSelection();
    } catch (err) {
      console.error('Highlight error:', err);
    }
  }, [addAnnotation, clearSelection, documentId, selectedPageNumber, selectedText, selectionRects, selectedColor]);

  const toggleQuickTranslationMode = useCallback(() => {
    toggleTranslationMode();
    clearSelection();
  }, [toggleTranslationMode, clearSelection]);

  // Progress save
  const handleProgressChange = useCallback(async (page: number, x: number, y: number, scale: number) => {
    if (!documentId) return;
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;
      await supabase.from('reading_progress').upsert({
        user_id: user.id, file_id: documentId, page, offset_x: x, offset_y: y,
        zoom_scale: scale, updated_at: new Date().toISOString(),
      }, { onConflict: 'user_id,file_id' });
    } catch (err) {
      console.error('Error saving progress:', err);
    }
  }, [documentId, supabase]);

  // Fullscreen
  const toggleFullscreen = useCallback(() => {
    if (!viewerRef.current) return;
    if (!globalThis.document.fullscreenElement) {
      viewerRef.current.requestFullscreen().catch(() => {});
    } else {
      globalThis.document.exitFullscreen();
    }
  }, []);

  useEffect(() => {
    const handler = () => {
      setIsFullscreen(!!globalThis.document.fullscreenElement);
      if (!globalThis.document.fullscreenElement) setIsNavHidden(false);
    };
    globalThis.document.addEventListener('fullscreenchange', handler);
    return () => globalThis.document.removeEventListener('fullscreenchange', handler);
  }, []);

  // Auto-hide on idle in fullscreen
  const handleMouseMove = useCallback(() => {
    if (!isFullscreen) return;
    setIsNavHidden(false);
    if (mouseIdleTimeoutRef.current) clearTimeout(mouseIdleTimeoutRef.current);
    mouseIdleTimeoutRef.current = setTimeout(() => {
      if (isFullscreen) setIsNavHidden(true);
    }, 3000);
  }, [isFullscreen]);

  useEffect(() => () => { if (mouseIdleTimeoutRef.current) clearTimeout(mouseIdleTimeoutRef.current) }, []);

  // Keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'F11') { e.preventDefault(); toggleFullscreen(); return; }
      const target = e.target as HTMLElement;
      if (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA') return;
      const colorMap: Record<string, string> = { '1': '#fef08a', '2': '#bbf7d0', '3': '#bae6fd', '4': '#fbcfe8' };
      if (colorMap[e.key]) setSelectedColor(colorMap[e.key]);
      if ((e.metaKey || e.ctrlKey) && e.key === 'j') { e.preventDefault(); toggleChat(); }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [toggleFullscreen, setSelectedColor, toggleChat]);

  if (isLoading) {
    return (
      <div className="flex h-screen flex-col items-center justify-center gap-4 bg-corio-bg text-corio-fg/60">
        <div className="h-10 w-10 animate-spin rounded-full border-2 border-corio-border border-t-corio-accent" />
        <p>Dosya yükleniyor...</p>
      </div>
    );
  }

  if (error || !document || !pdfUrl) {
    return (
      <div className="flex h-screen flex-col items-center justify-center gap-4 bg-corio-bg text-corio-fg/60">
        <span className="text-5xl">⚠️</span>
        <p className="text-lg">{error || 'Dosya bulunamadı'}</p>
        <Button onClick={() => router.push('/library')} className="bg-corio-accent text-white hover:bg-corio-accent-hover">
          Kütüphaneye Dön
        </Button>
      </div>
    );
  }

  return (
    <div className="flex h-screen flex-col overflow-hidden bg-corio-bg">
      {/* Reading progress */}
      <ReadingProgress progress={readingProgress} />

      {/* Header */}
      <header className={`flex items-center gap-3 border-b border-corio-border bg-corio-surface-1 px-4 py-2.5 transition-all ${isNavHidden ? 'opacity-0 pointer-events-none -translate-y-full' : ''}`}>
        <Button variant="ghost" size="sm" onClick={() => router.push('/library')} className="text-corio-fg/60 hover:text-corio-fg">
          <ArrowLeft className="mr-1 h-4 w-4" />
          Kütüphane
        </Button>
        <h1 className="flex-1 truncate text-sm font-medium text-corio-fg">{document.name}</h1>
      </header>

      {/* Main content */}
      <div className="flex flex-1 overflow-hidden" onMouseMove={handleMouseMove}>
        {/* PDF Viewer */}
        <div ref={viewerRef} className="relative flex-1 overflow-hidden">
          <PDFViewer
            pdfUrl={pdfUrl}
            storagePath={document.storagePath}
            documentName={document.name}
            annotations={annotations}
            onTextSelect={handleTextSelect}
            onImageSelect={handleImageSelect}
            onPageChange={(page: number) => setCurrentPage(page)}
            onRegisterGoToPage={(fn: (page: number) => void) => { goToPageRef.current = fn; }}
            onTotalPagesChange={setTotalPages}
            onScaleChange={setPdfScale}
            onProgressChange={handleProgressChange}
            initialPage={initialProgress?.page || 1}
            initialScroll={initialProgress ? { x: initialProgress.x, y: initialProgress.y, scale: initialProgress.scale } : undefined}
            persistentHighlightRects={persistentHighlightRects}
            persistentHighlightPageNumber={persistentHighlightPage}
            selectedColor={selectedColor}
            onColorChange={setSelectedColor}
            onQuickHighlight={handleHighlight}
            isFullscreen={isFullscreen}
            onToggleFullscreen={toggleFullscreen}
            isNavHidden={isNavHidden}
            isQuickTranslationMode={isTranslationMode}
            onToggleTranslation={toggleQuickTranslationMode}
            isChatOpen={isChatOpen}
            onToggleChat={toggleChat}
          />

          {/* Text selection popup */}
          {selectedText && selectionPosition && !isTranslationMode && (
            <SelectionPopup text={selectedText} position={selectionPosition} onClose={clearSelection}
              onAskAI={handleAskAI} onHighlight={handleHighlight} selectionRange={selectionRange ?? undefined} />
          )}

          {/* Image selection popup */}
          {selectedImage && imageSelectionPos && (
            <ImageSelectionPopup imageBase64={selectedImage} position={imageSelectionPos}
              onClose={clearSelection} onAskAI={handleAskAIWithImage} />
          )}

          {/* Quick translation popup */}
          {selectedText && selectionBounds && isTranslationMode && (
            <QuickTranslationPopup text={selectedText} anchorBounds={selectionBounds}
              zoomScale={pdfScale} containerSize={viewerSize ?? undefined}
              onClose={clearSelection} selectionRange={selectionRange ?? undefined} />
          )}
        </div>

        {/* Chat Panel */}
        <ChatPanel isOpen={isChatOpen} onClose={() => setChatOpen(false)}
          documentId={documentId} documentContext={documentContext}
          documentName={document.name} currentPage={currentPage}
          initialMessage={chatInitialMessage} initialImage={chatInitialImage}
          activeSelection={chatSelectedText}
          onClearInitialMessage={() => { setChatInitialMessage(undefined); setChatInitialImage(undefined); }}
          onClearSelection={handleClearChatSelection}
          onNavigateToPage={(page: number) => goToPageRef.current?.(page)} />
      </div>

      {/* Bottom bar — reading progress summary */}
      <div className={`flex items-center justify-between border-t border-corio-border bg-corio-surface-1 px-4 py-1.5 text-xs text-corio-fg/50 transition-all ${isNavHidden ? 'opacity-0 pointer-events-none translate-y-full' : ''}`}>
        <span>Sayfa {currentPage} / {totalPages}</span>
        <span>{totalPages > 0 ? Math.round(readingProgress) : 0}% okundu</span>
      </div>
    </div>
  );
}
