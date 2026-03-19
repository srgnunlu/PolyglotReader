// Zustand store for library page UI preferences (persisted to localStorage)
import { create } from "zustand";
import { persist } from "zustand/middleware";

interface LibraryStore {
  viewMode: "grid" | "list";
  sortBy: "name" | "date" | "size" | "lastRead";
  searchQuery: string;
  setViewMode: (mode: "grid" | "list") => void;
  setSortBy: (sort: "name" | "date" | "size" | "lastRead") => void;
  setSearchQuery: (query: string) => void;
}

export const useLibraryStore = create<LibraryStore>()(
  persist(
    (set) => ({
      viewMode: "grid",
      sortBy: "date",
      searchQuery: "",
      setViewMode: (mode) => set({ viewMode: mode }),
      setSortBy: (sort) => set({ sortBy: sort }),
      setSearchQuery: (query) => set({ searchQuery: query }),
    }),
    {
      name: "corio-library-prefs",
      partialize: (state) => ({ viewMode: state.viewMode, sortBy: state.sortBy }),
    }
  )
);
