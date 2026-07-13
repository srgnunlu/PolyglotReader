'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import type { ChatMessage } from '@/types/models';
import type { ChatHistoryMessage } from '@/lib/gemini';
import { streamLibraryChat } from '@/lib/gemini';
import {
  clearLibraryChatHistory,
  loadLibraryChatHistory,
  saveLibraryChatMessage,
} from '@/lib/chatSync';
import { toChatHistory } from '@/lib/chatHistory';
import { formatChatTranscript, normalizeChatDraft } from '@/lib/chatPresentation';

export interface LibraryChatFile {
  id: string;
  name: string;
}

interface LibraryRequest {
  files: LibraryChatFile[];
  history: ChatHistoryMessage[];
  prompt: string;
}

let messageSequence = 0;
function messageId(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return crypto.randomUUID();
  messageSequence += 1;
  return `${Date.now()}-${messageSequence}`;
}

export function useLibraryChatSession(activeFiles: LibraryChatFile[]) {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isLoadingHistory, setIsLoadingHistory] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [retryRequest, setRetryRequest] = useState<LibraryRequest | null>(null);
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
    let cancelled = false;
    loadLibraryChatHistory()
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
        if (!cancelled) {
          console.error('Failed to load library chat:', loadError);
          setError('Sohbet geçmişi yüklenemedi.');
        }
      })
      .finally(() => { if (!cancelled) setIsLoadingHistory(false); });
    return () => {
      cancelled = true;
      abortRef.current?.abort();
    };
  }, [updateMessages]);

  const runResponse = useCallback((request: LibraryRequest) => {
    stopGenerating();
    setError(null);
    setRetryRequest(null);
    const responseId = messageId();
    const controller = new AbortController();
    abortRef.current = controller;
    activeResponseIdRef.current = responseId;
    setIsLoading(true);
    updateMessages(current => [
      ...current,
      { id: responseId, role: 'model', status: 'streaming', text: '', timestamp: new Date() },
    ]);

    void (async () => {
      let fullResponse = '';
      let lastPaint = 0;
      const paint = (status: ChatMessage['status']) => updateMessages(current => current.map(message =>
        message.id === responseId ? { ...message, status, text: fullResponse } : message
      ));

      try {
        for await (const chunk of streamLibraryChat(
          request.prompt,
          request.files,
          request.history,
          controller.signal,
        )) {
          fullResponse += chunk;
          const now = performance.now();
          if (now - lastPaint >= 50) {
            paint('streaming');
            lastPaint = now;
          }
        }

        if (!fullResponse.trim()) {
          fullResponse = 'Seçili kaynaklarda bu soruya yanıt verecek yeterli bilgi bulamadım.';
        }
        paint('complete');
        try {
          await saveLibraryChatMessage('model', fullResponse);
        } catch (saveError) {
          console.error('Failed to save library model message:', saveError);
          setError('Yanıt oluşturuldu ancak geçmişe kaydedilemedi.');
        }
      } catch (streamError) {
        if (controller.signal.aborted) {
          updateMessages(current => current.flatMap(message => {
            if (message.id !== responseId) return [message];
            const partial = message.text || fullResponse;
            return partial.trim() ? [{ ...message, status: 'stopped' as const, text: partial }] : [];
          }));
          return;
        }
        console.error('Library chat response failed:', streamError);
        setRetryRequest(request);
        updateMessages(current => current.map(message => message.id === responseId
          ? { ...message, status: 'error', text: 'Kaynaklar aranırken bir sorun oluştu.' }
          : message));
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
  }, [stopGenerating, updateMessages]);

  const sendMessage = useCallback((text: string) => {
    if (isLoading || activeFiles.length === 0) return;
    const prompt = normalizeChatDraft(text, false);
    if (!prompt) return;
    const history = toChatHistory(messagesRef.current);
    updateMessages(current => [
      ...current,
      { id: messageId(), role: 'user', status: 'complete', text: prompt, timestamp: new Date() },
    ]);
    void saveLibraryChatMessage('user', prompt).catch(saveError => {
      console.error('Failed to save library chat message:', saveError);
      setError('Mesaj gönderildi ancak geçmişe kaydedilemedi.');
    });
    runResponse({ files: [...activeFiles], history, prompt });
  }, [activeFiles, isLoading, runResponse, updateMessages]);

  const retryLastResponse = useCallback(() => {
    if (!retryRequest || isLoading) return;
    updateMessages(current => current.filter(message => message.status !== 'error'));
    runResponse(retryRequest);
  }, [isLoading, retryRequest, runResponse, updateMessages]);

  const regenerateLastResponse = useCallback(() => {
    if (isLoading) return;
    const current = messagesRef.current;
    const userIndex = current.findLastIndex(message => message.role === 'user');
    if (userIndex < 0) return;
    const prompt = current[userIndex].text;
    updateMessages(() => current.slice(0, userIndex + 1));
    runResponse({ files: [...activeFiles], history: toChatHistory(current.slice(0, userIndex)), prompt });
  }, [activeFiles, isLoading, runResponse, updateMessages]);

  const clearHistory = useCallback(async () => {
    stopGenerating();
    const previous = messagesRef.current;
    updateMessages(() => []);
    try {
      await clearLibraryChatHistory();
    } catch (clearError) {
      updateMessages(() => previous);
      setError('Sohbet geçmişi silinemedi.');
      throw clearError;
    }
  }, [stopGenerating, updateMessages]);

  return {
    clearHistory,
    dismissError: () => setError(null),
    error,
    exportTranscript: () => formatChatTranscript(messagesRef.current, 'Corio AI Kütüphane Sohbeti'),
    isLoading,
    isLoadingHistory,
    messages,
    regenerateLastResponse,
    retryLastResponse,
    sendMessage,
    stopGenerating,
  };
}
