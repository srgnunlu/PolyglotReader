// UploadArea - drag-and-drop zone for uploading PDF files
'use client';

import { useRef, useState, useCallback } from 'react';
import { Upload } from 'lucide-react';

interface UploadAreaProps {
  onFilesSelected?: (files: File[]) => void;
}

export function UploadArea({ onFilesSelected }: UploadAreaProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [isDragOver, setIsDragOver] = useState(false);

  const handleFiles = useCallback(
    (files: FileList | null) => {
      if (!files) return;
      const pdfFiles = Array.from(files).filter(f => f.type === 'application/pdf');
      if (pdfFiles.length > 0) {
        onFilesSelected?.(pdfFiles);
      }
    },
    [onFilesSelected]
  );

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(true);
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragOver(false);
  }, []);

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault();
      setIsDragOver(false);
      handleFiles(e.dataTransfer.files);
    },
    [handleFiles]
  );

  const handleClick = () => {
    inputRef.current?.click();
  };

  return (
    <div
      onClick={handleClick}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
      className="flex flex-col items-center justify-center gap-3 rounded-xl cursor-pointer transition-all py-10 px-6"
      style={{
        border: `2px dashed ${isDragOver ? '#D4713C' : 'rgba(42, 37, 32, 0.15)'}`,
        background: isDragOver
          ? 'rgba(212, 113, 60, 0.04)'
          : 'rgba(255, 255, 255, 0.4)',
        transition: 'border-color 0.2s ease, background 0.2s ease',
      }}
    >
      <div
        className="flex items-center justify-center w-12 h-12 rounded-full"
        style={{ background: 'rgba(212, 113, 60, 0.1)' }}
      >
        <Upload
          className="w-5 h-5"
          style={{ color: '#D4713C' }}
        />
      </div>

      <div className="text-center">
        <p className="text-sm font-medium" style={{ color: '#2A2520' }}>
          PDF dosyalarını buraya sürükleyin
        </p>
        <p className="text-xs mt-1" style={{ color: 'rgba(42, 37, 32, 0.5)' }}>
          veya seçmek için tıklayın
        </p>
      </div>

      <input
        ref={inputRef}
        type="file"
        accept=".pdf,application/pdf"
        multiple
        className="hidden"
        onChange={e => handleFiles(e.target.files)}
      />
    </div>
  );
}
