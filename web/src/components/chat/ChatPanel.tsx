'use client';

import { useState, useRef, useEffect, useCallback, useMemo } from 'react';
import { ChatMessage } from '@/types/models';
import { getAccessToken, getSupabase } from '@/lib/supabase';

type ChatHistoryMessage = { role: 'user' | 'model'; text: string };
type ChatSession = { file_id: string; file_name: string; first_message: string; created_at: string };
import { loadChatHistory, saveChatMessage, clearChatHistory } from '@/lib/chatSync';
import styles from './ChatPanel.module.css';
import ReactMarkdown, { Components } from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { CodeBlock } from './CodeBlock';
import {
    CorioLogo,
    NewChatIcon,
    HistoryIcon,
    CloseIcon,
    SendIcon,
    UserAvatarIcon,
    AIAvatarIcon,
    SparkleIcon,
    TrashIcon,
    QuoteIcon,
    MessageIcon,
} from './ChatIcons';

interface ChatPanelProps {
    isOpen: boolean;
    onClose: () => void;
    documentId?: string;
    documentContext?: string;
    initialMessage?: string;
    initialImage?: string;
    activeSelection?: string | null;
    onClearInitialMessage?: () => void;
    onClearSelection?: () => void;
}

// Default suggestions for empty state
const DEFAULT_SUGGESTIONS = [
    "Bu belgenin ana konusu nedir?",
    "Bu içeriği özetler misin?",
    "En önemli noktaları listele",
    "Bu konuyu basitçe açıkla",
];

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
    const [showHistory, setShowHistory] = useState(false);
    const [historySessions, setHistorySessions] = useState<ChatSession[]>([]);
    const [historyLoading, setHistoryLoading] = useState(false);
    const [copiedMessageId, setCopiedMessageId] = useState<string | null>(null);
    const messagesEndRef = useRef<HTMLDivElement>(null);
    const textareaRef = useRef<HTMLTextAreaElement>(null);
    const [panelWidth, setPanelWidth] = useState(380);
    const resizeStartRef = useRef<{ x: number; width: number } | null>(null);
    const historyRef = useRef<HTMLDivElement>(null);

    // Markdown components with syntax highlighting
    const markdownComponents = useMemo<Components>(() => ({
        code({ className, children, ...props }) {
            const match = /language-(\w+)/.exec(className || '');
            const codeString = String(children).replace(/\n$/, '');
            if (match) {
                return <CodeBlock language={match[1]}>{codeString}</CodeBlock>;
            }
            return <code className={className} {...props}>{children}</code>;
        },
    }), []);

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
                setPendingAttachment(initialImage);
            } else if (initialMessage) {
                handleSendMessage(initialMessage);
            }
            onClearInitialMessage();
        }
    }, [initialMessage, initialImage]);

    // Close history dropdown when clicking outside
    useEffect(() => {
        function handleClickOutside(event: MouseEvent) {
            if (historyRef.current && !historyRef.current.contains(event.target as Node)) {
                setShowHistory(false);
            }
        }
        document.addEventListener('mousedown', handleClickOutside);
        return () => document.removeEventListener('mousedown', handleClickOutside);
    }, []);

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

        setMessages(prev => [...prev, userMessage]);
        setInput('');
        setPendingAttachment(null);
        resetTextareaHeight();

        if (activeSelection && onClearSelection) {
            onClearSelection();
        }

        setIsLoading(true);

        const aiMessageId = (Date.now() + 1).toString();
        const aiMessage: ChatMessage = {
            id: aiMessageId,
            role: 'model',
            text: '',
            timestamp: new Date(),
        };
        setMessages(prev => [...prev, aiMessage]);

        try {
            let fullResponse = '';
            const historyMessages = messages.slice(0, -2);
            const chatHistory: ChatHistoryMessage[] = historyMessages.map(m => ({
                role: m.role as 'user' | 'model',
                text: m.text
            }));

            const accessToken = await getAccessToken();
            if (!accessToken) throw new Error('Not authenticated');

            const response = await fetch('/api/chat', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${accessToken}`
                },
                body: JSON.stringify({
                    message: messageContent,
                    fileId: documentId,
                    history: chatHistory,
                    image: img ?? undefined,
                    context: !documentId ? documentContext : undefined
                })
            });

            if (!response.ok || !response.body) {
                throw new Error(`Chat request failed: ${response.status}`);
            }

            const reader = response.body.getReader();
            const decoder = new TextDecoder();
            while (true) {
                const { done, value } = await reader.read();
                if (done) break;
                fullResponse += decoder.decode(value, { stream: true });
                setMessages(prev =>
                    prev.map(m =>
                        m.id === aiMessageId ? { ...m, text: fullResponse } : m
                    )
                );
            }

            if (documentId) {
                try {
                    await saveChatMessage(documentId, 'user', messageContent);
                    await saveChatMessage(documentId, 'model', fullResponse);
                } catch (saveError) {
                    console.error('Failed to save chat messages:', saveError);
                }
            }
        } catch (err) {
            console.error('Chat error:', err);
            setMessages(prev =>
                prev.map(m => {
                    if (m.id !== aiMessageId) return m;
                    // Preserve any partial response that was streamed
                    const partialText = m.text || '';
                    const errorSuffix = partialText
                        ? '\n\n---\n⚠️ Yanıt tamamlanamadı.'
                        : '⚠️ Bir hata oluştu.';
                    return {
                        ...m,
                        text: partialText + errorSuffix,
                        error: true,
                        originalUserMessage: messageContent,
                    };
                })
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

    const handleNewChat = async () => {
        setMessages([]);
        if (documentId) {
            try {
                await clearChatHistory(documentId);
            } catch (error) {
                console.error('Failed to clear chat history:', error);
            }
        }
    };

    const handleSuggestionClick = (suggestion: string) => {
        handleSendMessage(suggestion);
    };

    const handleRetry = useCallback((message: ChatMessage) => {
        if (!message.originalUserMessage) return;
        // Remove the error message
        setMessages(prev => prev.filter(m => m.id !== message.id));
        handleSendMessage(message.originalUserMessage);
    }, []);

    const handleCopyMessage = useCallback(async (text: string, messageId: string) => {
        await navigator.clipboard.writeText(text);
        setCopiedMessageId(messageId);
        setTimeout(() => setCopiedMessageId(null), 2000);
    }, []);

    // Auto-resize textarea
    const handleInputChange = useCallback((e: React.ChangeEvent<HTMLTextAreaElement>) => {
        setInput(e.target.value);
        const el = e.target;
        el.style.height = 'auto';
        el.style.height = Math.min(el.scrollHeight, 120) + 'px';
    }, []);

    // Reset textarea height after sending
    const resetTextareaHeight = useCallback(() => {
        if (textareaRef.current) {
            textareaRef.current.style.height = 'auto';
        }
    }, []);

    // Fetch real chat sessions for history dropdown
    const fetchChatSessions = useCallback(async () => {
        if (!documentId) return;
        setHistoryLoading(true);
        try {
            const supabase = getSupabase();
            // Get distinct file_ids with their first message from chats table
            const { data, error } = await supabase
                .from('chats')
                .select('file_id, content, created_at')
                .eq('role', 'user')
                .order('created_at', { ascending: true })
                .limit(20);

            if (error) throw error;

            // Group by file_id, take first message per file
            const sessionMap = new Map<string, ChatSession>();
            for (const row of data || []) {
                if (!sessionMap.has(row.file_id)) {
                    sessionMap.set(row.file_id, {
                        file_id: row.file_id,
                        file_name: '',
                        first_message: row.content?.substring(0, 60) || 'Sohbet',
                        created_at: row.created_at,
                    });
                }
            }
            setHistorySessions(Array.from(sessionMap.values()));
        } catch {
            // Non-critical
        } finally {
            setHistoryLoading(false);
        }
    }, [documentId]);

    if (!isOpen) return null;

    const handlePanelMouseDown = (e: React.MouseEvent) => {
        e.stopPropagation();
    };

    const handleResizeStart = (e: React.PointerEvent<HTMLDivElement>) => {
        e.preventDefault();
        e.stopPropagation();

        const startWidth = panelWidth;
        resizeStartRef.current = { x: e.clientX, width: startWidth };

        const minWidth = 320;
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

            {/* Header */}
            <div className={styles.header}>
                <div className={styles.headerLeft}>
                    <div className={styles.logo}>
                        <CorioLogo size={28} className={styles.logoIcon} />
                        <span className={styles.logoText}>Corio AI</span>
                    </div>
                </div>
                <div className={styles.headerActions}>
                    <button
                        className={styles.iconBtn}
                        onClick={handleNewChat}
                        title="Yeni Sohbet"
                    >
                        <NewChatIcon size={18} />
                    </button>
                    <div className={styles.historyContainer} ref={historyRef}>
                        <button
                            className={styles.iconBtn}
                            onClick={() => {
                                const next = !showHistory;
                                setShowHistory(next);
                                if (next) fetchChatSessions();
                            }}
                            title="Sohbet Geçmişi"
                        >
                            <HistoryIcon size={18} />
                        </button>
                        {showHistory && (
                            <div className={styles.historyDropdown}>
                                <div className={styles.historyHeader}>Sohbet Geçmişi</div>
                                {historyLoading ? (
                                    <div className={styles.historyEmpty}>Yükleniyor...</div>
                                ) : historySessions.length > 0 ? (
                                    historySessions.map(session => (
                                        <div
                                            key={session.file_id}
                                            className={`${styles.historyItem} ${session.file_id === documentId ? styles.historyItemActive : ''}`}
                                        >
                                            <MessageIcon size={20} className={styles.historyItemIcon} />
                                            <div className={styles.historyItemText}>
                                                <div className={styles.historyItemTitle}>
                                                    {session.first_message}
                                                </div>
                                                <div className={styles.historyItemDate}>
                                                    {new Date(session.created_at).toLocaleDateString('tr-TR')}
                                                </div>
                                            </div>
                                        </div>
                                    ))
                                ) : (
                                    <div className={styles.historyEmpty}>
                                        Henüz sohbet geçmişi yok
                                    </div>
                                )}
                            </div>
                        )}
                    </div>
                    <button
                        className={`${styles.iconBtn} ${styles.iconBtnDanger}`}
                        onClick={handleNewChat}
                        title="Sohbeti Temizle"
                    >
                        <TrashIcon size={18} />
                    </button>
                    <button
                        className={styles.iconBtn}
                        onClick={onClose}
                        title="Kapat"
                    >
                        <CloseIcon size={18} />
                    </button>
                </div>
            </div>

            {/* Messages */}
            <div className={styles.messages}>
                {messages.length === 0 ? (
                    <div className={styles.emptyState}>
                        <MessageIcon size={56} className={styles.emptyIcon} />
                        <h3 className={styles.emptyTitle}>Merhaba! Ben Corio AI</h3>
                        <p className={styles.emptySubtitle}>
                            Belgeniz hakkında sorular sorabilir, özetler isteyebilir veya herhangi bir konuda yardım alabilirsiniz.
                        </p>
                        <div className={styles.suggestions}>
                            {DEFAULT_SUGGESTIONS.map((suggestion, index) => (
                                <button
                                    key={index}
                                    className={styles.suggestionChip}
                                    onClick={() => handleSuggestionClick(suggestion)}
                                >
                                    <SparkleIcon size={16} className={styles.suggestionIcon} />
                                    <span className={styles.suggestionText}>{suggestion}</span>
                                </button>
                            ))}
                        </div>
                    </div>
                ) : (
                    messages.map(message => (
                        <div
                            key={message.id}
                            className={`${styles.message} ${styles[message.role]} ${message.error ? styles.messageError : ''}`}
                        >
                            <div className={styles.messageAvatar}>
                                {message.role === 'user' ? (
                                    <UserAvatarIcon size={28} />
                                ) : (
                                    <AIAvatarIcon size={28} />
                                )}
                            </div>
                            <div className={styles.messageBubble}>
                                {message.attachment && message.attachment.type === 'image' && (
                                    <div className={styles.messageImageContainer}>
                                        <img
                                            src={`data:image/png;base64,${message.attachment.content}`}
                                            alt="Görsel eki"
                                            className={styles.messageImage}
                                        />
                                    </div>
                                )}
                                {message.text ? (
                                    <div className={styles.messageMarkdown}>
                                        <ReactMarkdown
                                            remarkPlugins={[remarkGfm]}
                                            components={message.role === 'model' ? markdownComponents : undefined}
                                        >
                                            {message.text}
                                        </ReactMarkdown>
                                    </div>
                                ) : (
                                    <div className={styles.typingIndicator}>
                                        <span className={styles.typingDot} />
                                        <span className={styles.typingDot} />
                                        <span className={styles.typingDot} />
                                    </div>
                                )}
                                {/* Action buttons for AI messages */}
                                {message.role === 'model' && message.text && (
                                    <div className={styles.messageActions}>
                                        <button
                                            className={styles.messageActionBtn}
                                            onClick={() => handleCopyMessage(message.text, message.id)}
                                            title="Kopyala"
                                        >
                                            {copiedMessageId === message.id ? 'Kopyalandı!' : '📋 Kopyala'}
                                        </button>
                                        {message.error && message.originalUserMessage && (
                                            <button
                                                className={`${styles.messageActionBtn} ${styles.retryBtn}`}
                                                onClick={() => handleRetry(message)}
                                                disabled={isLoading}
                                            >
                                                🔄 Tekrar Dene
                                            </button>
                                        )}
                                    </div>
                                )}
                            </div>
                        </div>
                    ))
                )}
                <div ref={messagesEndRef} />
            </div>

            {/* Input Area */}
            <div className={styles.inputArea}>
                <div className={styles.inputWrapper}>
                    <div className={styles.inputContainer}>
                        {activeSelection && (
                            <div className={styles.selectedQuote}>
                                <QuoteIcon size={16} className={styles.quoteIcon} />
                                <div className={styles.quoteContent}>
                                    <div className={styles.quoteText}>&quot;{activeSelection}&quot;</div>
                                </div>
                                <button
                                    className={styles.quoteClose}
                                    onClick={(e) => {
                                        e.stopPropagation();
                                        onClearSelection?.();
                                    }}
                                    title="Seçimi kaldır"
                                >
                                    <CloseIcon size={14} />
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
                            ref={textareaRef}
                            className={styles.input}
                            value={input}
                            onChange={handleInputChange}
                            onKeyDown={handleKeyDown}
                            onMouseDown={(e) => e.stopPropagation()}
                            onFocus={(e) => e.stopPropagation()}
                            placeholder={
                                pendingAttachment
                                    ? "Görsel hakkında soru sorun..."
                                    : activeSelection
                                        ? "Seçili metin hakkında soru sorun..."
                                        : "Mesajınızı yazın..."
                            }
                            rows={1}
                            disabled={isLoading}
                        />
                    </div>
                </div>
                <button
                    className={styles.sendBtn}
                    onClick={() => handleSendMessage()}
                    disabled={(!input.trim() && !pendingAttachment) || isLoading}
                >
                    {isLoading ? (
                        <span className={styles.spinner} />
                    ) : (
                        <SendIcon size={20} />
                    )}
                </button>
            </div>
        </div>
    );
}
