'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { ChatMessage } from '@/types/models';
import { streamChat, streamChatWithImage, streamChatWithRAGAndHistory } from '@/lib/gemini';
import { searchRelevantChunks } from '@/lib/rag';
import { clearChatHistory, loadChatHistory, saveChatMessage } from '@/lib/chatSync';
import { toChatHistory } from '@/lib/chatHistory';
import { formatChatTranscript, normalizeChatDraft } from '@/lib/chatPresentation';

interface UseChatSessionOptions {
  activeSelection?: string | null;
  currentPage?: number;
  documentContext?: string;
  documentId?: string;
  isActive: boolean;
}

interface SendMessageOptions {
  attachment?: string | null;
  selection?: string | null;
  text: string;
}

interface ResponseRequest {
  attachment?: string;
  history: ChatMessage[];
  prompt: string;
}

interface UseChatSessionResult {
  clearHistory: () => Promise<void>;
  dismissError: () => void;
  error: string | null;
  exportTranscript: () => string;
  isHistoryReady: boolean;
  isLoading: boolean;
  isLoadingHistory: boolean;
  messages: ChatMessage[];
  regenerateLastResponse: () => void;
  retryLastResponse: () => void;
  sendMessage: (options: SendMessageOptions) => void;
  stopGenerating: () => void;
  suggestions: string[];
}

let fallbackId = 0;

function createMessageId(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return crypto.randomUUID();
  fallbackId += 1;
  return `${Date.now()}-${fallbackId}`;
}

function contextualSuggestions(activeSelection?: string | null, currentPage?: number): string[] {
  if (activeSelection) {
    return [
      'Seçili bölümü daha anlaşılır biçimde açıkla',
      'Bu metindeki anahtar kavramları çıkar',
      'Bu bölümden üç çalışma sorusu üret',
    ];
  }

  if (currentPage && currentPage > 1) {
    return [
      `Sayfa ${currentPage}’yi kısa maddelerle özetle`,
      'Bu sayfadaki en önemli kavramlar neler?',
      'Bu bölümü belgenin ana fikriyle ilişkilendir',
    ];
  }

  return [
    'Bu belgenin ana fikrini özetle',
    'En önemli bulguları maddeler halinde çıkar',
    'Belgeyi anlamak için hangi kavramları bilmeliyim?',
  ];
}

export function useChatSession({
  activeSelection,
  currentPage,
  documentContext,
  documentId,
  isActive,
}: UseChatSessionOptions): UseChatSessionResult {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isLoadingHistory, setIsLoadingHistory] = useState(false);
  const [isHistoryReady, setIsHistoryReady] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [retryRequest, setRetryRequest] = useState<ResponseRequest | null>(null);
  const messagesRef = useRef<ChatMessage[]>([]);
  const abortRef = useRef<AbortController | null>(null);
  const activeResponseIdRef = useRef<string | null>(null);

  const updateMessages = useCallback((updater: (current: ChatMessage[]) => ChatMessage[]) => {
    setMessages(current => {
      const next = updater(current);
      messagesRef.current = next;
      return next;
    });
  }, []);

  const stopGenerating = useCallback(() => {
    abortRef.current?.abort();
    abortRef.current = null;
    setIsLoading(false);

    const activeId = activeResponseIdRef.current;
    activeResponseIdRef.current = null;
    if (!activeId) return;

    updateMessages(current => current.flatMap(message => {
      if (message.id !== activeId) return [message];
      return message.text.trim() ? [{ ...message, status: 'stopped' as const }] : [];
    }));
  }, [updateMessages]);

  useEffect(() => {
    if (!isActive) stopGenerating();
  }, [isActive, stopGenerating]);

  useEffect(() => () => abortRef.current?.abort(), []);

  useEffect(() => {
    let cancelled = false;
    abortRef.current?.abort();
    setError(null);
    setRetryRequest(null);
    setIsHistoryReady(false);

    if (!documentId) {
      updateMessages(() => []);
      setIsLoadingHistory(false);
      setIsHistoryReady(true);
      return () => { cancelled = true; };
    }

    setIsLoadingHistory(true);
    loadChatHistory(documentId)
      .then(history => {
        if (cancelled) return;
        updateMessages(() => history.map(item => ({
          id: item.id || `${item.created_at}-${item.role}`,
          role: item.role,
          status: 'complete',
          text: item.content,
          timestamp: item.created_at ? new Date(item.created_at) : new Date(),
        })));
      })
      .catch(loadError => {
        if (cancelled) return;
        console.error('Failed to load chat history:', loadError);
        setError('Sohbet geçmişi yüklenemedi. Yeni mesajlarınızı yine de gönderebilirsiniz.');
      })
      .finally(() => {
        if (cancelled) return;
        setIsLoadingHistory(false);
        setIsHistoryReady(true);
      });

    return () => { cancelled = true; };
  }, [documentId, updateMessages]);

  const runResponse = useCallback((request: ResponseRequest) => {
    stopGenerating();
    setError(null);
    setRetryRequest(null);

    const responseId = createMessageId();
    const controller = new AbortController();
    abortRef.current = controller;
    activeResponseIdRef.current = responseId;
    setIsLoading(true);
    updateMessages(current => [
      ...current,
      {
        id: responseId,
        role: 'model',
        status: 'streaming',
        text: '',
        timestamp: new Date(),
      },
    ]);

    void (async () => {
      let fullResponse = '';
      let lastPaint = 0;

      const paint = (status: ChatMessage['status'] = 'streaming') => {
        updateMessages(current => current.map(message =>
          message.id === responseId ? { ...message, status, text: fullResponse } : message
        ));
      };

      try {
        let stream: AsyncGenerator<string, void, unknown>;
        if (request.attachment) {
          let context = documentContext;
          if (documentId) {
            try {
              context = await searchRelevantChunks(documentId, request.prompt, 15);
            } catch (ragError) {
              console.error('RAG image context search failed:', ragError);
            }
          }
          stream = streamChatWithImage(
            request.prompt,
            request.attachment,
            context,
            controller.signal,
          );
        } else if (documentId) {
          stream = streamChatWithRAGAndHistory(
            request.prompt,
            documentId,
            toChatHistory(request.history),
            controller.signal,
          );
        } else {
          stream = streamChat(request.prompt, documentContext, controller.signal);
        }

        for await (const chunk of stream) {
          fullResponse += chunk;
          const now = performance.now();
          if (now - lastPaint >= 50) {
            paint();
            lastPaint = now;
          }
        }

        if (!fullResponse.trim()) {
          throw new Error('Model boş bir yanıt döndürdü.');
        }

        paint('complete');
        if (documentId) {
          try {
            await saveChatMessage(documentId, 'model', fullResponse);
          } catch (saveError) {
            console.error('Failed to save model chat message:', saveError);
            setError('Yanıt oluşturuldu ancak geçmişe kaydedilemedi.');
          }
        }
      } catch (streamError) {
        if (controller.signal.aborted) {
          updateMessages(current => current.flatMap(message => {
            if (message.id !== responseId) return [message];
            const partialText = message.text || fullResponse;
            return partialText.trim()
              ? [{ ...message, status: 'stopped' as const, text: partialText }]
              : [];
          }));
          return;
        }

        console.error('Chat response failed:', streamError);
        setRetryRequest(request);
        updateMessages(current => current.map(message =>
          message.id === responseId
            ? {
                ...message,
                status: 'error',
                text: 'Bir şey ters gitti. İsteğinizi yeniden deneyebilirsiniz.',
              }
            : message
        ));
      } finally {
        if (abortRef.current === controller) {
          abortRef.current = null;
          setIsLoading(false);
        }
        if (activeResponseIdRef.current === responseId) {
          activeResponseIdRef.current = null;
          setIsLoading(false);
        }
      }
    })();
  }, [documentContext, documentId, stopGenerating, updateMessages]);

  const sendMessage = useCallback(({ attachment, selection, text }: SendMessageOptions) => {
    if (isLoading) return;
    const prompt = normalizeChatDraft(text, Boolean(attachment));
    if (!prompt) return;

    const modelPrompt = selection ? `${prompt}\n\n> ${selection}` : prompt;
    const history = [...messagesRef.current];
    const userMessage: ChatMessage = {
      attachment: attachment ? { type: 'image', content: attachment } : undefined,
      id: createMessageId(),
      role: 'user',
      status: 'complete',
      text: modelPrompt,
      timestamp: new Date(),
    };
    updateMessages(current => [...current, userMessage]);

    if (documentId) {
      void saveChatMessage(documentId, 'user', modelPrompt).catch(saveError => {
        console.error('Failed to save user chat message:', saveError);
        setError('Mesaj gönderildi ancak geçmişe kaydedilemedi.');
      });
    }

    runResponse({
      attachment: attachment ?? undefined,
      history,
      prompt: modelPrompt,
    });
  }, [documentId, isLoading, runResponse, updateMessages]);

  const retryLastResponse = useCallback(() => {
    if (isLoading || !retryRequest) return;
    updateMessages(current => current.filter(message => message.status !== 'error'));
    runResponse(retryRequest);
  }, [isLoading, retryRequest, runResponse, updateMessages]);

  const regenerateLastResponse = useCallback(() => {
    if (isLoading) return;
    const current = messagesRef.current;
    const userIndex = current.findLastIndex(message => message.role === 'user');
    if (userIndex < 0) return;

    const userMessage = current[userIndex];
    const history = current.slice(0, userIndex);
    updateMessages(() => current.slice(0, userIndex + 1));
    runResponse({
      attachment: userMessage.attachment?.content,
      history,
      prompt: userMessage.text,
    });
  }, [isLoading, runResponse, updateMessages]);

  const clearHistory = useCallback(async () => {
    stopGenerating();
    const previousMessages = messagesRef.current;
    updateMessages(() => []);
    setRetryRequest(null);
    setError(null);

    if (!documentId) return;
    try {
      await clearChatHistory(documentId);
    } catch (clearError) {
      console.error('Failed to clear chat history:', clearError);
      updateMessages(() => previousMessages);
      setError('Sohbet geçmişi silinemedi. Lütfen yeniden deneyin.');
      throw clearError;
    }
  }, [documentId, stopGenerating, updateMessages]);

  const exportTranscript = useCallback(
    () => formatChatTranscript(messagesRef.current, 'Corio AI Sohbeti'),
    [],
  );

  const suggestions = useMemo(
    () => contextualSuggestions(activeSelection, currentPage),
    [activeSelection, currentPage],
  );

  return {
    clearHistory,
    dismissError: () => setError(null),
    error,
    exportTranscript,
    isHistoryReady,
    isLoading,
    isLoadingHistory,
    messages,
    regenerateLastResponse,
    retryLastResponse,
    sendMessage,
    stopGenerating,
    suggestions,
  };
}
