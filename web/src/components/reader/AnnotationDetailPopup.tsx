'use client';

import { useState } from 'react';
import { Annotation } from '@/types/models';
import { useAnnotations } from '@/contexts/AnnotationContext';

interface AnnotationDetailPopupProps {
    annotation: Annotation;
    position: { x: number; y: number };
    onClose: () => void;
}

const HIGHLIGHT_COLORS = [
    { name: 'Sarı', color: '#fef08a' },
    { name: 'Yeşil', color: '#bbf7d0' },
    { name: 'Mavi', color: '#bae6fd' },
    { name: 'Pembe', color: '#fbcfe8' },
];

export function AnnotationDetailPopup({ annotation, position, onClose }: AnnotationDetailPopupProps) {
    const [note, setNote] = useState(annotation.note || '');
    const [isSaving, setIsSaving] = useState(false);
    const { updateAnnotationNote, removeAnnotation } = useAnnotations();

    const handleSaveNote = async () => {
        setIsSaving(true);
        try {
            await updateAnnotationNote(annotation.id, note);
        } catch {
            // handled by context
        } finally {
            setIsSaving(false);
        }
    };

    const handleDelete = async () => {
        try {
            await removeAnnotation(annotation.id);
            onClose();
        } catch {
            // handled by context
        }
    };

    return (
        <>
            <div
                style={{ position: 'fixed', inset: 0, zIndex: 500 }}
                onClick={onClose}
            />
            <div
                style={{
                    position: 'absolute',
                    left: position.x,
                    top: position.y,
                    transform: 'translateX(-50%)',
                    zIndex: 501,
                    background: 'var(--bg-secondary, white)',
                    borderRadius: 14,
                    padding: 16,
                    width: 280,
                    boxShadow: '0 8px 32px rgba(0,0,0,0.18)',
                    border: '1px solid var(--border-color, #e5e7eb)',
                    animation: 'toastSlideIn 0.2s ease',
                }}
            >
                {/* Color indicator + text preview */}
                <div style={{
                    display: 'flex', alignItems: 'flex-start', gap: 10, marginBottom: 12,
                    paddingBottom: 12, borderBottom: '1px solid var(--border-color, #e5e7eb)',
                }}>
                    <span style={{
                        width: 14, height: 14, borderRadius: 4, flexShrink: 0, marginTop: 2,
                        background: annotation.color, border: '1px solid rgba(0,0,0,0.1)',
                    }} />
                    <div style={{ flex: 1, minWidth: 0 }}>
                        <div style={{ fontSize: '0.8rem', color: 'var(--text-tertiary)', marginBottom: 2 }}>
                            Sayfa {annotation.pageNumber} &middot; {annotation.type === 'highlight' ? 'Vurgu' : annotation.type === 'underline' ? 'Altı çizili' : 'Üstü çizili'}
                        </div>
                        {annotation.text && (
                            <p style={{
                                fontSize: '0.85rem', color: 'var(--text-primary)', margin: 0,
                                lineHeight: 1.4, overflow: 'hidden', textOverflow: 'ellipsis',
                                display: '-webkit-box', WebkitLineClamp: 3, WebkitBoxOrient: 'vertical',
                            }}>
                                &quot;{annotation.text}&quot;
                            </p>
                        )}
                    </div>
                </div>

                {/* Note textarea */}
                <div style={{ marginBottom: 12 }}>
                    <label style={{ fontSize: '0.75rem', fontWeight: 600, color: 'var(--text-secondary)', display: 'block', marginBottom: 4 }}>
                        Not
                    </label>
                    <textarea
                        value={note}
                        onChange={(e) => setNote(e.target.value)}
                        placeholder="Not ekleyin..."
                        rows={3}
                        style={{
                            width: '100%', padding: '8px 10px', borderRadius: 8,
                            border: '1px solid var(--border-color)', fontSize: '0.85rem',
                            background: 'var(--bg-primary)', color: 'var(--text-primary)',
                            outline: 'none', resize: 'vertical', fontFamily: 'inherit',
                            boxSizing: 'border-box',
                        }}
                    />
                </div>

                {/* Actions */}
                <div style={{ display: 'flex', gap: 6, justifyContent: 'space-between' }}>
                    <button
                        onClick={handleDelete}
                        style={{
                            padding: '6px 12px', borderRadius: 8,
                            background: 'rgba(239,68,68,0.1)', color: '#dc2626',
                            border: 'none', cursor: 'pointer', fontSize: '0.8rem', fontWeight: 600,
                        }}
                    >
                        Sil
                    </button>
                    <div style={{ display: 'flex', gap: 6 }}>
                        <button
                            onClick={onClose}
                            style={{
                                padding: '6px 12px', borderRadius: 8,
                                background: 'var(--bg-tertiary)', color: 'var(--text-secondary)',
                                border: 'none', cursor: 'pointer', fontSize: '0.8rem',
                            }}
                        >
                            Kapat
                        </button>
                        <button
                            onClick={handleSaveNote}
                            disabled={isSaving}
                            style={{
                                padding: '6px 14px', borderRadius: 8,
                                background: 'var(--color-primary-500)', color: 'white',
                                border: 'none', cursor: 'pointer', fontSize: '0.8rem', fontWeight: 600,
                                opacity: isSaving ? 0.6 : 1,
                            }}
                        >
                            {isSaving ? 'Kaydediliyor...' : 'Kaydet'}
                        </button>
                    </div>
                </div>
            </div>
        </>
    );
}
