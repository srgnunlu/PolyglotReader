// Document outline (TOC) side panel — lists the PDF's embedded bookmarks and
// jumps to a section's page on click.
'use client';

import { useEffect, useState } from 'react';
import type { pdfjs } from 'react-pdf';
import { Loader2, ListTree, X } from 'lucide-react';
import { extractOutline, OutlineItem } from '@/lib/pdfOutline';

interface DocumentOutlineProps {
  pdf: pdfjs.PDFDocumentProxy | null;
  currentPage: number;
  onNavigate: (page: number) => void;
  onClose: () => void;
}

export function DocumentOutline({ pdf, currentPage, onNavigate, onClose }: DocumentOutlineProps) {
  const [items, setItems] = useState<OutlineItem[]>([]);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    if (!pdf) return;
    let cancelled = false;
    const load = async () => {
      setIsLoading(true);
      try {
        const result = await extractOutline(pdf);
        if (!cancelled) setItems(result);
      } catch {
        if (!cancelled) setItems([]);
      } finally {
        if (!cancelled) setIsLoading(false);
      }
    };
    load();
    return () => {
      cancelled = true;
    };
  }, [pdf]);

  return (
    <div className="flex h-full w-72 shrink-0 flex-col border-r border-corio-border bg-corio-surface-1">
      <div className="flex items-center justify-between border-b border-corio-border px-3 py-2.5">
        <div className="flex items-center gap-2 text-sm font-medium text-corio-fg">
          <ListTree className="size-4 text-corio-accent" />
          İçindekiler
        </div>
        <button
          onClick={onClose}
          className="rounded-lg p-1 text-corio-fg/50 transition-colors hover:bg-corio-surface-2 hover:text-corio-fg"
          aria-label="İçindekileri kapat"
        >
          <X className="size-4" />
        </button>
      </div>

      <div className="flex-1 overflow-y-auto p-2">
        {isLoading ? (
          <div className="flex items-center justify-center gap-2 py-10 text-sm text-corio-fg/50">
            <Loader2 className="size-4 animate-spin" />
            Yükleniyor...
          </div>
        ) : items.length === 0 ? (
          <div className="px-3 py-10 text-center text-sm text-corio-fg/50">
            Bu dokümanda içindekiler tablosu bulunmuyor.
          </div>
        ) : (
          <ul className="space-y-0.5">
            {items.map((item, idx) => {
              const isActive = item.pageNumber === currentPage;
              return (
                <li key={`${item.title}-${idx}`}>
                  <button
                    onClick={() => item.pageNumber && onNavigate(item.pageNumber)}
                    disabled={item.pageNumber === null}
                    style={{ paddingLeft: `${item.level * 12 + 8}px` }}
                    className={`flex w-full items-baseline justify-between gap-2 rounded-lg py-1.5 pr-2 text-left text-sm transition-colors disabled:cursor-default disabled:opacity-50 ${
                      isActive
                        ? 'bg-corio-accent-subtle text-corio-accent'
                        : 'text-corio-fg/80 hover:bg-corio-surface-2'
                    }`}
                  >
                    <span className="truncate">{item.title}</span>
                    {item.pageNumber !== null && (
                      <span className="shrink-0 text-xs text-corio-fg/40">{item.pageNumber}</span>
                    )}
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </div>
  );
}
