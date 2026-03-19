// Zustand store for reader typography preferences (persisted to localStorage)
import { create } from "zustand";
import { persist } from "zustand/middleware";

interface ThemeStore {
  fontSize: number;
  fontFamily: "sans" | "serif" | "mono";
  setFontSize: (size: number) => void;
  setFontFamily: (family: "sans" | "serif" | "mono") => void;
}

export const useThemeStore = create<ThemeStore>()(
  persist(
    (set) => ({
      fontSize: 16,
      fontFamily: "sans",
      setFontSize: (size) => set({ fontSize: Math.min(24, Math.max(14, size)) }),
      setFontFamily: (family) => set({ fontFamily: family }),
    }),
    { name: "corio-theme-prefs" }
  )
);
