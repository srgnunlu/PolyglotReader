// Zustand store for reader UI state and annotation management
import { create } from "zustand";

interface ReaderStore {
  // UI toggles
  isChatOpen: boolean;
  isThumbnailOpen: boolean;
  isTranslationMode: boolean;
  toggleChat: () => void;
  toggleThumbnail: () => void;
  toggleTranslationMode: () => void;
  setChatOpen: (open: boolean) => void;
}

export const useReaderStore = create<ReaderStore>((set) => ({
  isChatOpen: false,
  isThumbnailOpen: true,
  isTranslationMode: false,
  toggleChat: () => set((s) => ({ isChatOpen: !s.isChatOpen })),
  toggleThumbnail: () => set((s) => ({ isThumbnailOpen: !s.isThumbnailOpen })),
  toggleTranslationMode: () => set((s) => ({ isTranslationMode: !s.isTranslationMode })),
  setChatOpen: (open) => set({ isChatOpen: open }),
}));
