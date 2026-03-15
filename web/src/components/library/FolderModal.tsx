'use client';

import { useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { useToast } from '@/contexts/ToastContext';
import { Folder } from '@/types/models';

interface FolderModalProps {
    folder?: Folder | null;
    onClose: () => void;
    onSave: () => void;
}

const FOLDER_COLORS = [
    '#6366F1', '#8B5CF6', '#EC4899', '#EF4444',
    '#F59E0B', '#22C55E', '#06B6D4', '#3B82F6',
];

export function FolderModal({ folder, onClose, onSave }: FolderModalProps) {
    const [name, setName] = useState(folder?.name || '');
    const [color, setColor] = useState(folder?.color || FOLDER_COLORS[0]);
    const [isSaving, setIsSaving] = useState(false);
    const { showToast } = useToast();

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        if (!name.trim()) return;

        setIsSaving(true);
        try {
            const supabase = getSupabase();
            const { data: { user } } = await supabase.auth.getUser();
            if (!user) throw new Error('Not authenticated');

            if (folder) {
                const { error } = await supabase
                    .from('folders')
                    .update({ name: name.trim(), color })
                    .eq('id', folder.id);
                if (error) throw error;
                showToast('Klasör güncellendi', 'success');
            } else {
                const { error } = await supabase
                    .from('folders')
                    .insert({ user_id: user.id, name: name.trim(), color });
                if (error) throw error;
                showToast('Klasör oluşturuldu', 'success');
            }
            onSave();
            onClose();
        } catch (err) {
            console.error('Folder save error:', err);
            showToast('Klasör kaydedilemedi', 'error');
        } finally {
            setIsSaving(false);
        }
    };

    const handleDelete = async () => {
        if (!folder) return;
        if (!confirm('Bu klasörü silmek istediğinize emin misiniz?')) return;

        setIsSaving(true);
        try {
            const supabase = getSupabase();
            const { error } = await supabase.from('folders').delete().eq('id', folder.id);
            if (error) throw error;
            showToast('Klasör silindi', 'success');
            onSave();
            onClose();
        } catch (err) {
            console.error('Folder delete error:', err);
            showToast('Klasör silinemedi', 'error');
        } finally {
            setIsSaving(false);
        }
    };

    return (
        <div
            style={{
                position: 'fixed', inset: 0, zIndex: 1000,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                background: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(4px)',
            }}
            onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
        >
            <div style={{
                background: 'var(--bg-secondary, white)', borderRadius: 20,
                padding: 28, width: '90%', maxWidth: 400,
                boxShadow: '0 24px 48px rgba(0,0,0,0.2)',
            }}>
                <h2 style={{ fontSize: '1.15rem', fontWeight: 700, marginBottom: 20, color: 'var(--text-primary)' }}>
                    {folder ? 'Klasörü Düzenle' : 'Yeni Klasör'}
                </h2>

                <form onSubmit={handleSubmit}>
                    <div style={{ marginBottom: 16 }}>
                        <label style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--text-secondary)', display: 'block', marginBottom: 6 }}>
                            Klasör Adı
                        </label>
                        <input
                            type="text"
                            value={name}
                            onChange={(e) => setName(e.target.value)}
                            placeholder="Klasör adı girin..."
                            autoFocus
                            style={{
                                width: '100%', padding: '10px 14px', borderRadius: 10,
                                border: '1px solid var(--border-color, #e5e7eb)',
                                background: 'var(--bg-primary, white)',
                                color: 'var(--text-primary)', fontSize: '0.9rem',
                                outline: 'none', boxSizing: 'border-box',
                            }}
                        />
                    </div>

                    <div style={{ marginBottom: 20 }}>
                        <label style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--text-secondary)', display: 'block', marginBottom: 8 }}>
                            Renk
                        </label>
                        <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                            {FOLDER_COLORS.map(c => (
                                <button
                                    key={c}
                                    type="button"
                                    onClick={() => setColor(c)}
                                    style={{
                                        width: 32, height: 32, borderRadius: '50%',
                                        background: c, border: color === c ? '3px solid var(--text-primary)' : '2px solid transparent',
                                        cursor: 'pointer', transition: 'transform 0.15s',
                                        transform: color === c ? 'scale(1.15)' : 'scale(1)',
                                    }}
                                />
                            ))}
                        </div>
                    </div>

                    <div style={{ display: 'flex', gap: 8, justifyContent: 'flex-end' }}>
                        {folder && (
                            <button
                                type="button"
                                onClick={handleDelete}
                                disabled={isSaving}
                                style={{
                                    padding: '8px 16px', borderRadius: 10,
                                    background: 'rgba(239,68,68,0.1)', color: '#dc2626',
                                    border: 'none', cursor: 'pointer', fontWeight: 600, fontSize: '0.85rem',
                                    marginRight: 'auto',
                                }}
                            >
                                Sil
                            </button>
                        )}
                        <button
                            type="button"
                            onClick={onClose}
                            style={{
                                padding: '8px 16px', borderRadius: 10,
                                background: 'var(--bg-tertiary)', color: 'var(--text-secondary)',
                                border: 'none', cursor: 'pointer', fontWeight: 500, fontSize: '0.85rem',
                            }}
                        >
                            Vazgeç
                        </button>
                        <button
                            type="submit"
                            disabled={isSaving || !name.trim()}
                            style={{
                                padding: '8px 20px', borderRadius: 10,
                                background: 'linear-gradient(135deg, var(--color-primary-500), var(--color-primary-600))',
                                color: 'white', border: 'none', cursor: 'pointer',
                                fontWeight: 600, fontSize: '0.85rem',
                                opacity: isSaving || !name.trim() ? 0.5 : 1,
                            }}
                        >
                            {isSaving ? 'Kaydediliyor...' : 'Kaydet'}
                        </button>
                    </div>
                </form>
            </div>
        </div>
    );
}
