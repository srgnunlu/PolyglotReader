// PDFCard - single document card for the library grid view
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
      <div className="flex h-full w-full items-center justify-center bg-corio-surface-2 animate-pulse">
        <FileText className="h-8 w-8 text-corio-fg/20" />
      </div>
    ),
  }
);

interface PDFCardProps {
  document: PDFDocumentMetadata;
  /** Position in the grid — drives a capped stagger on entrance */
  index?: number;
}

// Cap the stagger so a large library doesn't pile up seconds of delay
const STAGGER_MS = 35;
const MAX_STAGGER_STEPS = 12;

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

export function PDFCard({ document, index = 0 }: PDFCardProps) {
  const router = useRouter();
  const [isHovered, setIsHovered] = useState(false);

  const staggerDelay = Math.min(index, MAX_STAGGER_STEPS) * STAGGER_MS;

  return (
    <div
      onClick={() => router.push(`/reader/${document.id}`)}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
      className="cursor-pointer rounded-xl overflow-hidden flex flex-col bg-corio-surface-1 border border-corio-border-subtle animate-in fade-in slide-in-from-bottom-2 fill-mode-both duration-300 motion-reduce:animate-none"
      style={{
        animationDelay: `${staggerDelay}ms`,
        transform: isHovered ? 'translateY(-2px)' : 'translateY(0)',
        boxShadow: isHovered
          ? '0 8px 30px rgba(212, 113, 60, 0.15), 0 2px 8px rgba(42, 37, 32, 0.06)'
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
          className="text-sm font-medium leading-snug text-corio-fg"
          style={{
            display: '-webkit-box',
            WebkitLineClamp: 2,
            WebkitBoxOrient: 'vertical',
            overflow: 'hidden',
          }}
        >
          {document.name}
        </h4>
        <div className="flex items-center gap-1.5 text-xs text-corio-fg/50">
          <span>{formatFileSize(document.size)}</span>
          <span>·</span>
          <span>{formatDate(document.uploadedAt)}</span>
        </div>
      </div>
    </div>
  );
}
