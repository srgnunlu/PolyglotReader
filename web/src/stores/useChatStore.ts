// Zustand store for global chat panel UI state
import { create } from "zustand";

interface ChatStore {
  isOpen: boolean;
  activeFileId: string | null;
  toggleOpen: () => void;
  setActiveFileId: (id: string | null) => void;
}

export const useChatStore = create<ChatStore>((set) => ({
  isOpen: false,
  activeFileId: null,
  toggleOpen: () => set((s) => ({ isOpen: !s.isOpen })),
  setActiveFileId: (id) => set({ activeFileId: id }),
}));
