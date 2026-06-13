// Bottom bar page controls — previous/next, page input, zoom controls
"use client";

import { ChevronLeft, ChevronRight, Minus, Plus, RotateCcw } from "lucide-react";
import { Button } from "@/components/ui/button";

interface PageNavigationProps {
  currentPage: number;
  totalPages: number;
  displayScale: number;
  onGoToPage: (page: number) => void;
  onZoomIn: () => void;
  onZoomOut: () => void;
  onResetZoom: () => void;
}

export function PageNavigation({
  currentPage,
  totalPages,
  displayScale,
  onGoToPage,
  onZoomIn,
  onZoomOut,
  onResetZoom,
}: PageNavigationProps) {
  return (
    <div className="flex items-center gap-3 px-3 py-2">
      {/* Page navigation */}
      <div className="flex items-center gap-1">
        <Button
          variant="ghost"
          size="icon"
          className="h-8 w-8"
          onClick={() => onGoToPage(currentPage - 1)}
          disabled={currentPage <= 1}
        >
          <ChevronLeft className="h-4 w-4" />
        </Button>
        <div className="flex items-center gap-1 text-sm text-corio-fg/70">
          <span>Sayfa</span>
          <input
            type="number"
            value={currentPage}
            onChange={(e) => onGoToPage(parseInt(e.target.value) || 1)}
            min={1}
            max={totalPages}
            className="w-12 rounded-md border border-corio-border bg-corio-bg px-2 py-0.5 text-center text-sm text-corio-fg"
          />
          <span>/ {totalPages || 0}</span>
        </div>
        <Button
          variant="ghost"
          size="icon"
          className="h-8 w-8"
          onClick={() => onGoToPage(currentPage + 1)}
          disabled={currentPage >= totalPages}
        >
          <ChevronRight className="h-4 w-4" />
        </Button>
      </div>

      {/* Zoom controls */}
      <div className="flex items-center gap-1 border-l border-corio-border pl-4">
        <Button variant="ghost" size="icon" className="h-8 w-8" onClick={onZoomOut}>
          <Minus className="h-4 w-4" />
        </Button>
        <span className="min-w-[48px] text-center text-sm text-corio-fg/70">
          {Math.round(displayScale * 100)}%
        </span>
        <Button variant="ghost" size="icon" className="h-8 w-8" onClick={onZoomIn}>
          <Plus className="h-4 w-4" />
        </Button>
        <Button variant="ghost" size="icon" className="h-8 w-8" onClick={onResetZoom}>
          <RotateCcw className="h-3.5 w-3.5" />
        </Button>
      </div>
    </div>
  );
}
