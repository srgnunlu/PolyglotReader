// Citation dialog — extracts the document's bibliographic metadata (DOI →
// Crossref, with an AI fallback) and offers BibTeX / RIS copy & download.
'use client';

import { useEffect, useState } from 'react';
import type { pdfjs } from 'react-pdf';
import { toast } from 'sonner';
import { Loader2, Copy, Download, Quote, Sparkles, AlertCircle } from 'lucide-react';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  resolveCitation,
  toBibtex,
  toRis,
  CitationMetadata,
  CitationSource,
} from '@/lib/citation';
import { downloadTextFile } from '@/lib/highlightExport';

interface CitationDialogProps {
  pdf: pdfjs.PDFDocumentProxy | null;
  documentName: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

type Format = 'bibtex' | 'ris';

export function CitationDialog({ pdf, documentName, open, onOpenChange }: CitationDialogProps) {
  const [isLoading, setIsLoading] = useState(false);
  const [metadata, setMetadata] = useState<CitationMetadata | null>(null);
  const [source, setSource] = useState<CitationSource | null>(null);
  const [failed, setFailed] = useState(false);
  const [format, setFormat] = useState<Format>('bibtex');

  useEffect(() => {
    if (!open || !pdf) return;
    let cancelled = false;
    const load = async () => {
      setIsLoading(true);
      setMetadata(null);
      setSource(null);
      setFailed(false);
      try {
        const result = await resolveCitation(pdf);
        if (cancelled) return;
        if (result) {
          setMetadata(result.metadata);
          setSource(result.source);
        } else {
          setFailed(true);
        }
      } catch {
        if (!cancelled) setFailed(true);
      } finally {
        if (!cancelled) setIsLoading(false);
      }
    };
    load();
    return () => {
      cancelled = true;
    };
  }, [open, pdf]);

  const content = metadata ? (format === 'bibtex' ? toBibtex(metadata) : toRis(metadata)) : '';

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(content);
      toast.success('Panoya kopyalandı');
    } catch {
      toast.error('Kopyalanamadı');
    }
  };

  const handleDownload = () => {
    const safeName = documentName.replace(/\.[^.]+$/, '').replace(/[^\w.-]+/g, '_') || 'atif';
    if (format === 'bibtex') {
      downloadTextFile(`${safeName}.bib`, content, 'application/x-bibtex');
    } else {
      downloadTextFile(`${safeName}.ris`, content, 'application/x-research-info-systems');
    }
    toast.success('İndirildi');
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Quote className="size-5 text-corio-accent" />
            Atıf Çıkar
          </DialogTitle>
          <DialogDescription>
            Doküman künyesi çıkarılıp BibTeX / RIS olarak dışa aktarılır.
          </DialogDescription>
        </DialogHeader>

        {isLoading ? (
          <div className="flex flex-col items-center gap-3 py-10 text-sm text-corio-fg/60">
            <Loader2 className="size-6 animate-spin text-corio-accent" />
            Künye çıkarılıyor...
          </div>
        ) : failed ? (
          <div className="flex flex-col items-center gap-3 py-10 text-center">
            <div className="flex size-12 items-center justify-center rounded-2xl bg-corio-destructive/10">
              <AlertCircle className="size-6 text-corio-destructive" />
            </div>
            <p className="text-sm text-corio-fg/70">
              Bu dokümandan künye çıkarılamadı. DOI bulunamadı ve metinden de
              yeterli bilgi alınamadı.
            </p>
          </div>
        ) : metadata ? (
          <div className="space-y-4">
            {/* Metadata summary */}
            <div className="space-y-1 rounded-xl border border-corio-border bg-corio-surface-2 p-3">
              <p className="text-sm font-medium text-corio-fg">{metadata.title}</p>
              {metadata.authors.length > 0 && (
                <p className="text-xs text-corio-fg/60">{metadata.authors.join('; ')}</p>
              )}
              <p className="text-xs text-corio-fg/50">
                {[metadata.journal, metadata.year, metadata.doi].filter(Boolean).join(' · ')}
              </p>
              <p className="flex items-center gap-1 pt-1 text-[11px] text-corio-fg/40">
                {source === 'crossref' ? (
                  'Kaynak: Crossref (DOI)'
                ) : (
                  <>
                    <Sparkles className="size-3" />
                    Kaynak: AI çıkarımı — kontrol edin
                  </>
                )}
              </p>
            </div>

            {/* Format toggle */}
            <div className="flex items-center gap-1 rounded-xl bg-corio-surface-2 p-1">
              {(['bibtex', 'ris'] as const).map(f => (
                <button
                  key={f}
                  onClick={() => setFormat(f)}
                  className={`flex-1 rounded-lg py-1.5 text-xs font-medium transition-colors ${
                    format === f
                      ? 'bg-corio-bg text-corio-accent shadow-sm'
                      : 'text-corio-fg/60 hover:text-corio-fg'
                  }`}
                >
                  {f === 'bibtex' ? 'BibTeX' : 'RIS'}
                </button>
              ))}
            </div>

            {/* Citation text */}
            <pre className="max-h-48 overflow-auto rounded-xl border border-corio-border bg-corio-surface-1 p-3 font-mono text-xs leading-relaxed text-corio-fg">
              {content}
            </pre>

            {/* Actions */}
            <div className="flex gap-2">
              <button
                onClick={handleCopy}
                className="flex flex-1 items-center justify-center gap-1.5 rounded-xl border border-corio-border bg-corio-surface-2 py-2 text-sm font-medium text-corio-fg transition-colors hover:bg-corio-surface-3"
              >
                <Copy className="size-4" />
                Kopyala
              </button>
              <button
                onClick={handleDownload}
                className="flex flex-1 items-center justify-center gap-1.5 rounded-xl bg-corio-accent py-2 text-sm font-medium text-white transition-colors hover:bg-corio-accent-hover"
              >
                <Download className="size-4" />
                İndir
              </button>
            </div>
          </div>
        ) : null}
      </DialogContent>
    </Dialog>
  );
}
