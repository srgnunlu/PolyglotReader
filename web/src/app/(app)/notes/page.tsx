// Notes page — displays all annotations grouped by PDF file, with search and color filtering
'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { ProtectedRoute } from '@/components/auth/ProtectedRoute';
import { getSupabase } from '@/lib/supabase';
import { useAuth } from '@/hooks/useAuth';
import { AnnotationCard } from '@/components/notebook/AnnotationCard';
import { NotebookFilters } from '@/components/notebook/NotebookFilters';
import { Skeleton } from '@/components/ui/skeleton';
import { Notebook, AlertCircle, Library } from 'lucide-react';

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
  const { user } = useAuth();

  const [notes, setNotes] = useState<Note[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [activeColor, setActiveColor] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Fetch annotations from Supabase
  useEffect(() => {
    const fetchNotes = async () => {
      setIsLoading(true);
      setError(null);

      try {
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

        // Show ALL annotations (not just ones with notes)
        const mappedNotes: Note[] = (data || [])
          .filter((item: Record<string, unknown>) => {
            const itemData = item.data as { text?: string; note?: string } | undefined;
            // Include annotation if it has highlighted text OR a user note
            return itemData?.text || itemData?.note;
          })
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
        setError('Notlar yüklenemedi. Lütfen tekrar deneyin.');
      } finally {
        setIsLoading(false);
      }
    };

    fetchNotes();
  }, [supabase]);

  // Filter notes by search query and color
  const filteredNotes = notes.filter((note) => {
    const matchesSearch =
      note.text.toLowerCase().includes(searchQuery.toLowerCase()) ||
      note.note.toLowerCase().includes(searchQuery.toLowerCase()) ||
      note.fileName.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesColor = activeColor === null || note.color === activeColor;
    return matchesSearch && matchesColor;
  });

  // Group notes by file
  const groupedNotes = filteredNotes.reduce(
    (acc, note) => {
      if (!acc[note.fileId]) {
        acc[note.fileId] = { fileName: note.fileName, notes: [] };
      }
      acc[note.fileId].notes.push(note);
      return acc;
    },
    {} as Record<string, { fileName: string; notes: Note[] }>
  );

  const handleNoteClick = (note: Note) => {
    router.push(`/reader/${note.fileId}?page=${note.pageNumber}`);
  };

  return (
    <div className="min-h-screen bg-corio-bg">
      {/* Page header */}
      <div className="sticky top-0 z-10 px-4 sm:px-6 py-4 bg-corio-bg/90 backdrop-blur-xl border-b border-corio-border-subtle">
        <div className="flex flex-col gap-3">
          <h1 className="text-xl font-semibold text-corio-fg">Notlarim</h1>
          <NotebookFilters
            searchQuery={searchQuery}
            onSearchChange={setSearchQuery}
            activeColor={activeColor}
            onColorFilter={setActiveColor}
          />
        </div>
      </div>

      {/* Content */}
      <div className="px-4 sm:px-6 py-6 max-w-3xl mx-auto">
        {/* Loading state */}
        {isLoading && (
          <div className="space-y-4">
            {Array.from({ length: 4 }).map((_, i) => (
              <div key={i} className="space-y-2">
                <Skeleton className="h-5 w-40" />
                <Skeleton className="h-24 w-full rounded-xl" />
                <Skeleton className="h-24 w-full rounded-xl" />
              </div>
            ))}
          </div>
        )}

        {/* Error state */}
        {!isLoading && error && (
          <div className="flex flex-col items-center gap-3 py-16 text-center">
            <div className="flex items-center justify-center size-14 rounded-2xl bg-red-500/10">
              <AlertCircle className="size-7 text-red-500" />
            </div>
            <p className="text-sm font-medium text-corio-fg">{error}</p>
          </div>
        )}

        {/* Empty state */}
        {!isLoading && !error && filteredNotes.length === 0 && (
          <div className="flex flex-col items-center gap-4 py-20 text-center">
            <div className="flex items-center justify-center size-16 rounded-2xl bg-corio-surface-2">
              <Notebook className="size-8 text-corio-fg/30" />
            </div>
            <div className="space-y-1">
              <h3 className="text-base font-medium text-corio-fg">
                Henuz not yok
              </h3>
              <p className="text-sm text-corio-fg/50 max-w-xs">
                PDF dosyalarinizda metin secip isaretleme yapabilir ve not ekleyebilirsiniz.
              </p>
            </div>
            <button
              onClick={() => router.push('/library')}
              className="flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-medium bg-corio-accent text-white hover:bg-corio-accent-hover transition-colors"
            >
              <Library className="size-4" />
              Kutuphaneye Git
            </button>
          </div>
        )}

        {/* Grouped annotations */}
        {!isLoading && !error && filteredNotes.length > 0 && (
          <div className="space-y-6">
            {Object.entries(groupedNotes).map(([fileId, { fileName, notes: fileNotes }]) => (
              <div key={fileId} className="space-y-3">
                <div className="flex items-center gap-2">
                  <h3 className="text-sm font-semibold text-corio-fg truncate">
                    {fileName}
                  </h3>
                  <span className="text-xs text-corio-fg/40 shrink-0">
                    ({fileNotes.length} not)
                  </span>
                </div>
                <div className="space-y-2">
                  {fileNotes.map((note) => (
                    <AnnotationCard
                      key={note.id}
                      id={note.id}
                      fileName={note.fileName}
                      fileId={note.fileId}
                      pageNumber={note.pageNumber}
                      text={note.text}
                      note={note.note}
                      color={note.color}
                      createdAt={note.createdAt}
                      onClick={() => handleNoteClick(note)}
                    />
                  ))}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
