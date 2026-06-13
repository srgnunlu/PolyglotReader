// Reader toolbar — annotation color picker, translation/chat toggles, fullscreen
"use client";

import { Globe, MessageSquare, Maximize } from "lucide-react";
import { Button } from "@/components/ui/button";

const HIGHLIGHT_COLORS = [
  { name: "Sarı", value: "#fef08a", shortcut: "1" },
  { name: "Yeşil", value: "#bbf7d0", shortcut: "2" },
  { name: "Mavi", value: "#bae6fd", shortcut: "3" },
  { name: "Pembe", value: "#fbcfe8", shortcut: "4" },
] as const;

interface ReaderToolbarProps {
  selectedColor: string;
  onColorChange: (color: string) => void;
  onQuickHighlight?: (color: string) => void;
  isQuickTranslationMode: boolean;
  onToggleTranslation: () => void;
  isChatOpen: boolean;
  onToggleChat: () => void;
  isFullscreen: boolean;
  onToggleFullscreen: () => void;
}

export function ReaderToolbar({
  selectedColor,
  onColorChange,
  onQuickHighlight,
  isQuickTranslationMode,
  onToggleTranslation,
  isChatOpen,
  onToggleChat,
  isFullscreen,
  onToggleFullscreen,
}: ReaderToolbarProps) {
  return (
    <div className="flex items-center gap-3 px-3 py-2">
      {/* Highlight color picker */}
      <div className="flex items-center gap-1.5 border-r border-corio-border pr-3">
        {HIGHLIGHT_COLORS.map(({ name, value, shortcut }) => (
          <button
            key={value}
            title={`${name} (${shortcut})`}
            aria-label={`${name} ile işaretle`}
            className={`h-6 w-6 rounded-full border-2 transition-all hover:scale-110 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-corio-accent/40 ${
              selectedColor === value
                ? "border-corio-fg/60 scale-110 ring-2 ring-corio-accent/30"
                : "border-transparent"
            }`}
            style={{ backgroundColor: value }}
            onMouseDown={(e) => e.preventDefault()}
            onClick={() => {
              onColorChange(value);
              onQuickHighlight?.(value);
            }}
          />
        ))}
      </div>

      {/* Translation toggle */}
      <Button
        variant={isQuickTranslationMode ? "default" : "ghost"}
        size="icon"
        className={`h-8 w-8 ${isQuickTranslationMode ? "bg-corio-accent text-white hover:bg-corio-accent-hover" : ""}`}
        onClick={onToggleTranslation}
        title={isQuickTranslationMode ? "Hızlı çeviri açık" : "Hızlı çeviri"}
      >
        <Globe className="h-4 w-4" />
      </Button>

      {/* Chat toggle */}
      <Button
        variant={isChatOpen ? "default" : "ghost"}
        size="icon"
        className={`h-8 w-8 ${isChatOpen ? "bg-corio-accent text-white hover:bg-corio-accent-hover" : ""}`}
        onClick={onToggleChat}
        title="AI Sohbet (⌘J)"
      >
        <MessageSquare className="h-4 w-4" />
      </Button>

      {/* Fullscreen */}
      <Button
        variant={isFullscreen ? "default" : "ghost"}
        size="icon"
        className={`h-8 w-8 ${isFullscreen ? "bg-corio-accent text-white hover:bg-corio-accent-hover" : ""}`}
        onClick={onToggleFullscreen}
        title={isFullscreen ? "Tam ekrandan çık (Esc)" : "Tam ekran (F11)"}
      >
        <Maximize className="h-4 w-4" />
      </Button>
    </div>
  );
}
