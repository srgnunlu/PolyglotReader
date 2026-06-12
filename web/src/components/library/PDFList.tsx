// PDFList - table/list layout for documents with small thumbnail, title, date, size
'use client';

import dynamic from 'next/dynamic';
import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { PDFDocumentMetadata } from '@/types/models';

const PDFThumbnail = dynamic(
  () => import('@/components/library/PDFThumbnail').then(mod => mod.PDFThumbnail),
  {
    ssr: false,
    loading: () => (
      <div
        style={{
          width: '100%',
          height: '100%',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontSize: 16,
        }}
      >
        📄
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

function PDFListRow({ document }: { document: PDFDocumentMetadata }) {
  const router = useRouter();
  const [isHovered, setIsHovered] = useState(false);

  return (
    <div
      onClick={() => router.push(`/reader/${document.id}`)}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
      className="flex items-center gap-4 px-4 py-3 rounded-xl cursor-pointer transition-colors"
      style={{
        background: isHovered ? 'rgba(212, 113, 60, 0.04)' : 'transparent',
        borderBottom: '1px solid rgba(42, 37, 32, 0.06)',
      }}
    >
      {/* Small thumbnail */}
      <div
        className="shrink-0 rounded-lg overflow-hidden"
        style={{
          width: 40,
          height: 52,
          background: 'rgba(42, 37, 32, 0.04)',
        }}
      >
        <PDFThumbnail
          storagePath={document.storagePath}
          alt={document.name}
          base64Data={document.thumbnailData}
        />
      </div>

      {/* Title — takes remaining space */}
      <div className="flex-1 min-w-0">
        <p
          className="text-sm font-medium truncate"
          style={{ color: '#2A2520' }}
        >
          {document.name}
        </p>
        {document.summary && (
          <p
            className="text-xs mt-0.5 truncate"
            style={{ color: 'rgba(42, 37, 32, 0.5)' }}
          >
            {document.summary}
          </p>
        )}
      </div>

      {/* Date */}
      <span
        className="shrink-0 text-xs hidden sm:block"
        style={{ color: 'rgba(42, 37, 32, 0.5)' }}
      >
        {formatDate(document.uploadedAt)}
      </span>

      {/* Size */}
      <span
        className="shrink-0 text-xs w-16 text-right"
        style={{ color: 'rgba(42, 37, 32, 0.5)' }}
      >
        {formatFileSize(document.size)}
      </span>
    </div>
  );
}

export function PDFList({ documents }: PDFListProps) {
  return (
    <div
      className="rounded-xl overflow-hidden"
      style={{
        background: 'rgba(255, 255, 255, 0.7)',
        border: '1px solid rgba(42, 37, 32, 0.06)',
      }}
    >
      {/* Column headers */}
      <div
        className="flex items-center gap-4 px-4 py-2 border-b"
        style={{ borderColor: 'rgba(42, 37, 32, 0.06)' }}
      >
        <div className="w-10 shrink-0" />
        <span className="flex-1 text-xs font-medium" style={{ color: 'rgba(42, 37, 32, 0.5)' }}>
          Belge Adı
        </span>
        <span
          className="shrink-0 text-xs font-medium hidden sm:block"
          style={{ color: 'rgba(42, 37, 32, 0.5)' }}
        >
          Tarih
        </span>
        <span
          className="shrink-0 text-xs font-medium w-16 text-right"
          style={{ color: 'rgba(42, 37, 32, 0.5)' }}
        >
          Boyut
        </span>
      </div>

      {/* Rows */}
      {documents.map(doc => (
        <PDFListRow key={doc.id} document={doc} />
      ))}
    </div>
  );
}
