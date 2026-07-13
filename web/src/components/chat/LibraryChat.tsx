'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import {
  BookOpenText,
  Check,
  Download,
  FileText,
  Library,
  Loader2,
  RotateCcw,
  Search,
  Sparkles,
  X,
} from 'lucide-react';
import { useDocuments } from '@/hooks/useDocuments';
import { useLibraryChatSession } from '@/hooks/useLibraryChatSession';
import { CorioLogo } from '@/components/shared/CorioLogo';
import { ChatInput } from './ChatInput';
import { ChatMessage } from './ChatMessage';
import { SuggestedPrompts } from './SuggestedPrompts';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';

const DEFAULT_SUGGESTIONS = [
  'Dokümanlarımda hangi ana konular işleniyor?',
  'Bu belgeler arasındaki ortak temaları karşılaştır',
  'En önemli bulguları kaynaklarıyla özetle',
];

export function LibraryChat() {
  const { documents, isLoading: documentsLoading } = useDocuments();
  const [draft, setDraft] = useState('');
  const [selectedIds, setSelectedIds] = useState<Set<string> | null>(null);
  const [sourcePickerOpen, setSourcePickerOpen] = useState(false);
  const [sourceQuery, setSourceQuery] = useState('');
  const [confirmClear, setConfirmClear] = useState(false);
  const [showJumpButton, setShowJumpButton] = useState(false);
  const scrollerRef = useRef<HTMLDivElement>(null);
  const nearBottomRef = useRef(true);

  const activeFiles = useMemo(
    () => documents
      .filter(document => selectedIds === null || selectedIds.has(document.id))
      .map(document => ({ id: document.id, name: document.name })),
    [documents, selectedIds],
  );
  const filteredDocuments = useMemo(() => {
    const query = sourceQuery.trim().toLocaleLowerCase('tr-TR');
    return query
      ? documents.filter(document => document.name.toLocaleLowerCase('tr-TR').includes(query))
      : documents;
  }, [documents, sourceQuery]);
  const session = useLibraryChatSession(activeFiles);
  const lastModelId = useMemo(
    () => [...session.messages].reverse().find(message => message.role === 'model')?.id,
    [session.messages],
  );

  const scrollToBottom = (behavior: ScrollBehavior = 'smooth') => {
    const scroller = scrollerRef.current;
    if (!scroller) return;
    scroller.scrollTo({ behavior, top: scroller.scrollHeight });
    nearBottomRef.current = true;
    setShowJumpButton(false);
  };

  useEffect(() => {
    const last = session.messages.at(-1);
    if (!last || (!nearBottomRef.current && last.role !== 'user')) return;
    const frame = window.requestAnimationFrame(() =>
      scrollToBottom(last.status === 'streaming' ? 'auto' : 'smooth')
    );
    return () => window.cancelAnimationFrame(frame);
  }, [session.messages]);

  const send = (text = draft) => {
    if (activeFiles.length === 0) return;
    session.sendMessage(text);
    setDraft('');
  };

  const toggleDocument = (id: string) => {
    setSelectedIds(current => {
      const next = new Set(current ?? documents.map(document => document.id));
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const exportTranscript = () => {
    const blob = new Blob([session.exportTranscript()], { type: 'text/markdown;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const anchor = window.document.createElement('a');
    anchor.href = url;
    anchor.download = 'corio-kutuphane-sohbeti.md';
    anchor.click();
    window.setTimeout(() => URL.revokeObjectURL(url), 0);
  };

  return (
    <div className="flex h-[calc(100dvh-4rem)] min-h-[520px] flex-col overflow-hidden bg-corio-bg text-corio-fg lg:h-screen">
      <header className="relative z-20 shrink-0 border-b border-corio-border-subtle bg-corio-bg/92 px-4 py-3 backdrop-blur-xl sm:px-6">
        <div className="mx-auto flex max-w-4xl items-center gap-3">
          <div className="flex size-10 shrink-0 items-center justify-center rounded-2xl bg-corio-accent-subtle ring-1 ring-corio-accent/10">
            <CorioLogo size={24} />
          </div>
          <div className="min-w-0 flex-1">
            <h1 className="truncate text-base font-semibold tracking-[-0.02em] sm:text-lg">Kütüphane Sohbeti</h1>
            <p className="truncate text-[11px] text-corio-fg/45 sm:text-xs">
              {session.isLoading ? 'Kaynaklar taranıyor…' : `${activeFiles.length} kaynak üzerinde çalışan Corio AI`}
            </p>
          </div>

          {session.messages.length > 0 && (
            <button
              aria-label="Sohbeti dışa aktar"
              className="hidden size-10 items-center justify-center rounded-xl text-corio-fg/55 transition-colors hover:bg-corio-surface-2 hover:text-corio-fg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-corio-accent/40 sm:flex"
              onClick={exportTranscript}
              title="Sohbeti dışa aktar"
              type="button"
            >
              <Download className="size-[18px]" />
            </button>
          )}

          {session.messages.length > 0 && (
            <button
              className="flex h-10 items-center gap-1.5 rounded-xl px-2.5 text-xs font-medium text-corio-fg/60 transition-colors hover:bg-corio-surface-2 hover:text-corio-fg focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-corio-accent/40"
              onClick={() => setConfirmClear(true)}
              type="button"
            >
              <RotateCcw className="size-4" />
              <span className="hidden sm:inline">Yeni sohbet</span>
            </button>
          )}

          <button
            aria-expanded={sourcePickerOpen}
            className="flex h-10 items-center gap-2 rounded-xl border border-corio-border bg-corio-surface-1 px-3 text-xs font-medium shadow-sm transition-colors hover:bg-corio-surface-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-corio-accent/40 disabled:opacity-50"
            disabled={session.isLoading}
            onClick={() => setSourcePickerOpen(open => !open)}
            type="button"
          >
            <Library className="size-4 text-corio-accent" />
            <span>{activeFiles.length}</span>
            <span className="hidden sm:inline">kaynak</span>
          </button>
        </div>

        {sourcePickerOpen && (
          <div className="absolute left-4 right-4 top-[calc(100%-0.25rem)] mx-auto max-w-2xl rounded-2xl border border-corio-border bg-corio-surface-1 p-3 shadow-xl sm:left-6 sm:right-6">
            <div className="mb-2 flex items-center gap-2 rounded-xl border border-corio-border-subtle bg-corio-bg px-2.5 py-1.5">
              <Search className="size-4 text-corio-fg/35" />
              <input
                aria-label="Kaynaklarda ara"
                className="min-w-0 flex-1 bg-transparent text-sm outline-none placeholder:text-corio-fg/35"
                onChange={event => setSourceQuery(event.target.value)}
                placeholder="Dosya ara…"
                value={sourceQuery}
              />
              {sourceQuery && (
                <button aria-label="Aramayı temizle" onClick={() => setSourceQuery('')} type="button">
                  <X className="size-4 text-corio-fg/45" />
                </button>
              )}
            </div>
            <div className="mb-1 flex items-center justify-between px-1 text-xs">
              <span className="font-medium text-corio-fg/55">Yanıta dahil edilecek belgeler</span>
              <button className="font-medium text-corio-accent hover:underline" onClick={() => setSelectedIds(null)} type="button">
                Tümünü seç
              </button>
            </div>
            <div className="max-h-56 space-y-0.5 overflow-y-auto overscroll-contain">
              {filteredDocuments.map(document => {
                const selected = selectedIds === null || selectedIds.has(document.id);
                return (
                  <button
                    aria-pressed={selected}
                    className="flex min-h-10 w-full items-center gap-2 rounded-xl px-2 text-left text-sm transition-colors hover:bg-corio-surface-2 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-corio-accent/40"
                    key={document.id}
                    onClick={() => toggleDocument(document.id)}
                    type="button"
                  >
                    <span className={`flex size-[18px] shrink-0 items-center justify-center rounded-md border ${selected ? 'border-corio-accent bg-corio-accent text-white' : 'border-corio-border bg-corio-bg'}`}>
                      {selected && <Check className="size-3" />}
                    </span>
                    <FileText className="size-4 shrink-0 text-corio-fg/35" />
                    <span className="truncate">{document.name}</span>
                  </button>
                );
              })}
            </div>
          </div>
        )}
      </header>

      {session.error && (
        <div className="mx-auto mt-2 flex w-[calc(100%-2rem)] max-w-4xl items-start gap-2 rounded-xl border border-corio-destructive/15 bg-corio-destructive/5 px-3 py-2 text-xs text-corio-fg/70" role="alert">
          <span className="flex-1">{session.error}</span>
          <button aria-label="Uyarıyı kapat" onClick={session.dismissError} type="button"><X className="size-4" /></button>
        </div>
      )}

      <main
        className="relative flex-1 overflow-y-auto overscroll-contain px-4 py-6 sm:px-6"
        onScroll={event => {
          const target = event.currentTarget;
          const nearBottom = target.scrollHeight - target.scrollTop - target.clientHeight < 120;
          nearBottomRef.current = nearBottom;
          setShowJumpButton(!nearBottom);
        }}
        ref={scrollerRef}
      >
        <div className="mx-auto flex min-h-full max-w-4xl flex-col">
          {documentsLoading || session.isLoadingHistory ? (
            <div className="flex flex-1 items-center justify-center gap-2 py-20 text-sm text-corio-fg/45" role="status">
              <Loader2 className="size-4 animate-spin text-corio-accent" />
              {documentsLoading ? 'Dokümanlar hazırlanıyor…' : 'Sohbet geçmişi yükleniyor…'}
            </div>
          ) : documents.length === 0 ? (
            <div className="flex flex-1 flex-col items-center justify-center py-16 text-center">
              <div className="mb-4 flex size-16 items-center justify-center rounded-[22px] bg-corio-surface-2">
                <BookOpenText className="size-8 text-corio-fg/30" />
              </div>
              <h2 className="text-base font-semibold">Sohbet için bir belge gerekiyor</h2>
              <p className="mt-1 max-w-sm text-sm leading-relaxed text-corio-fg/50">Kütüphanenize belge eklediğinizde Corio belgeler arasında bağlantılar kurabilir.</p>
            </div>
          ) : session.messages.length === 0 ? (
            <div className="flex flex-1 flex-col items-center justify-center py-10 text-center">
              <div className="mb-5 flex size-16 items-center justify-center rounded-[22px] bg-corio-accent-subtle ring-1 ring-corio-accent/10">
                <Sparkles className="size-7 text-corio-accent" />
              </div>
              <h2 className="text-xl font-semibold tracking-[-0.02em]">Kütüphanene tek yerden sor</h2>
              <p className="mb-7 mt-1.5 max-w-md text-sm leading-relaxed text-corio-fg/50">Belgelerindeki bilgileri karşılaştırır, ortak temaları bulur ve kullandığı kaynakları belirtir.</p>
              <div className="w-full max-w-xl">
                <SuggestedPrompts disabled={activeFiles.length === 0} onSelect={send} prompts={DEFAULT_SUGGESTIONS} />
              </div>
            </div>
          ) : (
            <div className="space-y-5" aria-live="polite">
              {session.messages.map(message => (
                <ChatMessage
                  isLastModelMessage={message.id === lastModelId}
                  key={message.id}
                  message={message}
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
            className="sticky bottom-2 left-full flex size-10 -translate-x-2 items-center justify-center rounded-full border border-corio-border bg-corio-surface-1 shadow-md hover:text-corio-accent"
            onClick={() => scrollToBottom()}
            type="button"
          >
            <span className="text-lg leading-none">↓</span>
          </button>
        )}
      </main>

      <footer className="shrink-0 border-t border-corio-border-subtle bg-corio-bg/94 backdrop-blur-xl">
        <div className="mx-auto max-w-4xl">
          <ChatInput
            allowsAttachments={false}
            attachment={null}
            autoFocus={!documentsLoading && documents.length > 0 && session.messages.length === 0}
            draft={draft}
            isLoading={session.isLoading}
            onAttachmentChange={() => undefined}
            onDraftChange={setDraft}
            onStop={session.stopGenerating}
            onSubmit={() => send()}
            placeholder={activeFiles.length === 0 ? 'Yanıt için en az bir kaynak seçin…' : 'Kütüphanene bir soru sor…'}
          />
        </div>
      </footer>

      <Dialog onOpenChange={setConfirmClear} open={confirmClear}>
        <DialogContent className="border border-corio-border bg-corio-surface-1 text-corio-fg" showCloseButton={false}>
          <DialogHeader>
            <DialogTitle>Yeni bir sohbet başlatılsın mı?</DialogTitle>
            <DialogDescription>Mevcut kütüphane sohbeti kalıcı olarak silinecek.</DialogDescription>
          </DialogHeader>
          <DialogFooter className="border-corio-border-subtle bg-corio-surface-2/60">
            <button className="rounded-xl border border-corio-border px-3 py-2 text-sm font-medium hover:bg-corio-surface-3" onClick={() => setConfirmClear(false)} type="button">Vazgeç</button>
            <button
              className="rounded-xl bg-corio-destructive px-3 py-2 text-sm font-medium text-white hover:opacity-90"
              onClick={() => void session.clearHistory().then(() => setConfirmClear(false)).catch(() => undefined)}
              type="button"
            >
              Yeni sohbet
            </button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
