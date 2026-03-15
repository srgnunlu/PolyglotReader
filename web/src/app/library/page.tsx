'use client';

import { ProtectedRoute } from '@/components/auth/ProtectedRoute';
import { useAuth } from '@/hooks/useAuth';
import { useDocuments } from '@/hooks/useDocuments';
import dynamic from 'next/dynamic';
const PDFThumbnail = dynamic(() => import('@/components/library/PDFThumbnail').then(mod => mod.PDFThumbnail), {
    ssr: false,
    loading: () => <div className="card-placeholder">📄</div>
});
import { useState, useMemo, useCallback } from 'react';
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
        hasMore,
        loadMore,
        setSelectedFolder,
        setSearchQuery,
    } = useDocuments();

    const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid');
    const [sidebarOpen, setSidebarOpen] = useState(false);

    const handleDocumentClick = useCallback((id: string) => {
        router.push(`/reader/${id}`);
    }, [router]);

    const handleLogout = useCallback(async () => {
        await signOut();
        router.push('/login');
    }, [signOut, router]);

    const formatFileSize = useCallback((bytes: number) => {
        if (bytes < 1024) return `${bytes} B`;
        if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
        return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
    }, []);

    const formatDate = useCallback((date: Date) => {
        return date.toLocaleDateString('tr-TR', {
            day: 'numeric',
            month: 'short',
            year: 'numeric',
        });
    }, []);

    const handleFolderSelect = useCallback((id: string | null) => {
        setSelectedFolder(id);
        setSidebarOpen(false);
    }, [setSelectedFolder]);

    const documentCards = useMemo(() => {
        return documents.map(doc => ({
            ...doc,
            formattedSize: formatFileSize(doc.size),
            formattedDate: formatDate(doc.uploadedAt),
        }));
    }, [documents, formatFileSize, formatDate]);

    return (
        <div className={styles.layout}>
            {/* Animated Background */}
            <div className={styles.backgroundOrbs}>
                <div className={`${styles.orb} ${styles.orb1}`} />
                <div className={`${styles.orb} ${styles.orb2}`} />
            </div>

            {/* Mobile Sidebar Overlay */}
            {sidebarOpen && (
                <div
                    className={styles.sidebarOverlay}
                    onClick={() => setSidebarOpen(false)}
                />
            )}

            {/* Sidebar */}
            <aside className={`${styles.sidebar} ${sidebarOpen ? styles.sidebarOpen : ''}`}>
                <div className={styles.sidebarHeader}>
                    <div className={styles.logo}>
                        <span className={styles.logoIcon}>📄</span>
                        <span className={styles.logoText}>Corio Docs</span>
                    </div>
                </div>

                <nav className={styles.sidebarNav}>
                    <button
                        className={`${styles.navItem} ${!selectedFolder ? styles.navItemActive : ''}`}
                        onClick={() => handleFolderSelect(null)}
                    >
                        <span className={styles.navIcon}>📁</span>
                        <span>Tüm Dosyalar</span>
                        <span className={styles.navBadge}>{documents.length}</span>
                    </button>

                    <button
                        className={styles.navItem}
                        onClick={() => { router.push('/notes'); setSidebarOpen(false); }}
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
                                onClick={() => handleFolderSelect(folder.id)}
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
                    {/* Mobile hamburger button */}
                    <button
                        className={styles.mobileMenuBtn}
                        onClick={() => setSidebarOpen(true)}
                        aria-label="Menüyü aç"
                    >
                        <span className={styles.hamburgerLine} />
                        <span className={styles.hamburgerLine} />
                        <span className={styles.hamburgerLine} />
                    </button>

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
                        <>
                        <div className={viewMode === 'grid' ? styles.grid : styles.list}>
                            {documentCards.map(doc => (
                                <div
                                    key={doc.id}
                                    className={viewMode === 'grid' ? styles.cardGrid : styles.cardList}
                                    onClick={() => handleDocumentClick(doc.id)}
                                >
                                    <div className={styles.cardThumbnail}>
                                        <PDFThumbnail
                                            storagePath={doc.storagePath}
                                            alt={doc.name}
                                            base64Data={doc.thumbnailData}
                                        />
                                    </div>
                                    <div className={styles.cardInfo}>
                                        <h4 className={styles.cardTitle}>{doc.name}</h4>
                                        <div className={styles.cardMeta}>
                                            <span>{doc.formattedSize}</span>
                                            <span>•</span>
                                            <span>{doc.formattedDate}</span>
                                        </div>
                                        {doc.summary && viewMode === 'list' && (
                                            <p className={styles.cardSummary}>{doc.summary}</p>
                                        )}
                                    </div>
                                </div>
                            ))}
                        </div>
                        {hasMore && (
                            <div className={styles.loadMoreContainer}>
                                <button
                                    className={styles.loadMoreBtn}
                                    onClick={loadMore}
                                    disabled={isLoading}
                                >
                                    {isLoading ? 'Yükleniyor...' : 'Daha Fazla Yükle'}
                                </button>
                            </div>
                        )}
                        </>
                    )}
                </div>
            </main>
        </div>
    );
}
