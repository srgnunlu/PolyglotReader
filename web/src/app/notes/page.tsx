'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { ProtectedRoute } from '@/components/auth/ProtectedRoute';
import { getSupabase } from '@/lib/supabase';
import { useAuth } from '@/hooks/useAuth';
import { SkeletonNoteCard, SkeletonStyles } from '@/components/ui/Skeleton';
import styles from './notes.module.css';

interface Note {
    id: string;
    fileId: string;
    fileName: string;
    pageNumber: number;
    text: string;
    note: string;
    color: string;
    createdAt: Date;
}

export default function NotesPage() {
    return (
        <ProtectedRoute>
            <NotesContent />
        </ProtectedRoute>
    );
}

function NotesContent() {
    const router = useRouter();
    const supabase = getSupabase();
    const { user, signOut } = useAuth();

    const [notes, setNotes] = useState<Note[]>([]);
    const [isLoading, setIsLoading] = useState(true);
    const [searchQuery, setSearchQuery] = useState('');
    const [error, setError] = useState<string | null>(null);
    const [showAll, setShowAll] = useState(false);

    // Fetch notes from Supabase
    useEffect(() => {
        const fetchNotes = async () => {
            setIsLoading(true);
            setError(null);

            try {
                // Fetch annotations with their file names
                // data column is JSONB containing: text, note, color, rects, isAiGenerated
                const { data, error: fetchError } = await supabase
                    .from('annotations')
                    .select(`
            id,
            file_id,
            page,
            type,
            data,
            created_at,
            files!inner(name)
          `)
                    .order('created_at', { ascending: false });

                if (fetchError) throw fetchError;

                const mappedNotes: Note[] = (data || [])
                    .map((item: Record<string, unknown>) => {
                        const itemData = item.data as { text?: string; note?: string; color?: string };
                        return {
                            id: item.id as string,
                            fileId: item.file_id as string,
                            fileName: (item.files as { name: string })?.name || 'Bilinmeyen Dosya',
                            pageNumber: item.page as number,
                            text: itemData?.text || '',
                            note: itemData?.note || '',
                            color: itemData?.color || '#fef08a',
                            createdAt: new Date(item.created_at as string),
                        };
                    });

                setNotes(mappedNotes);
            } catch (err) {
                console.error('Fetch notes error:', err);
                setError('Notlar yüklenemedi');
            } finally {
                setIsLoading(false);
            }
        };

        fetchNotes();
    }, [supabase]);

    // Filter notes by search and showAll toggle
    const filteredNotes = notes.filter(note => {
        if (!showAll && !note.note) return false;
        const q = searchQuery.toLowerCase();
        return !q || note.text.toLowerCase().includes(q) ||
            note.note.toLowerCase().includes(q) ||
            note.fileName.toLowerCase().includes(q);
    });

    // Group notes by file
    const groupedNotes = filteredNotes.reduce((acc, note) => {
        if (!acc[note.fileId]) {
            acc[note.fileId] = {
                fileName: note.fileName,
                notes: [],
            };
        }
        acc[note.fileId].notes.push(note);
        return acc;
    }, {} as Record<string, { fileName: string; notes: Note[] }>);

    const handleNoteClick = (note: Note) => {
        router.push(`/reader/${note.fileId}?page=${note.pageNumber}`);
    };

    return (
        <div className={styles.layout}>
            {/* Animated Background */}
            <div className={styles.backgroundOrbs}>
                <div className={`${styles.orb} ${styles.orb1}`} />
                <div className={`${styles.orb} ${styles.orb2}`} />
            </div>

            {/* Sidebar */}
            <aside className={styles.sidebar}>
                <div className={styles.sidebarHeader}>
                    <div className={styles.logoSection}>
                        <span className={styles.logoIcon}>📄</span>
                        <h1 className={styles.logoText}>Corio Docs</h1>
                    </div>
                </div>

                <nav className={styles.nav}>
                    <button
                        className={styles.navItem}
                        onClick={() => router.push('/library')}
                    >
                        <span className={styles.navIcon}>📁</span>
                        <span>Kütüphane</span>
                    </button>
                    <button className={`${styles.navItem} ${styles.navItemActive}`}>
                        <span className={styles.navIcon}>📝</span>
                        <span>Notlarım</span>
                    </button>
                </nav>

                <div className={styles.sidebarFooter}>
                    <div className={styles.userInfo}>
                        <div className={styles.userAvatar}>
                            {user?.name?.charAt(0).toUpperCase() || '?'}
                        </div>
                        <div className={styles.userDetails}>
                            <span className={styles.userName}>{user?.name}</span>
                            <span className={styles.userEmail}>{user?.email}</span>
                        </div>
                    </div>
                    <button className={styles.logoutBtn} onClick={signOut}>
                        Çıkış Yap
                    </button>
                </div>
            </aside>

            {/* Main Content */}
            <main className={styles.main}>
                <header className={styles.header}>
                    <h2 className={styles.title}>📝 Notlarım</h2>
                    <div style={{ display: 'flex', gap: 12, alignItems: 'center', flex: 1 }}>
                        <div className={styles.searchBox}>
                            <span className={styles.searchIcon}>🔍</span>
                            <input
                                type="text"
                                placeholder="Notlarda ara..."
                                className={styles.searchInput}
                                value={searchQuery}
                                onChange={(e) => setSearchQuery(e.target.value)}
                            />
                        </div>
                        <button
                            onClick={() => setShowAll(!showAll)}
                            style={{
                                padding: '8px 14px', borderRadius: 10, whiteSpace: 'nowrap',
                                background: showAll ? 'var(--color-primary-500)' : 'var(--bg-tertiary)',
                                color: showAll ? 'white' : 'var(--text-secondary)',
                                border: 'none', cursor: 'pointer', fontSize: '0.8rem', fontWeight: 600,
                                transition: 'all 0.2s',
                            }}
                        >
                            {showAll ? 'Tüm İşaretler' : 'Sadece Notlar'}
                        </button>
                    </div>
                </header>

                <div className={styles.content}>
                    {isLoading ? (
                        <>
                            <SkeletonStyles />
                            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                                {Array.from({ length: 4 }).map((_, i) => (
                                    <SkeletonNoteCard key={i} />
                                ))}
                            </div>
                        </>
                    ) : error ? (
                        <div className={styles.error}>
                            <span>⚠️</span>
                            <p>{error}</p>
                        </div>
                    ) : filteredNotes.length === 0 ? (
                        <div className={styles.empty}>
                            <span className={styles.emptyIcon}>📝</span>
                            <h3>Henüz not yok</h3>
                            <p>PDF dosyalarınızda metin seçip not ekleyebilirsiniz.</p>
                            <button
                                className="btn btn-primary"
                                onClick={() => router.push('/library')}
                            >
                                Kütüphaneye Git
                            </button>
                        </div>
                    ) : (
                        <div className={styles.notesList}>
                            {Object.entries(groupedNotes).map(([fileId, { fileName, notes: fileNotes }]) => (
                                <div key={fileId} className={styles.fileGroup}>
                                    <h3 className={styles.fileGroupTitle}>
                                        <span>📄</span>
                                        {fileName}
                                        <span className={styles.noteCount}>({fileNotes.length} not)</span>
                                    </h3>
                                    <div className={styles.fileNotes}>
                                        {fileNotes.map(note => (
                                            <div
                                                key={note.id}
                                                className={styles.noteCard}
                                                onClick={() => handleNoteClick(note)}
                                                style={{ borderLeftColor: note.color }}
                                            >
                                                <div className={styles.noteHeader}>
                                                    <span className={styles.notePage}>Sayfa {note.pageNumber}</span>
                                                    <span className={styles.noteDate}>
                                                        {note.createdAt.toLocaleDateString('tr-TR')}
                                                    </span>
                                                </div>
                                                {note.text && (
                                                    <p className={styles.noteHighlight}>
                                                        &ldquo;{note.text.slice(0, 150)}{note.text.length > 150 ? '...' : ''}&rdquo;
                                                    </p>
                                                )}
                                                <p className={styles.noteText}>{note.note}</p>
                                            </div>
                                        ))}
                                    </div>
                                </div>
                            ))}
                        </div>
                    )}
                </div>
            </main>
        </div>
    );
}
