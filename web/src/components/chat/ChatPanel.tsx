'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { Drawer } from 'vaul';
import {
  ArrowDown,
  Download,
  Ellipsis,
  Search,
  Trash2,
  X,
} from 'lucide-react';
import { CorioLogo } from '@/components/shared/CorioLogo';
import { ChatInput } from './ChatInput';
import { ChatMessage } from './ChatMessage';
import { SuggestedPrompts } from './SuggestedPrompts';
import { useChatSession } from '@/hooks/useChatSession';
import { useIsDesktop, useMediaQuery } from '@/hooks/useMediaQuery';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';

interface ChatPanelProps {
  activeSelection?: string | null;
  currentPage?: number;
  documentContext?: string;
  documentId?: string;
  documentName?: string;
  initialImage?: string;
  initialMessage?: string;
  isOpen: boolean;
  onClearInitialMessage?: () => void;
  onClearSelection?: () => void;
  onClose: () => void;
  onNavigateToPage?: (page: number) => void;
}

const iconButton = 'flex size-9 shrink-0 items-center justify-center rounded-xl text-corio-fg/55 transition-colors hover:bg-corio-surface-2 hover:text-corio-fg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-corio-accent/40 disabled:opacity-35';

export function ChatPanel({
  activeSelection,
  currentPage,
  documentContext,
  documentId,
  documentName,
  initialImage,
  initialMessage,
  isOpen,
  onClearInitialMessage,
  onClearSelection,
  onClose,
  onNavigateToPage,
}: ChatPanelProps) {
  const isDesktop = useIsDesktop();
  const isTablet = useMediaQuery('(min-width: 768px)');
  const [draft, setDraft] = useState('');
  const [attachment, setAttachment] = useState<string | null>(null);
  const [panelWidth, setPanelWidth] = useState(() => {
    if (typeof window === 'undefined') return 420;
    const savedWidth = Number.parseInt(window.localStorage.getItem('corio-chat-width') ?? '', 10);
    return Number.isFinite(savedWidth) ? Math.min(680, Math.max(360, savedWidth)) : 420;
  });
  const [searchOpen, setSearchOpen] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [confirmClear, setConfirmClear] = useState(false);
  const [showJumpButton, setShowJumpButton] = useState(false);
  const scrollerRef = useRef<HTMLDivElement>(null);
  const isNearBottomRef = useRef(true);
  const handledInitialRef = useRef<string | null>(null);
  const resizeCleanupRef = useRef<(() => void) | null>(null);

  const session = useChatSession({
    activeSelection,
    currentPage,
    documentContext,
    documentId,
    isActive: isOpen,
  });

  useEffect(() => () => resizeCleanupRef.current?.(), []);

  useEffect(() => {
    if (!initialMessage && !initialImage) {
      handledInitialRef.current = null;
      return;
    }
    if (!isOpen || !session.isHistoryReady) return;
    const signature = `${initialMessage ?? ''}:${initialImage?.slice(0, 48) ?? ''}`;
    if (handledInitialRef.current === signature) return;
    handledInitialRef.current = signature;

    const frame = window.requestAnimationFrame(() => {
      if (initialImage) {
        setAttachment(initialImage);
        if (initialMessage) setDraft(initialMessage);
      } else if (initialMessage) {
        session.sendMessage({ text: initialMessage, selection: activeSelection });
        onClearSelection?.();
      }
      onClearInitialMessage?.();
    });
    return () => window.cancelAnimationFrame(frame);
  }, [
    activeSelection,
    initialImage,
    initialMessage,
    isOpen,
    onClearInitialMessage,
    onClearSelection,
    session,
  ]);

  const scrollToBottom = (behavior: ScrollBehavior = 'smooth') => {
    const scroller = scrollerRef.current;
    if (!scroller) return;
    scroller.scrollTo({ behavior, top: scroller.scrollHeight });
    isNearBottomRef.current = true;
    setShowJumpButton(false);
  };

  useEffect(() => {
    const lastMessage = session.messages.at(-1);
    if (!lastMessage || (!isNearBottomRef.current && lastMessage.role !== 'user')) return;
    const frame = window.requestAnimationFrame(() =>
      scrollToBottom(lastMessage.status === 'streaming' ? 'auto' : 'smooth')
    );
    return () => window.cancelAnimationFrame(frame);
  }, [session.messages]);

  useEffect(() => {
    if (!isOpen) return;
    const frame = window.requestAnimationFrame(() => scrollToBottom('auto'));
    return () => window.cancelAnimationFrame(frame);
  }, [isOpen, session.isLoadingHistory]);

  const visibleMessages = useMemo(() => {
    const query = searchQuery.trim().toLocaleLowerCase('tr-TR');
    if (!query) return session.messages;
    return session.messages.filter(message => message.text.toLocaleLowerCase('tr-TR').includes(query));
  }, [searchQuery, session.messages]);

  const lastModelId = useMemo(
    () => [...session.messages].reverse().find(message => message.role === 'model')?.id,
    [session.messages],
  );

  const handleSubmit = (text = draft) => {
    session.sendMessage({ attachment, selection: activeSelection, text });
    setDraft('');
    setAttachment(null);
    onClearSelection?.();
  };

  const handleExport = () => {
    const blob = new Blob([session.exportTranscript()], { type: 'text/markdown;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const anchor = window.document.createElement('a');
    anchor.href = url;
    anchor.download = 'corio-sohbet.md';
    anchor.click();
    window.setTimeout(() => URL.revokeObjectURL(url), 0);
  };

  const handleClose = () => {
    session.stopGenerating();
    onClose();
  };

  const handleResizeStart = (event: React.PointerEvent<HTMLDivElement>) => {
    event.preventDefault();
    const startX = event.clientX;
    const startWidth = panelWidth;

    const move = (pointerEvent: PointerEvent) => {
      const maxWidth = Math.min(680, window.innerWidth - 360);
      setPanelWidth(Math.max(360, Math.min(maxWidth, startWidth + startX - pointerEvent.clientX)));
    };
    const cleanup = () => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', cleanup);
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
      resizeCleanupRef.current = null;
      setPanelWidth(width => {
        window.localStorage.setItem('corio-chat-width', String(Math.round(width)));
        return width;
      });
    };

    resizeCleanupRef.current?.();
    resizeCleanupRef.current = cleanup;
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
    window.addEventListener('pointermove', move);
    window.addEventListener('pointerup', cleanup);
  };

  const panelContent = (
    <div className="flex h-full min-h-0 flex-col overflow-hidden bg-corio-bg text-corio-fg" data-chat-panel="true">
      <header className="shrink-0 border-b border-corio-border-subtle bg-corio-bg/92 px-3 py-2.5 backdrop-blur-xl sm:px-4">
        <div className="flex min-h-10 items-center gap-2">
          <div className="flex size-9 shrink-0 items-center justify-center rounded-xl bg-corio-accent-subtle ring-1 ring-corio-accent/10">
            <CorioLogo size={21} />
          </div>
          <div className="min-w-0 flex-1">
            <h2 className="truncate text-sm font-semibold tracking-[-0.01em]">Corio AI</h2>
            <div className="flex items-center gap-1.5 text-[11px] text-corio-fg/45">
              <span className={`size-1.5 rounded-full ${session.isLoading ? 'animate-pulse bg-corio-accent' : 'bg-corio-success'}`} />
              <span className="truncate">{session.isLoading ? 'Yanıt hazırlanıyor' : documentName ? `${documentName} ile bağlı` : 'Belgeye bağlı'}</span>
            </div>
          </div>

          {session.messages.length > 0 && (
            <button
              aria-label="Sohbette ara"
              className={iconButton}
              onClick={() => {
                setSearchOpen(open => !open);
                if (searchOpen) setSearchQuery('');
              }}
              title="Sohbette ara"
              type="button"
            >
              <Search className="size-[17px]" />
            </button>
          )}

          <DropdownMenu>
            <DropdownMenuTrigger className={iconButton} aria-label="Sohbet seçenekleri">
              <Ellipsis className="size-[18px]" />
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-52 border border-corio-border bg-corio-surface-1 text-corio-fg">
              <DropdownMenuItem disabled={session.messages.length === 0} onClick={handleExport}>
                <Download /> Sohbeti dışa aktar
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              <DropdownMenuItem
                disabled={session.messages.length === 0}
                onClick={() => setConfirmClear(true)}
                variant="destructive"
              >
                <Trash2 /> Sohbeti temizle
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>

          <button aria-label="Sohbeti kapat" className={iconButton} onClick={handleClose} title="Kapat" type="button">
            <X className="size-[18px]" />
          </button>
        </div>

        {searchOpen && (
          <div className="mt-2 flex items-center gap-2 rounded-xl border border-corio-border bg-corio-surface-1 px-2.5 py-1.5">
            <Search className="size-4 text-corio-fg/35" />
            <input
              aria-label="Sohbet mesajlarında ara"
              autoFocus
              className="min-w-0 flex-1 bg-transparent text-sm outline-none placeholder:text-corio-fg/35"
              onChange={event => setSearchQuery(event.target.value)}
              placeholder="Mesajlarda ara…"
              value={searchQuery}
            />
            <span className="text-[11px] tabular-nums text-corio-fg/40">{visibleMessages.length}</span>
            <button aria-label="Aramayı kapat" className="rounded-md p-1 hover:bg-corio-surface-2" onClick={() => { setSearchOpen(false); setSearchQuery(''); }} type="button">
              <X className="size-3.5" />
            </button>
          </div>
        )}
      </header>

      {session.error && (
        <div className="mx-3 mt-2 flex items-start gap-2 rounded-xl border border-corio-destructive/15 bg-corio-destructive/5 px-3 py-2 text-xs leading-relaxed text-corio-fg/70" role="alert">
          <span className="flex-1">{session.error}</span>
          <button aria-label="Uyarıyı kapat" className="rounded p-0.5 hover:bg-corio-destructive/10" onClick={session.dismissError} type="button">
            <X className="size-3.5" />
          </button>
        </div>
      )}

      <div
        className="relative flex-1 overflow-y-auto overscroll-contain px-3 py-5 sm:px-4"
        onScroll={event => {
          const target = event.currentTarget;
          const nearBottom = target.scrollHeight - target.scrollTop - target.clientHeight < 110;
          isNearBottomRef.current = nearBottom;
          setShowJumpButton(!nearBottom);
        }}
        ref={scrollerRef}
      >
        <div className="mx-auto flex min-h-full w-full max-w-3xl flex-col">
          {session.isLoadingHistory ? (
            <div className="space-y-5 py-2" aria-label="Sohbet geçmişi yükleniyor" role="status">
              {[0, 1, 2].map(index => (
                <div className={`flex gap-2.5 ${index === 1 ? 'justify-end' : ''}`} key={index}>
                  {index !== 1 && <div className="size-7 animate-pulse rounded-full bg-corio-surface-2" />}
                  <div className={`h-16 animate-pulse rounded-2xl bg-corio-surface-2 ${index === 1 ? 'w-2/3' : 'w-4/5'}`} />
                </div>
              ))}
            </div>
          ) : session.messages.length === 0 ? (
            <div className="flex flex-1 flex-col items-center justify-center py-7 text-center">
              <div className="mb-5 flex size-16 items-center justify-center rounded-[22px] bg-corio-accent-subtle ring-1 ring-corio-accent/10">
                <CorioLogo size={34} />
              </div>
              <h3 className="text-lg font-semibold tracking-[-0.02em]">Belgeni birlikte inceleyelim</h3>
              <p className="mb-6 mt-1.5 max-w-sm text-sm leading-relaxed text-corio-fg/50">
                Özet çıkarabilir, kavramları açıklayabilir ve yanıtları doğrudan ilgili sayfalara bağlayabilirim.
              </p>
              <SuggestedPrompts disabled={session.isLoading} onSelect={handleSubmit} prompts={session.suggestions} />
            </div>
          ) : visibleMessages.length === 0 ? (
            <div className="flex flex-1 flex-col items-center justify-center gap-2 py-20 text-center text-corio-fg/45">
              <Search className="size-6" />
              <p className="text-sm">Bu aramayla eşleşen mesaj yok.</p>
            </div>
          ) : (
            <div className="space-y-4" aria-live="polite">
              {visibleMessages.map(message => (
                <ChatMessage
                  isLastModelMessage={message.id === lastModelId}
                  key={message.id}
                  message={message}
                  onNavigateToPage={onNavigateToPage}
                  onRegenerate={session.regenerateLastResponse}
                  onRetry={message.status === 'error' ? session.retryLastResponse : undefined}
                />
              ))}
            </div>
          )}
        </div>

        {showJumpButton && (
          <button
            aria-label="Son mesaja git"
            className="sticky bottom-2 left-full flex size-9 -translate-x-1 items-center justify-center rounded-full border border-corio-border bg-corio-surface-1 text-corio-fg/65 shadow-md transition-transform hover:scale-105 hover:text-corio-fg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-corio-accent/40"
            onClick={() => scrollToBottom()}
            type="button"
          >
            <ArrowDown className="size-4" />
          </button>
        )}
      </div>

      <div className="shrink-0 border-t border-corio-border-subtle bg-corio-bg/94 backdrop-blur-xl">
        <ChatInput
          activeSelection={activeSelection}
          attachment={attachment}
          autoFocus={isOpen && session.isHistoryReady && session.messages.length === 0}
          draft={draft}
          isLoading={session.isLoading}
          onAttachmentChange={setAttachment}
          onDraftChange={setDraft}
          onRemoveSelection={onClearSelection}
          onStop={session.stopGenerating}
          onSubmit={() => handleSubmit()}
        />
      </div>
    </div>
  );

  if (!isOpen) return null;

  const clearDialog = (
    <Dialog onOpenChange={setConfirmClear} open={confirmClear}>
      <DialogContent className="border border-corio-border bg-corio-surface-1 text-corio-fg" showCloseButton={false}>
        <DialogHeader>
          <DialogTitle>Sohbet temizlensin mi?</DialogTitle>
          <DialogDescription>Bu belgeye ait tüm sohbet geçmişi kalıcı olarak silinecek.</DialogDescription>
        </DialogHeader>
        <DialogFooter className="border-corio-border-subtle bg-corio-surface-2/60">
          <button className="rounded-xl border border-corio-border px-3 py-2 text-sm font-medium hover:bg-corio-surface-3" onClick={() => setConfirmClear(false)} type="button">
            Vazgeç
          </button>
          <button
            className="rounded-xl bg-corio-destructive px-3 py-2 text-sm font-medium text-white hover:opacity-90"
            onClick={() => void session.clearHistory().then(() => setConfirmClear(false)).catch(() => undefined)}
            type="button"
          >
            Kalıcı olarak sil
          </button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );

  if (isDesktop) {
    return (
      <>
        <aside
          aria-label="Corio AI sohbet paneli"
          className="relative h-full min-w-[360px] max-w-[680px] shrink-0 border-l border-corio-border-subtle bg-corio-bg shadow-[-14px_0_40px_rgba(42,37,32,0.06)]"
          style={{ width: panelWidth }}
        >
          <div
            aria-hidden="true"
            className="absolute inset-y-0 -left-1 z-20 w-2 cursor-col-resize transition-colors hover:bg-corio-accent/20"
            onPointerDown={handleResizeStart}
          />
          {panelContent}
        </aside>
        {clearDialog}
      </>
    );
  }

  return (
    <>
      <Drawer.Root
        direction={isTablet ? 'right' : 'bottom'}
        fixed
        handleOnly={!isTablet}
        modal
        onOpenChange={open => { if (!open) handleClose(); }}
        open={isOpen}
      >
        <Drawer.Portal>
          <Drawer.Overlay className="fixed inset-0 z-[70] bg-black/30 backdrop-blur-[2px]" />
          <Drawer.Content
            className={
              isTablet
                ? 'fixed inset-y-0 right-0 z-[80] w-[min(470px,92vw)] border-l border-corio-border bg-corio-bg shadow-2xl outline-none'
                : 'fixed inset-x-0 bottom-0 z-[80] h-[94dvh] overflow-hidden rounded-t-[28px] border border-b-0 border-corio-border bg-corio-bg shadow-2xl outline-none'
            }
          >
            <Drawer.Title className="sr-only">Corio AI sohbeti</Drawer.Title>
            <Drawer.Description className="sr-only">Belgeniz hakkında soru sorun.</Drawer.Description>
            {!isTablet && (
              <div className="absolute inset-x-0 top-2 z-30 flex justify-center">
                <Drawer.Handle className="!m-0 h-1.5 w-12 rounded-full bg-corio-fg/18" />
              </div>
            )}
            <div className={!isTablet ? 'h-full pt-3' : 'h-full'}>{panelContent}</div>
          </Drawer.Content>
        </Drawer.Portal>
      </Drawer.Root>
      {clearDialog}
    </>
  );
}
