// Global keyboard shortcuts hook — registers key handlers with modifier support
"use client";

import { useEffect, useCallback } from "react";

interface Shortcut {
  key: string;
  ctrl?: boolean;
  meta?: boolean;
  shift?: boolean;
  handler: () => void;
  /** If true, fires even inside input/textarea */
  global?: boolean;
}

export function useKeyboardShortcuts(shortcuts: Shortcut[]) {
  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      const target = e.target as HTMLElement;
      const isInput = target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.isContentEditable;

      for (const s of shortcuts) {
        const modOk =
          (!s.ctrl || e.ctrlKey) &&
          (!s.meta || e.metaKey) &&
          (!s.shift || e.shiftKey);

        if (modOk && e.key.toLowerCase() === s.key.toLowerCase()) {
          if (isInput && !s.global) continue;
          e.preventDefault();
          s.handler();
          return;
        }
      }
    },
    [shortcuts]
  );

  useEffect(() => {
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [handleKeyDown]);
}
