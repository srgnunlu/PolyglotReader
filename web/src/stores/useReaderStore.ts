// Zustand store for reader UI state shared across reader components
import { create } from "zustand";

interface ReaderStore {
  isChatOpen: boolean;
  isTranslationMode: boolean;
  toggleChat: () => void;
  toggleTranslationMode: () => void;
  setChatOpen: (open: boolean) => void;
  reset: () => void;
}

export const useReaderStore = create<ReaderStore>((set) => ({
  isChatOpen: false,
  isTranslationMode: false,
  toggleChat: () => set((s) => ({ isChatOpen: !s.isChatOpen })),
  toggleTranslationMode: () => set((s) => ({ isTranslationMode: !s.isTranslationMode })),
  setChatOpen: (open) => set({ isChatOpen: open }),
  // Called when leaving the reader so the next document starts clean.
  reset: () => set({ isChatOpen: false, isTranslationMode: false }),
}));
