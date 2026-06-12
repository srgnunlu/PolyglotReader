// PDFGrid - responsive grid layout that renders a PDFCard for each document
'use client';

import { PDFDocumentMetadata } from '@/types/models';
import { PDFCard } from './PDFCard';

interface PDFGridProps {
  documents: PDFDocumentMetadata[];
}

export function PDFGrid({ documents }: PDFGridProps) {
  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4">
      {documents.map(doc => (
        <PDFCard key={doc.id} document={doc} />
      ))}
    </div>
  );
}
