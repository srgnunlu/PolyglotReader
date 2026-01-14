'use client';

import { ProtectedRoute } from '@/components/auth/ProtectedRoute';
import { useAuth } from '@/hooks/useAuth';
import { useDocuments } from '@/hooks/useDocuments';
import dynamic from 'next/dynamic';
const PDFThumbnail = dynamic(() => import('@/components/library/PDFThumbnail').then(mod => mod.PDFThumbnail), {
    ssr: false,
    loading: () => <div className="card-placeholder">📄</div>
});
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import styles from './library.module.css';

export default function LibraryPage() {
    return (
        <ProtectedRoute>
            <LibraryContent />
        </ProtectedRoute>
    );
}

function LibraryContent() {
    const router = useRouter();
    const { user, signOut } = useAuth();
    const {
        documents,
        folders,
        isLoading,
        error,
        selectedFolder,
        searchQuery,
        setSelectedFolder,
        setSearchQuery,
    } = useDocuments();

    const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid');

    const handleDocumentClick = (id: string) => {
        router.push(`/reader/${id}`);
    };

    const handleLogout = async () => {
        await signOut();
        router.push('/login');
    };

    const formatFileSize = (bytes: number) => {
        if (bytes < 1024) return `${bytes} B`;
        if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
        return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    };

    const formatDate = (date: Date) => {
        return date.toLocaleDateString('tr-TR', {
            day: 'numeric',
            month: 'short',
            year: 'numeric',
        });
    };

    return (
        <div className={styles.layout}>
            {/* Sidebar */}
            <aside className={styles.sidebar}>
                <div className={styles.sidebarHeader}>
                    <div className={styles.logo}>
                        <span className={styles.logoIcon}>📄</span>
                        <span className={styles.logoText}>Corio Docs</span>
                    </div>
                </div>

                <nav className={styles.sidebarNav}>
                    <button
                        className={`${styles.navItem} ${!selectedFolder ? styles.navItemActive : ''}`}
                        onClick={() => setSelectedFolder(null)}
                    >
                        <span className={styles.navIcon}>📁</span>
                        <span>Tüm Dosyalar</span>
                        <span className={styles.navBadge}>{documents.length}</span>
                    </button>

                    <button
                        className={styles.navItem}
                        onClick={() => router.push('/notes')}
                    >
                        <span className={styles.navIcon}>📝</span>
                        <span>Notlarım</span>
                    </button>

                    <div className={styles.navSection}>
                        <h3 className={styles.navSectionTitle}>Klasörler</h3>
                        {folders.map(folder => (
                            <button
                                key={folder.id}
                                className={`${styles.navItem} ${selectedFolder === folder.id ? styles.navItemActive : ''}`}
                                onClick={() => setSelectedFolder(folder.id)}
                            >
                                <span
                                    className={styles.navIcon}
                                    style={{ color: folder.color }}
                                >
                                    📁
                                </span>
                                <span>{folder.name}</span>
                            </button>
                        ))}
                    </div>
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
                    <button className={styles.logoutBtn} onClick={handleLogout}>
                        Çıkış
                    </button>
                </div>
            </aside>

            {/* Main Content */}
            <main className={styles.main}>
                {/* Header */}
                <header className={styles.header}>
                    <div className={styles.searchContainer}>
                        <input
                            type="text"
                            className={styles.searchInput}
                            placeholder="Dosya ara..."
                            value={searchQuery}
                            onChange={(e) => setSearchQuery(e.target.value)}
                        />
                        <span className={styles.searchIcon}>🔍</span>
                    </div>

                    <div className={styles.headerActions}>
                        <button
                            className={`${styles.viewToggle} ${viewMode === 'grid' ? styles.viewToggleActive : ''}`}
                            onClick={() => setViewMode('grid')}
                            title="Grid görünümü"
                        >
                            ▦
                        </button>
                        <button
                            className={`${styles.viewToggle} ${viewMode === 'list' ? styles.viewToggleActive : ''}`}
                            onClick={() => setViewMode('list')}
                            title="Liste görünümü"
                        >
                            ☰
                        </button>
                    </div>
                </header>

                {/* Content */}
                <div className={styles.content}>
                    {isLoading ? (
                        <div className={styles.loading}>
                            <div className="spinner" style={{ width: 40, height: 40 }} />
                            <p>Dosyalar yükleniyor...</p>
                        </div>
                    ) : error ? (
                        <div className={styles.error}>
                            <span>⚠️</span>
                            <p>{error}</p>
                        </div>
                    ) : documents.length === 0 ? (
                        <div className={styles.empty}>
                            <span className={styles.emptyIcon}>📭</span>
                            <h3>Henüz dosya yok</h3>
                            <p>iOS uygulamasından PDF yükleyerek başlayın</p>
                        </div>
                    ) : (
                        <div className={viewMode === 'grid' ? styles.grid : styles.list}>
                            {documents.map(doc => (
                                <div
                                    key={doc.id}
                                    className={viewMode === 'grid' ? styles.cardGrid : styles.cardList}
                                    onClick={() => handleDocumentClick(doc.id)}
                                >
                                    <div className={styles.cardThumbnail}>
                                        {doc.thumbnailData ? (
                                            <img
                                                src={`data:image/png;base64,${doc.thumbnailData}`}
                                                alt={doc.name}
                                            />
                                        ) : (
                                            <PDFThumbnail storagePath={doc.storagePath} alt={doc.name} />
                                        )}
                                    </div>
                                    <div className={styles.cardInfo}>
                                        <h4 className={styles.cardTitle}>{doc.name}</h4>
                                        <div className={styles.cardMeta}>
                                            <span>{formatFileSize(doc.size)}</span>
                                            <span>•</span>
                                            <span>{formatDate(doc.uploadedAt)}</span>
                                        </div>
                                        {doc.summary && viewMode === 'list' && (
                                            <p className={styles.cardSummary}>{doc.summary}</p>
                                        )}
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
