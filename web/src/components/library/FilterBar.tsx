'use client';

import { useState } from 'react';
import { Tag } from '@/types/models';

export type SortOption = 'date_desc' | 'date_asc' | 'name_asc' | 'name_desc' | 'size_desc';

interface FilterBarProps {
    tags: Tag[];
    selectedTags: string[];
    sortBy: SortOption;
    onTagToggle: (tagId: string) => void;
    onSortChange: (sort: SortOption) => void;
    onClearFilters: () => void;
}

const SORT_OPTIONS: { value: SortOption; label: string }[] = [
    { value: 'date_desc', label: 'En yeni' },
    { value: 'date_asc', label: 'En eski' },
    { value: 'name_asc', label: 'A-Z' },
    { value: 'name_desc', label: 'Z-A' },
    { value: 'size_desc', label: 'En büyük' },
];

export function FilterBar({ tags, selectedTags, sortBy, onTagToggle, onSortChange, onClearFilters }: FilterBarProps) {
    const [isOpen, setIsOpen] = useState(false);
    const hasFilters = selectedTags.length > 0 || sortBy !== 'date_desc';

    return (
        <div style={{ marginBottom: 16 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                <button
                    onClick={() => setIsOpen(!isOpen)}
                    style={{
                        display: 'flex', alignItems: 'center', gap: 6,
                        padding: '8px 14px', borderRadius: 10,
                        background: hasFilters ? 'rgba(99,102,241,0.1)' : 'var(--bg-tertiary, #f5f5f4)',
                        color: hasFilters ? 'var(--color-primary-500)' : 'var(--text-secondary)',
                        border: hasFilters ? '1px solid rgba(99,102,241,0.3)' : '1px solid var(--border-color, #e5e7eb)',
                        cursor: 'pointer', fontSize: '0.8rem', fontWeight: 600,
                        transition: 'all 0.15s',
                    }}
                >
                    Filtreler {hasFilters && `(${selectedTags.length + (sortBy !== 'date_desc' ? 1 : 0)})`}
                </button>

                {/* Sort chips */}
                <div style={{ display: 'flex', gap: 4 }}>
                    {SORT_OPTIONS.map(opt => (
                        <button
                            key={opt.value}
                            onClick={() => onSortChange(opt.value)}
                            style={{
                                padding: '6px 10px', borderRadius: 8,
                                background: sortBy === opt.value ? 'var(--color-primary-500)' : 'transparent',
                                color: sortBy === opt.value ? 'white' : 'var(--text-tertiary)',
                                border: 'none', cursor: 'pointer', fontSize: '0.75rem', fontWeight: 500,
                                transition: 'all 0.15s',
                            }}
                        >
                            {opt.label}
                        </button>
                    ))}
                </div>

                {hasFilters && (
                    <button
                        onClick={onClearFilters}
                        style={{
                            padding: '6px 10px', borderRadius: 8,
                            background: 'none', color: 'var(--text-tertiary)',
                            border: 'none', cursor: 'pointer', fontSize: '0.75rem',
                        }}
                    >
                        Temizle
                    </button>
                )}
            </div>

            {/* Tag filter chips */}
            {isOpen && tags.length > 0 && (
                <div style={{
                    display: 'flex', gap: 6, flexWrap: 'wrap', marginTop: 10,
                    padding: 12, background: 'var(--bg-tertiary, #f5f5f4)',
                    borderRadius: 12,
                }}>
                    <span style={{ fontSize: '0.75rem', color: 'var(--text-tertiary)', fontWeight: 600, marginRight: 4, alignSelf: 'center' }}>
                        Etiketler:
                    </span>
                    {tags.map(tag => (
                        <button
                            key={tag.id}
                            onClick={() => onTagToggle(tag.id)}
                            style={{
                                display: 'flex', alignItems: 'center', gap: 4,
                                padding: '4px 10px', borderRadius: 16,
                                background: selectedTags.includes(tag.id) ? tag.color + '30' : 'var(--bg-secondary, white)',
                                border: selectedTags.includes(tag.id) ? `1px solid ${tag.color}` : '1px solid var(--border-color)',
                                cursor: 'pointer', fontSize: '0.75rem',
                                color: 'var(--text-primary)', fontWeight: 500,
                                transition: 'all 0.15s',
                            }}
                        >
                            <span style={{ width: 8, height: 8, borderRadius: '50%', background: tag.color }} />
                            {tag.name}
                        </button>
                    ))}
                </div>
            )}
        </div>
    );
}
