// PDFList - table/list layout for documents with small thumbnail, title, date, size
'use client';

import dynamic from 'next/dynamic';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { FileText } from 'lucide-react';
import { PDFDocumentMetadata } from '@/types/models';

const PDFThumbnail = dynamic(
  () => import('@/components/library/PDFThumbnail').then(mod => mod.PDFThumbnail),
  {
    ssr: false,
    loading: () => (
      <div className="flex h-full w-full items-center justify-center">
        <FileText className="h-4 w-4 text-corio-fg/20" />
      </div>
    ),
  }
);

interface PDFListProps {
  documents: PDFDocumentMetadata[];
}

function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function formatDate(date: Date): string {
  return date.toLocaleDateString('tr-TR', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });
}

// Cap the stagger so a long list doesn't pile up seconds of delay
const STAGGER_MS = 25;
const MAX_STAGGER_STEPS = 14;

function PDFListRow({ document, index = 0 }: { document: PDFDocumentMetadata; index?: number }) {
  const router = useRouter();
  const [isHovered, setIsHovered] = useState(false);

  const staggerDelay = Math.min(index, MAX_STAGGER_STEPS) * STAGGER_MS;

  return (
    <div
      onClick={() => router.push(`/reader/${document.id}`)}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
      style={{ animationDelay: `${staggerDelay}ms` }}
      className={`flex items-center gap-4 px-4 py-3 rounded-xl cursor-pointer transition-colors border-b border-corio-border-subtle animate-in fade-in slide-in-from-bottom-1 fill-mode-both duration-300 motion-reduce:animate-none ${
        isHovered ? 'bg-corio-accent-subtle' : 'bg-transparent'
      }`}
    >
      {/* Small thumbnail */}
      <div className="shrink-0 rounded-lg overflow-hidden bg-corio-surface-2" style={{ width: 40, height: 52 }}>
        <PDFThumbnail
          storagePath={document.storagePath}
          alt={document.name}
          base64Data={document.thumbnailData}
        />
      </div>

      {/* Title — takes remaining space */}
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium truncate text-corio-fg">
          {document.name}
        </p>
        {document.summary && (
          <p className="text-xs mt-0.5 truncate text-corio-fg/50">
            {document.summary}
          </p>
        )}
      </div>

      {/* Date */}
      <span className="shrink-0 text-xs hidden sm:block text-corio-fg/50">
        {formatDate(document.uploadedAt)}
      </span>

      {/* Size */}
      <span className="shrink-0 text-xs w-16 text-right text-corio-fg/50">
        {formatFileSize(document.size)}
      </span>
    </div>
  );
}

export function PDFList({ documents }: PDFListProps) {
  return (
    <div className="rounded-xl overflow-hidden bg-corio-surface-1 border border-corio-border-subtle">
      {/* Column headers */}
      <div className="flex items-center gap-4 px-4 py-2 border-b border-corio-border-subtle">
        <div className="w-10 shrink-0" />
        <span className="flex-1 text-xs font-medium text-corio-fg/50">
          Belge Adı
        </span>
        <span className="shrink-0 text-xs font-medium hidden sm:block text-corio-fg/50">
          Tarih
        </span>
        <span className="shrink-0 text-xs font-medium w-16 text-right text-corio-fg/50">
          Boyut
        </span>
      </div>

      {/* Rows */}
      {documents.map((doc, i) => (
        <PDFListRow key={doc.id} document={doc} index={i} />
      ))}
    </div>
  );
}
