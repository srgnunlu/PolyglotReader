// NotebookFilters — search input and color filter buttons for the notebook page
'use client';

import { Search } from 'lucide-react';

interface NotebookFiltersProps {
  searchQuery: string;
  onSearchChange: (query: string) => void;
  activeColor: string | null;
  onColorFilter: (color: string | null) => void;
}

const HIGHLIGHT_COLORS = [
  { value: '#fef08a', label: 'Sari' },
  { value: '#bbf7d0', label: 'Yesil' },
  { value: '#bae6fd', label: 'Mavi' },
  { value: '#fbcfe8', label: 'Pembe' },
];

export function NotebookFilters({
  searchQuery,
  onSearchChange,
  activeColor,
  onColorFilter,
}: NotebookFiltersProps) {
  return (
    <div className="flex flex-col sm:flex-row sm:items-center gap-3">
      {/* Search input */}
      <div className="relative flex-1 sm:max-w-md">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 size-4 text-corio-fg/40 pointer-events-none" />
        <input
          type="text"
          placeholder="Notlarda ara..."
          value={searchQuery}
          onChange={(e) => onSearchChange(e.target.value)}
          className="w-full pl-9 pr-4 py-2 rounded-xl text-sm outline-none transition-all bg-white/70 border border-corio-border-subtle text-corio-fg placeholder:text-corio-fg/40 focus:border-corio-accent focus:ring-2 focus:ring-corio-accent/20"
        />
      </div>

      {/* Color filter circles */}
      <div className="flex items-center gap-2">
        {/* All colors button */}
        <button
          onClick={() => onColorFilter(null)}
          className={`px-3 py-1 rounded-full text-xs font-medium transition-all ${
            activeColor === null
              ? 'bg-corio-accent text-white'
              : 'bg-corio-surface-2 text-corio-fg/60 hover:bg-corio-surface-3'
          }`}
        >
          Hepsi
        </button>

        {HIGHLIGHT_COLORS.map(({ value, label }) => (
          <button
            key={value}
            onClick={() => onColorFilter(activeColor === value ? null : value)}
            title={label}
            className={`size-7 rounded-full border-2 transition-all ${
              activeColor === value
                ? 'border-corio-fg/60 scale-110'
                : 'border-transparent hover:scale-105'
            }`}
            style={{ backgroundColor: value }}
          />
        ))}
      </div>
    </div>
  );
}
