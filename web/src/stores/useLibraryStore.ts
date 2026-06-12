// Zustand store for library page UI preferences (persisted to localStorage).
// Search state lives in useDocuments — only durable view prefs belong here.
import { create } from "zustand";
import { persist } from "zustand/middleware";

interface LibraryStore {
  viewMode: "grid" | "list";
  setViewMode: (mode: "grid" | "list") => void;
}

export const useLibraryStore = create<LibraryStore>()(
  persist(
    (set) => ({
      viewMode: "grid",
      setViewMode: (mode) => set({ viewMode: mode }),
    }),
    { name: "corio-library-prefs" }
  )
);
