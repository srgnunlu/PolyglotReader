// Library page — main document browser, wrapped by AppShell which handles sidebar/nav
'use client';

import { ProtectedRoute } from '@/components/auth/ProtectedRoute';
import { useDocuments } from '@/hooks/useDocuments';
import { Skeleton } from '@/components/ui/skeleton';
import { PDFGrid } from '@/components/library/PDFGrid';
import { PDFList } from '@/components/library/PDFList';
import { EmptyLibrary } from '@/components/library/EmptyLibrary';
import { UploadArea } from '@/components/library/UploadArea';
import { LayoutGrid, List, Search, AlertCircle } from 'lucide-react';
import { useState, useEffect, useRef, useCallback } from 'react';

export default function LibraryPage() {
  return (
    <ProtectedRoute>
      <LibraryContent />
    </ProtectedRoute>
  );
}

function LibraryContent() {
  const {
    documents,
    isLoading,
    error,
    searchQuery,
    setSearchQuery,
  } = useDocuments();

  const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid');
  const [showUpload, setShowUpload] = useState(false);
  const [localSearch, setLocalSearch] = useState(searchQuery);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // 300ms debounce before updating the hook's search query (triggers API call)
  const handleSearchChange = useCallback(
    (value: string) => {
      setLocalSearch(value);
      if (debounceRef.current) clearTimeout(debounceRef.current);
      debounceRef.current = setTimeout(() => {
        setSearchQuery(value);
      }, 300);
    },
    [setSearchQuery]
  );

  // Cleanup on unmount
  useEffect(() => {
    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
  }, []);

  return (
    <div
      className="min-h-screen"
      style={{ background: '#FDFAF6' }}
    >
      {/* Page header */}
      <div
        className="sticky top-0 z-10 px-4 sm:px-6 py-4 flex flex-col sm:flex-row sm:items-center gap-3"
        style={{
          background: 'rgba(253, 250, 246, 0.9)',
          backdropFilter: 'blur(12px)',
          borderBottom: '1px solid rgba(42, 37, 32, 0.06)',
        }}
      >
        {/* Title */}
        <h1
          className="text-xl font-semibold shrink-0"
          style={{ color: '#2A2520' }}
        >
          Kütüphane
        </h1>

        {/* Search */}
        <div className="relative flex-1 sm:max-w-md">
          <Search
            className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 pointer-events-none"
            style={{ color: 'rgba(42, 37, 32, 0.4)' }}
          />
          <input
            type="text"
            placeholder="Belge ara..."
            value={localSearch}
            onChange={e => handleSearchChange(e.target.value)}
            className="w-full pl-9 pr-4 py-2 rounded-xl text-sm outline-none transition-all"
            style={{
              background: 'rgba(255, 255, 255, 0.7)',
              border: '1px solid rgba(42, 37, 32, 0.1)',
              color: '#2A2520',
            }}
          />
        </div>

        {/* Controls */}
        <div className="flex items-center gap-2 shrink-0">
          {/* View toggle */}
          <div
            className="flex items-center rounded-xl p-1 gap-0.5"
            style={{
              background: 'rgba(42, 37, 32, 0.06)',
            }}
          >
            <button
              onClick={() => setViewMode('grid')}
              className="flex items-center justify-center w-8 h-7 rounded-lg transition-all"
              title="Grid görünümü"
              style={{
                background: viewMode === 'grid' ? 'rgba(255,255,255,0.9)' : 'transparent',
                color: viewMode === 'grid' ? '#D4713C' : 'rgba(42, 37, 32, 0.5)',
                boxShadow: viewMode === 'grid' ? '0 1px 3px rgba(42,37,32,0.1)' : 'none',
              }}
            >
              <LayoutGrid className="w-4 h-4" />
            </button>
            <button
              onClick={() => setViewMode('list')}
              className="flex items-center justify-center w-8 h-7 rounded-lg transition-all"
              title="Liste görünümü"
              style={{
                background: viewMode === 'list' ? 'rgba(255,255,255,0.9)' : 'transparent',
                color: viewMode === 'list' ? '#D4713C' : 'rgba(42, 37, 32, 0.5)',
                boxShadow: viewMode === 'list' ? '0 1px 3px rgba(42,37,32,0.1)' : 'none',
              }}
            >
              <List className="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>

      {/* Main content */}
      <div className="px-4 sm:px-6 py-6">
        {/* Loading skeleton */}
        {isLoading && (
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4">
            {Array.from({ length: 10 }).map((_, i) => (
              <div key={i} className="rounded-xl overflow-hidden">
                <Skeleton className="w-full" style={{ aspectRatio: '3 / 4' }} />
                <div className="p-3 space-y-2">
                  <Skeleton className="h-4 w-full" />
                  <Skeleton className="h-3 w-2/3" />
                </div>
              </div>
            ))}
          </div>
        )}

        {/* Error state */}
        {!isLoading && error && (
          <div
            className="flex flex-col items-center gap-3 py-16 text-center"
          >
            <div
              className="flex items-center justify-center w-14 h-14 rounded-2xl"
              style={{ background: 'rgba(220, 38, 38, 0.08)' }}
            >
              <AlertCircle className="w-7 h-7" style={{ color: '#DC2626' }} />
            </div>
            <p className="text-sm font-medium" style={{ color: '#2A2520' }}>
              Belgeler yüklenirken hata oluştu
            </p>
            <p className="text-xs max-w-xs" style={{ color: 'rgba(42, 37, 32, 0.5)' }}>
              {error}
            </p>
          </div>
        )}

        {/* Empty state */}
        {!isLoading && !error && documents.length === 0 && !showUpload && (
          <EmptyLibrary onUploadClick={() => setShowUpload(true)} />
        )}

        {/* Upload area — shown after clicking "PDF Yükle" in empty state */}
        {showUpload && (
          <div className="mb-6">
            <UploadArea
              onFilesSelected={files => {
                // TODO: wire to Supabase upload logic
                console.info('Selected files for upload:', files.map(f => f.name));
                setShowUpload(false);
              }}
            />
          </div>
        )}

        {/* Document list */}
        {!isLoading && !error && documents.length > 0 && (
          viewMode === 'grid'
            ? <PDFGrid documents={documents} />
            : <PDFList documents={documents} />
        )}
      </div>
    </div>
  );
}
