// EmptyLibrary - empty state shown when no documents are in the library
'use client';

import { FileUp } from 'lucide-react';

interface EmptyLibraryProps {
  onUploadClick?: () => void;
}

export function EmptyLibrary({ onUploadClick }: EmptyLibraryProps) {
  return (
    <div className="flex flex-col items-center justify-center gap-5 py-20 px-6 text-center animate-in fade-in duration-500">
      {/* Icon */}
      <div className="flex items-center justify-center w-20 h-20 rounded-2xl bg-corio-accent-subtle">
        <FileUp className="w-9 h-9 text-corio-accent" />
      </div>

      {/* Text */}
      <div className="flex flex-col gap-2">
        <h3 className="text-lg font-semibold text-corio-fg">
          Henüz belge yüklenmemiş
        </h3>
        <p className="text-sm max-w-xs text-corio-fg/50">
          iOS uygulamasından veya buradan PDF yükleyerek kütüphanenizi oluşturun.
        </p>
      </div>

      {/* Upload button */}
      <button
        onClick={onUploadClick}
        className="flex items-center gap-2 px-5 py-2.5 rounded-xl text-sm font-medium transition-all hover:bg-corio-accent-hover active:scale-[0.98] bg-corio-accent text-white focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-corio-accent/40"
      >
        <FileUp className="w-4 h-4" />
        PDF Yükle
      </button>
    </div>
  );
}
