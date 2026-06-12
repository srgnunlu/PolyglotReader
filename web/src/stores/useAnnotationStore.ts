// Zustand store for annotations — single source of truth for annotation
// data and tool selection (replaces the old AnnotationContext).
import { create } from 'zustand';
import { Annotation, AnnotationType } from '@/types/models';
import {
    loadAnnotations,
    saveAnnotation,
    updateAnnotation,
    deleteAnnotation,
} from '@/lib/annotationSync';

interface AnnotationStore {
    annotations: Annotation[];
    selectedTool: AnnotationType | null;
    selectedColor: string;
    isLoading: boolean;
    setSelectedTool: (tool: AnnotationType | null) => void;
    setSelectedColor: (color: string) => void;
    loadFileAnnotations: (fileId: string) => Promise<void>;
    addAnnotation: (annotation: Omit<Annotation, 'id' | 'createdAt' | 'isAiGenerated'>) => Promise<void>;
    removeAnnotation: (annotationId: string) => Promise<void>;
    updateAnnotationNote: (annotationId: string, note: string) => Promise<void>;
    reset: () => void;
}

export const useAnnotationStore = create<AnnotationStore>((set) => ({
    annotations: [],
    selectedTool: null,
    selectedColor: '#fef08a', // yellow default
    isLoading: false,

    setSelectedTool: (tool) => set({ selectedTool: tool }),
    setSelectedColor: (color) => set({ selectedColor: color }),

    loadFileAnnotations: async (fileId) => {
        set({ isLoading: true });
        try {
            const annotations = await loadAnnotations(fileId);
            set({ annotations });
        } catch (error) {
            console.error('Failed to load annotations:', error);
        } finally {
            set({ isLoading: false });
        }
    },

    addAnnotation: async (annotation) => {
        try {
            const saved = await saveAnnotation(
                annotation.fileId,
                annotation.pageNumber,
                annotation.type,
                annotation.color,
                annotation.rects,
                annotation.text,
                annotation.note
            );
            if (saved) {
                set((state) => ({ annotations: [...state.annotations, saved] }));
            }
        } catch (error) {
            console.error('Failed to add annotation:', error);
        }
    },

    removeAnnotation: async (annotationId) => {
        try {
            const success = await deleteAnnotation(annotationId);
            if (success) {
                set((state) => ({
                    annotations: state.annotations.filter((a) => a.id !== annotationId),
                }));
            }
        } catch (error) {
            console.error('Failed to remove annotation:', error);
        }
    },

    updateAnnotationNote: async (annotationId, note) => {
        try {
            const success = await updateAnnotation(annotationId, { note });
            if (success) {
                set((state) => ({
                    annotations: state.annotations.map((a) =>
                        a.id === annotationId ? { ...a, note } : a
                    ),
                }));
            }
        } catch (error) {
            console.error('Failed to update annotation:', error);
        }
    },

    // Called when leaving the reader so the next document starts clean.
    reset: () => set({ annotations: [], selectedTool: null, isLoading: false }),
}));
