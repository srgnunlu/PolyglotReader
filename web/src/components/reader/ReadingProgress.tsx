// Thin accent-colored progress bar at top of reader
"use client";

interface ReadingProgressProps {
  progress: number; // 0-100
}

export function ReadingProgress({ progress }: ReadingProgressProps) {
  return (
    <div className="h-0.5 w-full bg-corio-surface-2">
      <div
        className="h-full bg-corio-accent transition-all duration-300 ease-out"
        style={{ width: `${Math.min(100, Math.max(0, progress))}%` }}
      />
    </div>
  );
}
