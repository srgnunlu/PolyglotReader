// AnnotationCard — displays a single annotation with highlight color, quoted text, note, and source info
'use client';

import { Card, CardContent } from '@/components/ui/card';
import { FileText } from 'lucide-react';

interface AnnotationCardProps {
  id: string;
  fileName: string;
  fileId: string;
  pageNumber: number;
  text: string;
  note: string;
  color: string;
  createdAt: Date;
  onClick: () => void;
}

export function AnnotationCard({
  fileName,
  pageNumber,
  text,
  note,
  color,
  createdAt,
  onClick,
}: AnnotationCardProps) {
  const truncatedText =
    text.length > 150 ? `${text.slice(0, 150)}...` : text;

  return (
    <Card
      className="cursor-pointer border-l-4 bg-corio-surface-1 border-corio-border transition-all hover:shadow-md hover:-translate-y-0.5"
      style={{ borderLeftColor: color }}
      onClick={onClick}
    >
      <CardContent className="space-y-2">
        {/* Quoted highlighted text */}
        {text && (
          <p className="text-sm italic text-corio-fg/70 leading-relaxed">
            &ldquo;{truncatedText}&rdquo;
          </p>
        )}

        {/* User note */}
        {note && (
          <p className="text-sm text-corio-fg leading-relaxed">
            {note}
          </p>
        )}

        {/* Footer: source + date */}
        <div className="flex items-center justify-between pt-1">
          <button
            className="flex items-center gap-1.5 text-xs text-corio-accent hover:text-corio-accent-hover transition-colors"
            onClick={(e) => {
              e.stopPropagation();
              onClick();
            }}
          >
            <FileText className="size-3.5" />
            <span className="truncate max-w-[180px]">{fileName}</span>
            <span className="text-corio-fg/40">
              &middot; Sayfa {pageNumber}
            </span>
          </button>
          <span className="text-xs text-corio-fg/40 shrink-0">
            {createdAt.toLocaleDateString('tr-TR')}
          </span>
        </div>
      </CardContent>
    </Card>
  );
}
