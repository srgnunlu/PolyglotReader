'use client';

import { useState, useRef, useEffect, useMemo } from 'react';
import { ChatMessage } from '@/types/models';
import { streamChat, streamChatWithImage, streamChatWithRAGAndHistory, ChatHistoryMessage } from '@/lib/gemini';
import { searchRelevantChunks } from '@/lib/rag';
import { loadChatHistory, saveChatMessage, clearChatHistory } from '@/lib/chatSync';
import styles from './ChatPanel.module.css';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

interface ChatPanelProps {
    isOpen: boolean;
    onClose: () => void;
    documentId?: string;
    documentContext?: string; // Kept for backward compatibility
    initialMessage?: string;
    initialImage?: string;
    activeSelection?: string | null;
    onClearInitialMessage?: () => void;
    onClearSelection?: () => void;
}

export function ChatPanel({
    isOpen,
    onClose,
    documentId,
    documentContext,
    initialMessage,
    initialImage,
    activeSelection,
    onClearInitialMessage,
    onClearSelection,
}: ChatPanelProps) {
    const [messages, setMessages] = useState<ChatMessage[]>([]);
    const [input, setInput] = useState('');
    const [isLoading, setIsLoading] = useState(false);
    const [pendingAttachment, setPendingAttachment] = useState<string | null>(null);
    const messagesEndRef = useRef<HTMLDivElement>(null);
    const [panelWidth, setPanelWidth] = useState(360);
    const resizeStartRef = useRef<{ x: number; width: number } | null>(null);

    // Scroll to bottom when new message
    useEffect(() => {
        messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }, [messages]);

    // Load chat history from Supabase when documentId changes
    useEffect(() => {
        if (!documentId) {
            setMessages([]);
            return;
        }

        let isMounted = true;

        const loadHistory = async () => {
            try {
                const history = await loadChatHistory(documentId);
                if (isMounted) {
                    // Convert Supabase chat format to ChatMessage format
                    const chatMessages: ChatMessage[] = history.map(h => ({
                        id: h.id || `${h.created_at}-${h.role}`,
                        role: h.role,
                        text: h.content,
                        timestamp: h.created_at ? new Date(h.created_at) : new Date(),
                    }));
                    setMessages(chatMessages);
                }
            } catch (error) {
                console.error('Failed to load chat history:', error);
            }
        };

        loadHistory();

        return () => {
            isMounted = false;
        };
    }, [documentId]);

    // Handle initial message/image from selection
    useEffect(() => {
        if ((initialMessage || initialImage) && onClearInitialMessage) {
            if (initialImage) {
                // If there's an image, set it as pending attachment and don't send yet
                setPendingAttachment(initialImage);
                // Optional: set a default text or leave empty for user to type
                // setInput('Bu görsel hakkında bilgi ver.'); 
            } else if (initialMessage) {
                // If just text, send immediately (or pre-fill input if preferred, but existing behavior was send)
                handleSendMessage(initialMessage);
            }
            onClearInitialMessage();
        }
    }, [initialMessage, initialImage]);

    const handleSendMessage = async (messageText?: string) => {
        const text = messageText || input.trim();
        const img = pendingAttachment;

        if ((!text && !img) || isLoading) return;

        const messageContent = activeSelection
            ? `${text}\n\n> ${activeSelection}`
            : text;

        const userMessage: ChatMessage = {
            id: Date.now().toString(),
            role: 'user',
            text: messageContent,
            timestamp: new Date(),
            attachment: img ? {
                type: 'image',
                content: img
            } : undefined
        };

        // Add temporary image display support via extended text or custom rendering
        // For this implementation, we will assume ChatMessage just holds text.
        // But we want to show the image in the UI. 
        // Let's rely on the fact that we process it. 
        // To show it in UI, we might need to extend ChatMessage type.
        // Since we can't change types/models.ts easily without seeing it, let's keep it simple.

        setMessages(prev => [...prev, userMessage]);
        setInput('');
        setPendingAttachment(null);

        // Clear selection after sending if it was used
        if (activeSelection && onClearSelection) {
            onClearSelection();
        }

        setIsLoading(true);

        // Create placeholder for AI response
        const aiMessageId = (Date.now() + 1).toString();
        const aiMessage: ChatMessage = {
            id: aiMessageId,
            role: 'model',
            text: '',
            timestamp: new Date(),
        };
        setMessages(prev => [...prev, aiMessage]);

        try {
            // Use streaming for real-time response
            let fullResponse = '';

            // Build conversation history for memory (exclude the just-added messages)
            // We need messages BEFORE the current user message and AI placeholder
            const historyMessages = messages.slice(0, -2); // Exclude last 2 (user + ai placeholder)
            const chatHistory: ChatHistoryMessage[] = historyMessages.map(m => ({
                role: m.role as 'user' | 'model',
                text: m.text
            }));

            let stream: AsyncGenerator<string, void, unknown>;

            if (img) {
                // Image chat - use existing function with context
                let context = documentContext;
                if (documentId) {
                    try {
                        context = await searchRelevantChunks(documentId, messageContent, 15);
                    } catch (ragError) {
                        console.error('RAG search failed:', ragError);
                    }
                }
                stream = streamChatWithImage(messageContent, img, context);
            } else if (documentId) {
                // Document chat with RAG + Memory
                // Uses hybrid search (vector + BM25) and conversation history
                stream = streamChatWithRAGAndHistory(messageContent, documentId, chatHistory);
            } else {
                // Simple chat without document
                stream = streamChat(messageContent, documentContext);
            }

            for await (const chunk of stream) {
                fullResponse += chunk;
                setMessages(prev =>
                    prev.map(m =>
                        m.id === aiMessageId ? { ...m, text: fullResponse } : m
                    )
                );
            }

            // Save both user and AI messages to Supabase after successful response
            if (documentId) {
                try {
                    await saveChatMessage(documentId, 'user', messageContent);
                    await saveChatMessage(documentId, 'model', fullResponse);
                } catch (saveError) {
                    console.error('Failed to save chat messages:', saveError);
                    // Non-blocking error, chat still works locally
                }
            }
        } catch (err) {
            console.error('Chat error:', err);
            setMessages(prev =>
                prev.map(m =>
                    m.id === aiMessageId
                        ? { ...m, text: 'Bir hata oluştu. Lütfen tekrar deneyin.' }
                        : m
                )
            );
        } finally {
            setIsLoading(false);
        }
    };

    const handleKeyDown = (e: React.KeyboardEvent) => {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            handleSendMessage();
        }
    };

    const clearChat = async () => {
        setMessages([]);

        // Also clear from Supabase
        if (documentId) {
            try {
                await clearChatHistory(documentId);
            } catch (error) {
                console.error('Failed to clear chat history from Supabase:', error);
            }
        }
    };

    if (!isOpen) return null;

    // Prevent clicks inside chat panel from clearing PDF selection
    const handlePanelMouseDown = (e: React.MouseEvent) => {
        e.stopPropagation();
    };

    const handleResizeStart = (e: React.PointerEvent<HTMLDivElement>) => {
        e.preventDefault();
        e.stopPropagation();

        const startWidth = panelWidth;
        resizeStartRef.current = { x: e.clientX, width: startWidth };

        const minWidth = 280;
        const maxWidth = Math.max(minWidth, Math.min(760, window.innerWidth - 240));

        const handlePointerMove = (event: PointerEvent) => {
            if (!resizeStartRef.current) return;
            const delta = resizeStartRef.current.x - event.clientX;
            const nextWidth = Math.min(
                maxWidth,
                Math.max(minWidth, resizeStartRef.current.width + delta)
            );
            setPanelWidth(nextWidth);
        };

        const handlePointerUp = () => {
            resizeStartRef.current = null;
            document.body.style.cursor = '';
            document.body.style.userSelect = '';
            document.removeEventListener('pointermove', handlePointerMove);
            document.removeEventListener('pointerup', handlePointerUp);
        };

        document.body.style.cursor = 'col-resize';
        document.body.style.userSelect = 'none';
        document.addEventListener('pointermove', handlePointerMove);
        document.addEventListener('pointerup', handlePointerUp);
    };

    return (
        <div
            className={styles.panel}
            style={{ width: panelWidth }}
            onMouseDown={handlePanelMouseDown}
            data-chat-panel="true"
        >
            <div
                className={styles.resizeHandle}
                onPointerDown={handleResizeStart}
                aria-hidden="true"
            />
            <div className={styles.header}>
                <h3 className={styles.title}>
                    <span className={styles.titleIcon}>✨</span>
                    AI Asistan
                </h3>
                <div className={styles.headerActions}>
                    <button
                        className={styles.headerBtn}
                        onClick={clearChat}
                        title="Sohbeti Temizle"
                    >
                        🗑️
                    </button>
                    <button
                        className={styles.headerBtn}
                        onClick={onClose}
                    >
                        ✕
                    </button>
                </div>
            </div>

            <div className={styles.messages}>
                {messages.length === 0 ? (
                    <div className={styles.emptyState}>
                        <span className={styles.emptyIcon}>💬</span>
                        <h4>Merhaba!</h4>
                        <p>Dokümandan metin veya görsel seçerek başlayabilirsiniz.</p>
                    </div>
                ) : (
                    messages.map(message => (
                        <div
                            key={message.id}
                            className={`${styles.message} ${styles[message.role]}`}
                        >
                            <div className={styles.messageAvatar}>
                                {message.role === 'user' ? '👤' : '✨'}
                            </div>
                            <div className={styles.messageContent}>
                                {message.attachment && message.attachment.type === 'image' && (
                                    <div className={styles.messageImageContainer}>
                                        <img
                                            src={`data:image/png;base64,${message.attachment.content}`}
                                            alt="Görsel eki"
                                            className={styles.messageImage}
                                        />
                                    </div>
                                )}
                                <div className={styles.messageMarkdown}>
                                    <ReactMarkdown remarkPlugins={[remarkGfm]}>
                                        {message.text}
                                    </ReactMarkdown>
                                </div>
                            </div>
                        </div>
                    ))
                )}
                <div ref={messagesEndRef} />
            </div>

            <div className={styles.inputArea}>
                <div className={styles.inputContainer}>
                    {activeSelection && (
                        <div className={styles.activeSelection}>
                            "{activeSelection}"
                            <button
                                className={styles.activeSelectionClose}
                                onClick={(e) => {
                                    e.stopPropagation();
                                    onClearSelection?.();
                                }}
                                title="Seçimi kaldır"
                            >
                                ✕
                            </button>
                        </div>
                    )}
                    {pendingAttachment && (
                        <div className={styles.pendingAttachment}>
                            <img
                                src={`data:image/png;base64,${pendingAttachment}`}
                                alt="Eklenecek görsel"
                                className={styles.pendingImage}
                            />
                            <button
                                className={styles.removeAttachmentBtn}
                                onClick={() => setPendingAttachment(null)}
                            >
                                ✕
                            </button>
                        </div>
                    )}
                    <textarea
                        className={styles.input}
                        value={input}
                        onChange={(e) => setInput(e.target.value)}
                        onKeyDown={handleKeyDown}
                        onMouseDown={(e) => e.stopPropagation()}
                        onFocus={(e) => e.stopPropagation()}
                        placeholder={pendingAttachment ? "Görsel hakkında soru sorun..." : activeSelection ? "Seçili metin hakkında soru sorun..." : "Bir soru sorun..."}
                        rows={1}
                        disabled={isLoading}
                    />
                </div>
                <button
                    className={styles.sendBtn}
                    onClick={() => handleSendMessage()}
                    disabled={(!input.trim() && !pendingAttachment) || isLoading}
                >
                    {isLoading ? (
                        <span className={styles.spinner} />
                    ) : (
                        '→'
                    )}
                </button>
            </div>
        </div>
    );
}
