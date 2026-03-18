// EmptyLibrary - empty state shown when no documents are in the library
'use client';

import { FileUp } from 'lucide-react';

interface EmptyLibraryProps {
  onUploadClick?: () => void;
}

export function EmptyLibrary({ onUploadClick }: EmptyLibraryProps) {
  return (
    <div className="flex flex-col items-center justify-center gap-5 py-20 px-6 text-center">
      {/* Icon */}
      <div
        className="flex items-center justify-center w-20 h-20 rounded-2xl"
        style={{ background: 'rgba(212, 113, 60, 0.08)' }}
      >
        <FileUp
          className="w-9 h-9"
          style={{ color: '#D4713C' }}
        />
      </div>

      {/* Text */}
      <div className="flex flex-col gap-2">
        <h3 className="text-lg font-semibold" style={{ color: '#2A2520' }}>
          Henüz belge yüklenmemiş
        </h3>
        <p className="text-sm max-w-xs" style={{ color: 'rgba(42, 37, 32, 0.5)' }}>
          iOS uygulamasından veya buradan PDF yükleyerek kütüphanenizi oluşturun.
        </p>
      </div>

      {/* Upload button */}
      <button
        onClick={onUploadClick}
        className="flex items-center gap-2 px-5 py-2.5 rounded-xl text-sm font-medium transition-opacity hover:opacity-90 active:opacity-80"
        style={{
          background: '#D4713C',
          color: '#FDFAF6',
        }}
      >
        <FileUp className="w-4 h-4" />
        PDF Yükle
      </button>
    </div>
  );
}
