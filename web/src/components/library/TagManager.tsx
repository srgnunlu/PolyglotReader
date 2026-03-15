'use client';

import { useState } from 'react';
import { getSupabase } from '@/lib/supabase';
import { useToast } from '@/contexts/ToastContext';
import { Tag } from '@/types/models';

interface TagManagerProps {
    tags: Tag[];
    selectedTag: string | null;
    onSelectTag: (id: string | null) => void;
    onRefresh: () => void;
}

const TAG_COLORS = ['#22C55E', '#3B82F6', '#F59E0B', '#EF4444', '#8B5CF6', '#EC4899', '#06B6D4'];

export function TagManager({ tags, selectedTag, onSelectTag, onRefresh }: TagManagerProps) {
    const [showAdd, setShowAdd] = useState(false);
    const [newName, setNewName] = useState('');
    const [newColor, setNewColor] = useState(TAG_COLORS[0]);
    const [isSaving, setIsSaving] = useState(false);
    const { showToast } = useToast();

    const handleAdd = async () => {
        if (!newName.trim()) return;
        setIsSaving(true);
        try {
            const supabase = getSupabase();
            const { data: { user } } = await supabase.auth.getUser();
            if (!user) throw new Error('Not authenticated');

            const { error } = await supabase
                .from('tags')
                .insert({ user_id: user.id, name: newName.trim(), color: newColor, is_auto_generated: false });
            if (error) throw error;

            showToast('Etiket oluşturuldu', 'success');
            setNewName('');
            setShowAdd(false);
            onRefresh();
        } catch (err) {
            console.error('Tag create error:', err);
            showToast('Etiket oluşturulamadı', 'error');
        } finally {
            setIsSaving(false);
        }
    };

    const handleDelete = async (tagId: string, tagName: string) => {
        if (!confirm(`"${tagName}" etiketini silmek istediğinize emin misiniz?`)) return;
        try {
            const supabase = getSupabase();
            const { error } = await supabase.from('tags').delete().eq('id', tagId);
            if (error) throw error;
            showToast('Etiket silindi', 'success');
            if (selectedTag === tagId) onSelectTag(null);
            onRefresh();
        } catch {
            showToast('Etiket silinemedi', 'error');
        }
    };

    return (
        <div>
            <div style={{
                display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                padding: '0 16px', marginBottom: 4,
            }}>
                <h3 style={{
                    fontSize: '0.7rem', fontWeight: 600, textTransform: 'uppercase',
                    letterSpacing: '0.05em', color: 'var(--text-tertiary)',
                }}>
                    Etiketler
                </h3>
                <button
                    onClick={() => setShowAdd(!showAdd)}
                    style={{
                        background: 'none', border: 'none', cursor: 'pointer',
                        color: 'var(--color-primary-500)', fontSize: '1.1rem', padding: 0,
                        lineHeight: 1,
                    }}
                    title="Yeni etiket"
                >
                    +
                </button>
            </div>

            {showAdd && (
                <div style={{ padding: '8px 16px', display: 'flex', flexDirection: 'column', gap: 8 }}>
                    <input
                        type="text"
                        value={newName}
                        onChange={(e) => setNewName(e.target.value)}
                        placeholder="Etiket adı..."
                        autoFocus
                        onKeyDown={(e) => e.key === 'Enter' && handleAdd()}
                        style={{
                            width: '100%', padding: '6px 10px', borderRadius: 8,
                            border: '1px solid var(--border-color)', fontSize: '0.8rem',
                            background: 'var(--bg-primary)', color: 'var(--text-primary)',
                            outline: 'none', boxSizing: 'border-box',
                        }}
                    />
                    <div style={{ display: 'flex', gap: 4 }}>
                        {TAG_COLORS.map(c => (
                            <button
                                key={c}
                                type="button"
                                onClick={() => setNewColor(c)}
                                style={{
                                    width: 18, height: 18, borderRadius: '50%', background: c,
                                    border: newColor === c ? '2px solid var(--text-primary)' : '1px solid transparent',
                                    cursor: 'pointer', padding: 0,
                                }}
                            />
                        ))}
                    </div>
                    <div style={{ display: 'flex', gap: 4 }}>
                        <button
                            onClick={handleAdd}
                            disabled={isSaving || !newName.trim()}
                            style={{
                                flex: 1, padding: '4px 8px', borderRadius: 6,
                                background: 'var(--color-primary-500)', color: 'white',
                                border: 'none', cursor: 'pointer', fontSize: '0.75rem', fontWeight: 600,
                                opacity: isSaving || !newName.trim() ? 0.5 : 1,
                            }}
                        >
                            Ekle
                        </button>
                        <button
                            onClick={() => setShowAdd(false)}
                            style={{
                                padding: '4px 8px', borderRadius: 6,
                                background: 'var(--bg-tertiary)', color: 'var(--text-secondary)',
                                border: 'none', cursor: 'pointer', fontSize: '0.75rem',
                            }}
                        >
                            Vazgeç
                        </button>
                    </div>
                </div>
            )}

            {tags.map(tag => (
                <div
                    key={tag.id}
                    style={{
                        display: 'flex', alignItems: 'center', gap: 8,
                        padding: '8px 16px', cursor: 'pointer',
                        background: selectedTag === tag.id ? 'var(--bg-tertiary)' : 'transparent',
                        transition: 'background 0.15s',
                        borderRadius: 8, margin: '0 8px',
                    }}
                    onClick={() => onSelectTag(selectedTag === tag.id ? null : tag.id)}
                >
                    <span style={{
                        width: 10, height: 10, borderRadius: '50%',
                        background: tag.color, flexShrink: 0,
                    }} />
                    <span style={{
                        flex: 1, fontSize: '0.85rem', color: 'var(--text-primary)',
                        overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                    }}>
                        {tag.name}
                    </span>
                    <button
                        onClick={(e) => { e.stopPropagation(); handleDelete(tag.id, tag.name); }}
                        style={{
                            background: 'none', border: 'none', cursor: 'pointer',
                            color: 'var(--text-tertiary)', fontSize: '0.75rem',
                            opacity: 0.5, padding: '2px 4px',
                        }}
                        title="Sil"
                    >
                        &times;
                    </button>
                </div>
            ))}
        </div>
    );
}
