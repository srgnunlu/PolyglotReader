// Library page — main document browser, wrapped by AppShell which handles sidebar/nav
'use client';

import { ProtectedRoute } from '@/components/auth/ProtectedRoute';
import { useDocuments } from '@/hooks/useDocuments';
import { Skeleton } from '@/components/ui/skeleton';
import { PDFGrid } from '@/components/library/PDFGrid';
import { PDFList } from '@/components/library/PDFList';
import { EmptyLibrary } from '@/components/library/EmptyLibrary';
import { UploadArea } from '@/components/library/UploadArea';
import { useFileUpload } from '@/hooks/useFileUpload';
import { useLibraryStore } from '@/stores/useLibraryStore';
import { LayoutGrid, List, Search, AlertCircle, Upload, Loader2 } from 'lucide-react';
import { useState, useEffect, useRef, useCallback } from 'react';
import { toast } from 'sonner';

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
    refresh,
  } = useDocuments();

  const { uploadFiles, isUploading } = useFileUpload();
  // Persisted view preference (survives reloads via localStorage)
  const { viewMode, setViewMode } = useLibraryStore();
  const [showUpload, setShowUpload] = useState(false);
  const [localSearch, setLocalSearch] = useState(searchQuery);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const handleFilesSelected = useCallback(
    async (files: File[]) => {
      setShowUpload(false);
      const uploadToast = toast.loading(
        files.length === 1
          ? `"${files[0].name}" yükleniyor...`
          : `${files.length} dosya yükleniyor...`
      );

      const result = await uploadFiles(files);
      toast.dismiss(uploadToast);

      if (result.succeeded.length > 0) {
        toast.success(
          result.succeeded.length === 1
            ? `"${result.succeeded[0]}" yüklendi`
            : `${result.succeeded.length} dosya yüklendi`
        );
        await refresh();
      }
      for (const failure of result.failed) {
        toast.error(`"${failure.name}" yüklenemedi: ${failure.error}`);
      }
    },
    [uploadFiles, refresh]
  );

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
    <div className="min-h-screen bg-corio-bg">
      {/* Page header */}
      <div className="sticky top-0 z-10 px-4 sm:px-6 py-4 flex flex-col sm:flex-row sm:items-center gap-3 bg-corio-bg/90 backdrop-blur-xl border-b border-corio-border-subtle">
        {/* Title */}
        <h1 className="text-xl font-semibold shrink-0 text-corio-fg">
          Kütüphane
        </h1>

        {/* Search */}
        <div className="relative flex-1 sm:max-w-md">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 pointer-events-none text-corio-fg/40" />
          <input
            type="text"
            placeholder="Belge ara..."
            value={localSearch}
            onChange={e => handleSearchChange(e.target.value)}
            aria-label="Belge ara"
            className="w-full pl-9 pr-4 py-2 rounded-xl text-sm outline-none transition-all bg-corio-surface-2 border border-corio-border text-corio-fg placeholder:text-corio-fg/40 focus:border-corio-accent focus:ring-2 focus:ring-corio-accent/20"
          />
        </div>

        {/* Controls */}
        <div className="flex items-center gap-2 shrink-0">
          {/* Upload button */}
          <button
            onClick={() => setShowUpload(prev => !prev)}
            disabled={isUploading}
            className="flex items-center gap-1.5 px-3 h-9 rounded-xl text-sm font-medium transition-all disabled:opacity-60 bg-corio-accent text-white hover:bg-corio-accent-hover focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-corio-accent/40"
          >
            {isUploading
              ? <Loader2 className="w-4 h-4 animate-spin" />
              : <Upload className="w-4 h-4" />}
            PDF Yükle
          </button>

          {/* View toggle */}
          <div className="flex items-center rounded-xl p-1 gap-0.5 bg-corio-surface-2">
            <button
              onClick={() => setViewMode('grid')}
              className={`flex items-center justify-center w-8 h-7 rounded-lg transition-all ${
                viewMode === 'grid'
                  ? 'bg-corio-bg text-corio-accent shadow-sm'
                  : 'text-corio-fg/50 hover:text-corio-fg/80'
              }`}
              title="Grid görünümü"
              aria-label="Grid görünümü"
              aria-pressed={viewMode === 'grid'}
            >
              <LayoutGrid className="w-4 h-4" />
            </button>
            <button
              onClick={() => setViewMode('list')}
              className={`flex items-center justify-center w-8 h-7 rounded-lg transition-all ${
                viewMode === 'list'
                  ? 'bg-corio-bg text-corio-accent shadow-sm'
                  : 'text-corio-fg/50 hover:text-corio-fg/80'
              }`}
              title="Liste görünümü"
              aria-label="Liste görünümü"
              aria-pressed={viewMode === 'list'}
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
          <div className="flex flex-col items-center gap-3 py-16 text-center">
            <div className="flex items-center justify-center w-14 h-14 rounded-2xl bg-corio-destructive/10">
              <AlertCircle className="w-7 h-7 text-corio-destructive" />
            </div>
            <p className="text-sm font-medium text-corio-fg">
              Belgeler yüklenirken hata oluştu
            </p>
            <p className="text-xs max-w-xs text-corio-fg/50">
              {error}
            </p>
          </div>
        )}

        {/* Empty state */}
        {!isLoading && !error && documents.length === 0 && !showUpload && (
          <EmptyLibrary onUploadClick={() => setShowUpload(true)} />
        )}

        {/* Upload area — toggled from the header button or the empty state */}
        {showUpload && (
          <div className="mb-6">
            <UploadArea onFilesSelected={handleFilesSelected} />
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
