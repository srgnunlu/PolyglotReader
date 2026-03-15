'use client';

import { useState, useEffect, useRef } from 'react';
import { getAccessToken } from '@/lib/supabase';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

interface SummaryPanelProps {
    fileId: string;
    documentText: string;
    existingSummary?: string;
    onClose: () => void;
}

export function SummaryPanel({ fileId, documentText, existingSummary, onClose }: SummaryPanelProps) {
    const [summary, setSummary] = useState(existingSummary || '');
    const [isLoading, setIsLoading] = useState(!existingSummary);
    const [error, setError] = useState<string | null>(null);
    const contentRef = useRef<HTMLDivElement>(null);

    useEffect(() => {
        if (existingSummary) return;

        const generateSummary = async () => {
            setIsLoading(true);
            setError(null);
            try {
                const token = await getAccessToken();
                if (!token) throw new Error('Not authenticated');

                const response = await fetch('/api/summarize', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'Authorization': `Bearer ${token}`,
                    },
                    body: JSON.stringify({ fileId, text: documentText }),
                });

                if (!response.ok || !response.body) throw new Error('Summarization failed');

                const reader = response.body.getReader();
                const decoder = new TextDecoder();
                let full = '';
                while (true) {
                    const { done, value } = await reader.read();
                    if (done) break;
                    full += decoder.decode(value, { stream: true });
                    setSummary(full);
                }
            } catch (err) {
                console.error('Summary error:', err);
                setError('Özet oluşturulamadı');
            } finally {
                setIsLoading(false);
            }
        };

        generateSummary();
    }, [fileId, documentText, existingSummary]);

    useEffect(() => {
        if (contentRef.current) {
            contentRef.current.scrollTop = contentRef.current.scrollHeight;
        }
    }, [summary]);

    return (
        <div style={{
            position: 'fixed', inset: 0, zIndex: 900,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            background: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(4px)',
        }}
            onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
        >
            <div style={{
                background: 'var(--bg-secondary, white)', borderRadius: 20,
                width: '90%', maxWidth: 600, maxHeight: '80vh',
                display: 'flex', flexDirection: 'column',
                boxShadow: '0 24px 48px rgba(0,0,0,0.2)',
                overflow: 'hidden',
            }}>
                {/* Header */}
                <div style={{
                    padding: '20px 24px', borderBottom: '1px solid var(--border-color)',
                    display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                }}>
                    <h2 style={{ fontSize: '1.1rem', fontWeight: 700, color: 'var(--text-primary)', margin: 0 }}>
                        Doküman Özeti
                    </h2>
                    <button
                        onClick={onClose}
                        style={{
                            background: 'none', border: 'none', cursor: 'pointer',
                            color: 'var(--text-tertiary)', fontSize: '1.5rem', lineHeight: 1,
                        }}
                    >
                        &times;
                    </button>
                </div>

                {/* Content */}
                <div ref={contentRef} style={{
                    padding: '20px 24px', flex: 1, overflowY: 'auto',
                    fontSize: '0.9rem', lineHeight: 1.7, color: 'var(--text-primary)',
                }}>
                    {error ? (
                        <div style={{ textAlign: 'center', padding: 40, color: 'var(--color-error)' }}>
                            <p>{error}</p>
                            <button
                                onClick={() => { setError(null); setSummary(''); setIsLoading(true); }}
                                style={{
                                    marginTop: 12, padding: '8px 16px', borderRadius: 8,
                                    background: 'var(--color-primary-500)', color: 'white',
                                    border: 'none', cursor: 'pointer',
                                }}
                            >
                                Tekrar Dene
                            </button>
                        </div>
                    ) : (
                        <>
                            {summary && (
                                <ReactMarkdown remarkPlugins={[remarkGfm]}>
                                    {summary}
                                </ReactMarkdown>
                            )}
                            {isLoading && (
                                <div style={{
                                    display: 'flex', alignItems: 'center', gap: 8,
                                    color: 'var(--text-tertiary)', padding: '8px 0',
                                }}>
                                    <span style={{
                                        width: 16, height: 16, borderRadius: '50%',
                                        border: '2px solid var(--color-primary-300)',
                                        borderTopColor: 'var(--color-primary-500)',
                                        animation: 'spin 0.8s linear infinite',
                                        display: 'inline-block',
                                    }} />
                                    <span style={{ fontSize: '0.85rem' }}>
                                        {summary ? 'Özet oluşturuluyor...' : 'Doküman analiz ediliyor...'}
                                    </span>
                                    <style>{`@keyframes spin { to { transform: rotate(360deg); } }`}</style>
                                </div>
                            )}
                        </>
                    )}
                </div>
            </div>
        </div>
    );
}
