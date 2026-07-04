// In-document search side panel — full-text search across all pages with
// snippet results that jump to the matching page.
'use client';

import { useState, useCallback, useEffect, useRef } from 'react';
import type { pdfjs } from 'react-pdf';
import { Search, Loader2, X } from 'lucide-react';
import { searchDocument, SearchMatch } from '@/lib/pdfSearch';

interface DocumentSearchPanelProps {
  pdf: pdfjs.PDFDocumentProxy | null;
  onNavigate: (page: number) => void;
  onClose: () => void;
}

export function DocumentSearchPanel({ pdf, onNavigate, onClose }: DocumentSearchPanelProps) {
  const [query, setQuery] = useState('');
  const [matches, setMatches] = useState<SearchMatch[]>([]);
  const [isSearching, setIsSearching] = useState(false);
  const [capped, setCapped] = useState(false);
  const [searched, setSearched] = useState(false);
  const [progress, setProgress] = useState<{ scanned: number; total: number } | null>(null);
  const abortRef = useRef<AbortController | null>(null);

  // Cancel an in-flight search when the panel closes/unmounts.
  useEffect(() => () => abortRef.current?.abort(), []);

  const runSearch = useCallback(async () => {
    if (!pdf || query.trim().length < 2) return;

    // A new search supersedes any in-flight one.
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;

    setIsSearching(true);
    setSearched(true);
    setMatches([]);
    setCapped(false);
    setProgress(null);
    try {
      const result = await searchDocument(pdf, query, {
        signal: controller.signal,
        onProgress: ({ pagesScanned, totalPages, matches: partial }) => {
          setProgress({ scanned: pagesScanned, total: totalPages });
          setMatches(partial);
        },
      });
      setMatches(result.matches);
      setCapped(result.capped);
    } catch (err) {
      // A superseded search must not clobber the newer search's state.
      if (err instanceof DOMException && err.name === 'AbortError') return;
      setMatches([]);
      setCapped(false);
    } finally {
      if (abortRef.current === controller) {
        setIsSearching(false);
        setProgress(null);
      }
    }
  }, [pdf, query]);

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      runSearch();
    }
  };

  return (
    <div className="flex h-full w-72 shrink-0 flex-col border-r border-corio-border bg-corio-surface-1">
      <div className="flex items-center justify-between border-b border-corio-border px-3 py-2.5">
        <div className="flex items-center gap-2 text-sm font-medium text-corio-fg">
          <Search className="size-4 text-corio-accent" />
          Belgede Ara
        </div>
        <button
          onClick={onClose}
          className="rounded-lg p-1 text-corio-fg/50 transition-colors hover:bg-corio-surface-2 hover:text-corio-fg"
          aria-label="Aramayı kapat"
        >
          <X className="size-4" />
        </button>
      </div>

      <div className="border-b border-corio-border p-2">
        <div className="relative">
          <Search className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-corio-fg/40" />
          <input
            type="text"
            autoFocus
            value={query}
            onChange={e => setQuery(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Aranacak kelime..."
            className="w-full rounded-lg border border-corio-border bg-corio-bg py-2 pl-8 pr-2 text-sm text-corio-fg outline-none transition-all placeholder:text-corio-fg/40 focus:border-corio-accent focus:ring-2 focus:ring-corio-accent/20"
          />
        </div>
      </div>

      <div className="flex-1 overflow-y-auto p-2">
        {isSearching && (
          <div className="flex items-center justify-center gap-2 py-2 text-sm text-corio-fg/50">
            <Loader2 className="size-4 animate-spin" />
            Aranıyor...
            {progress && ` (${progress.scanned}/${progress.total} sayfa)`}
          </div>
        )}
        {!searched ? (
          <div className="px-3 py-10 text-center text-sm text-corio-fg/50">
            Belge içinde arama yapmak için bir kelime yazıp Enter&apos;a basın.
          </div>
        ) : matches.length === 0 ? (
          !isSearching && (
            <div className="px-3 py-10 text-center text-sm text-corio-fg/50">
              Sonuç bulunamadı.
            </div>
          )
        ) : (
          <>
            <div className="px-2 pb-2 text-xs text-corio-fg/50">
              {matches.length}{capped ? '+' : ''} sonuç
              {capped && ' (ilk 200 gösteriliyor)'}
            </div>
            <ul className="space-y-1">
              {matches.map((match, idx) => (
                <li key={`${match.pageNumber}-${match.matchIndex}-${idx}`}>
                  <button
                    onClick={() => onNavigate(match.pageNumber)}
                    className="w-full rounded-lg px-2.5 py-2 text-left transition-colors hover:bg-corio-surface-2"
                  >
                    <div className="mb-0.5 text-xs font-medium text-corio-accent">
                      Sayfa {match.pageNumber}
                    </div>
                    <div className="line-clamp-2 text-xs leading-relaxed text-corio-fg/70">
                      {match.snippet}
                    </div>
                  </button>
                </li>
              ))}
            </ul>
          </>
        )}
      </div>
    </div>
  );
}
