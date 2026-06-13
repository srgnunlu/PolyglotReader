// Library-wide chat — ask questions across all (or a selected subset of)
// documents in the library. Uses multi-file hybrid RAG (lib/rag
// searchLibraryChunks) via streamLibraryChat.
'use client';

import { useState, useRef, useEffect, useMemo, memo, useCallback } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { Send, Sparkles, Library, Check, FileText, Loader2, RotateCcw } from 'lucide-react';
import { useDocuments } from '@/hooks/useDocuments';
import { streamLibraryChat, ChatHistoryMessage } from '@/lib/gemini';
import { ChatMessage } from '@/types/models';

const REMARK_PLUGINS = [remarkGfm];

const DEFAULT_SUGGESTIONS = [
  'Dokümanlarımda hangi ana konular işleniyor?',
  'Bu belgeler arasındaki ortak temalar neler?',
  'En önemli bulguları özetler misin?',
];

const MessageItem = memo(function MessageItem({ message }: { message: ChatMessage }) {
  const isUser = message.role === 'user';
  return (
    <div className={`flex gap-3 ${isUser ? 'flex-row-reverse' : ''}`}>
      <div
        className={`flex size-8 shrink-0 items-center justify-center rounded-full text-xs font-semibold ${
          isUser ? 'bg-corio-accent text-white' : 'bg-corio-surface-3 text-corio-accent'
        }`}
      >
        {isUser ? 'Sen' : <Sparkles className="size-4" />}
      </div>
      <div
        className={`max-w-[80%] rounded-2xl px-4 py-2.5 text-sm leading-relaxed ${
          isUser
            ? 'bg-corio-accent text-white'
            : 'bg-corio-surface-2 text-corio-fg border border-corio-border-subtle'
        }`}
      >
        {message.text ? (
          <div className="prose-chat">
            <ReactMarkdown remarkPlugins={REMARK_PLUGINS}>{message.text}</ReactMarkdown>
          </div>
        ) : (
          <div className="flex gap-1 py-1">
            <span className="size-1.5 animate-bounce rounded-full bg-corio-fg/40 [animation-delay:-0.3s]" />
            <span className="size-1.5 animate-bounce rounded-full bg-corio-fg/40 [animation-delay:-0.15s]" />
            <span className="size-1.5 animate-bounce rounded-full bg-corio-fg/40" />
          </div>
        )}
      </div>
    </div>
  );
});

export function LibraryChat() {
  const { documents, isLoading: docsLoading } = useDocuments();
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string> | null>(null); // null = all
  const [showPicker, setShowPicker] = useState(false);
  const messagesEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  // Resolve the active set of files: null means "all documents".
  const activeFiles = useMemo(
    () =>
      documents
        .filter(doc => selectedIds === null || selectedIds.has(doc.id))
        .map(doc => ({ id: doc.id, name: doc.name })),
    [documents, selectedIds]
  );

  const toggleFile = useCallback(
    (id: string) => {
      setSelectedIds(prev => {
        const base = prev ?? new Set(documents.map(d => d.id));
        const next = new Set(base);
        if (next.has(id)) next.delete(id);
        else next.add(id);
        return next;
      });
    },
    [documents]
  );

  const handleSend = useCallback(
    async (messageText?: string) => {
      const text = (messageText ?? input).trim();
      if (!text || isLoading) return;
      if (activeFiles.length === 0) return;

      const userMessage: ChatMessage = {
        id: Date.now().toString(),
        role: 'user',
        text,
        timestamp: new Date(),
      };
      setMessages(prev => [...prev, userMessage]);
      setInput('');
      setIsLoading(true);

      const aiMessageId = (Date.now() + 1).toString();
      setMessages(prev => [...prev, { id: aiMessageId, role: 'model', text: '', timestamp: new Date() }]);

      try {
        const chatHistory: ChatHistoryMessage[] = messages.map(m => ({
          role: m.role,
          text: m.text,
        }));

        let fullResponse = '';
        for await (const chunk of streamLibraryChat(text, activeFiles, chatHistory)) {
          fullResponse += chunk;
          setMessages(prev => prev.map(m => (m.id === aiMessageId ? { ...m, text: fullResponse } : m)));
        }
        if (!fullResponse) {
          setMessages(prev =>
            prev.map(m =>
              m.id === aiMessageId
                ? { ...m, text: 'Kütüphanenizdeki dokümanlar bu konuda bilgi içermiyor.' }
                : m
            )
          );
        }
      } catch (err) {
        console.error('Library chat error:', err);
        setMessages(prev =>
          prev.map(m =>
            m.id === aiMessageId ? { ...m, text: 'Bir hata oluştu. Lütfen tekrar deneyin.' } : m
          )
        );
      } finally {
        setIsLoading(false);
      }
    },
    [input, isLoading, activeFiles, messages]
  );

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const selectedCount = selectedIds === null ? documents.length : selectedIds.size;

  return (
    <div className="flex h-[calc(100vh-4rem)] flex-col lg:h-screen">
      {/* Header */}
      <div className="sticky top-0 z-10 border-b border-corio-border-subtle bg-corio-bg/90 px-4 py-4 backdrop-blur-xl sm:px-6">
        <div className="mx-auto flex max-w-3xl items-center justify-between gap-3">
          <div>
            <h1 className="text-xl font-semibold text-corio-fg">Kütüphane Sohbeti</h1>
            <p className="text-xs text-corio-fg/50">
              Tüm dokümanlarınız üzerinde soru sorun
            </p>
          </div>
          <div className="flex items-center gap-2">
            {messages.length > 0 && (
              <button
                onClick={() => setMessages([])}
                className="flex items-center gap-1.5 rounded-xl border border-corio-border px-3 py-2 text-xs font-medium text-corio-fg/70 transition-colors hover:bg-corio-surface-2"
                title="Sohbeti temizle"
              >
                <RotateCcw className="size-3.5" />
                Yeni
              </button>
            )}
            <button
              onClick={() => setShowPicker(prev => !prev)}
              className="flex items-center gap-1.5 rounded-xl border border-corio-border bg-corio-surface-2 px-3 py-2 text-xs font-medium text-corio-fg transition-colors hover:bg-corio-surface-3"
            >
              <Library className="size-3.5 text-corio-accent" />
              {selectedCount} kaynak
            </button>
          </div>
        </div>

        {/* Source picker */}
        {showPicker && (
          <div className="mx-auto mt-3 max-w-3xl rounded-xl border border-corio-border bg-corio-surface-1 p-3">
            <div className="mb-2 flex items-center justify-between">
              <span className="text-xs font-medium text-corio-fg/70">Kaynak dokümanlar</span>
              <button
                onClick={() => setSelectedIds(null)}
                className="text-xs font-medium text-corio-accent hover:underline"
              >
                Tümünü seç
              </button>
            </div>
            <div className="flex max-h-40 flex-col gap-1 overflow-y-auto">
              {documents.map(doc => {
                const checked = selectedIds === null || selectedIds.has(doc.id);
                return (
                  <button
                    key={doc.id}
                    onClick={() => toggleFile(doc.id)}
                    className="flex items-center gap-2 rounded-lg px-2 py-1.5 text-left text-sm text-corio-fg transition-colors hover:bg-corio-surface-2"
                  >
                    <span
                      className={`flex size-4 shrink-0 items-center justify-center rounded border ${
                        checked ? 'border-corio-accent bg-corio-accent text-white' : 'border-corio-border'
                      }`}
                    >
                      {checked && <Check className="size-3" />}
                    </span>
                    <FileText className="size-3.5 shrink-0 text-corio-fg/40" />
                    <span className="truncate">{doc.name}</span>
                  </button>
                );
              })}
            </div>
          </div>
        )}
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto px-4 py-6 sm:px-6">
        <div className="mx-auto max-w-3xl space-y-5">
          {docsLoading ? (
            <div className="flex items-center justify-center gap-2 py-20 text-corio-fg/50">
              <Loader2 className="size-4 animate-spin" />
              Dokümanlar yükleniyor...
            </div>
          ) : documents.length === 0 ? (
            <div className="flex flex-col items-center gap-3 py-20 text-center">
              <div className="flex size-16 items-center justify-center rounded-2xl bg-corio-surface-2">
                <Library className="size-8 text-corio-fg/30" />
              </div>
              <p className="text-sm text-corio-fg/60">
                Sohbet için önce kütüphanenize doküman ekleyin.
              </p>
            </div>
          ) : messages.length === 0 ? (
            <div className="flex flex-col items-center gap-5 py-16 text-center">
              <div className="flex size-14 items-center justify-center rounded-2xl bg-corio-accent-subtle">
                <Sparkles className="size-7 text-corio-accent" />
              </div>
              <div className="space-y-1">
                <h3 className="text-base font-medium text-corio-fg">Kütüphanenle sohbet et</h3>
                <p className="max-w-sm text-sm text-corio-fg/50">
                  Tüm dokümanların arasından yanıt bulurum ve hangi dosya/sayfadan geldiğini belirtirim.
                </p>
              </div>
              <div className="flex w-full max-w-md flex-col gap-2">
                {DEFAULT_SUGGESTIONS.map(s => (
                  <button
                    key={s}
                    onClick={() => handleSend(s)}
                    className="flex items-center gap-2 rounded-xl border border-corio-border bg-corio-surface-1 px-3 py-2.5 text-left text-sm text-corio-fg transition-colors hover:bg-corio-surface-2"
                  >
                    <Sparkles className="size-4 shrink-0 text-corio-accent" />
                    {s}
                  </button>
                ))}
              </div>
            </div>
          ) : (
            messages.map(m => <MessageItem key={m.id} message={m} />)
          )}
          <div ref={messagesEndRef} />
        </div>
      </div>

      {/* Input */}
      <div className="border-t border-corio-border bg-corio-surface-1 px-4 py-3 sm:px-6">
        <div className="mx-auto flex max-w-3xl items-end gap-2">
          <textarea
            value={input}
            onChange={e => setInput(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={
              documents.length === 0
                ? 'Önce doküman ekleyin...'
                : 'Kütüphanene bir soru sor...'
            }
            rows={1}
            disabled={isLoading || documents.length === 0}
            className="max-h-32 flex-1 resize-none rounded-xl border border-corio-border bg-corio-bg px-3.5 py-2.5 text-sm text-corio-fg outline-none transition-all placeholder:text-corio-fg/40 focus:border-corio-accent focus:ring-2 focus:ring-corio-accent/20 disabled:opacity-60"
          />
          <button
            onClick={() => handleSend()}
            disabled={!input.trim() || isLoading || documents.length === 0}
            className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-corio-accent text-white transition-colors hover:bg-corio-accent-hover disabled:opacity-40"
            aria-label="Gönder"
          >
            {isLoading ? <Loader2 className="size-4 animate-spin" /> : <Send className="size-4" />}
          </button>
        </div>
      </div>
    </div>
  );
}
