// PDFCard - single document card for the library grid view
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
          background: 'rgba(42, 37, 32, 0.04)',
          fontSize: 32,
        }}
      >
        📄
      </div>
    ),
  }
);

interface PDFCardProps {
  document: PDFDocumentMetadata;
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

export function PDFCard({ document }: PDFCardProps) {
  const router = useRouter();
  const [isHovered, setIsHovered] = useState(false);

  return (
    <div
      onClick={() => router.push(`/reader/${document.id}`)}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
      className="cursor-pointer rounded-xl overflow-hidden flex flex-col"
      style={{
        background: '#ffffff',
        border: '1px solid rgba(42, 37, 32, 0.06)',
        transform: isHovered ? 'translateY(-2px)' : 'translateY(0)',
        boxShadow: isHovered
          ? '0 8px 30px rgba(212, 113, 60, 0.12), 0 2px 8px rgba(42, 37, 32, 0.06)'
          : '0 1px 4px rgba(42, 37, 32, 0.04)',
        transition: 'transform 0.2s ease, box-shadow 0.2s ease',
      }}
    >
      {/* Thumbnail — 3:4 aspect ratio, always white background regardless of theme */}
      <div
        className="relative w-full overflow-hidden"
        style={{ aspectRatio: '3 / 4', background: '#ffffff' }}
      >
        <PDFThumbnail
          storagePath={document.storagePath}
          alt={document.name}
          base64Data={document.thumbnailData}
        />
      </div>

      {/* Card info */}
      <div className="p-3 flex flex-col gap-1">
        <h4
          className="text-sm font-medium leading-snug"
          style={{
            color: '#2A2520',
            display: '-webkit-box',
            WebkitLineClamp: 2,
            WebkitBoxOrient: 'vertical',
            overflow: 'hidden',
          }}
        >
          {document.name}
        </h4>
        <div
          className="flex items-center gap-1.5 text-xs"
          style={{ color: 'rgba(42, 37, 32, 0.5)' }}
        >
          <span>{formatFileSize(document.size)}</span>
          <span>·</span>
          <span>{formatDate(document.uploadedAt)}</span>
        </div>
      </div>
    </div>
  );
}
