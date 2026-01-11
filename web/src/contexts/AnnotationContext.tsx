'use client';

import React, { createContext, useContext, useState, useCallback, useEffect } from 'react';
import { Annotation, AnnotationType } from '@/types/models';
import {
    loadAnnotations,
    saveAnnotation,
    updateAnnotation,
    deleteAnnotation
} from '@/lib/annotationSync';

interface AnnotationContextType {
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
}

const AnnotationContext = createContext<AnnotationContextType | undefined>(undefined);

export function useAnnotations() {
    const context = useContext(AnnotationContext);
    if (!context) {
        throw new Error('useAnnotations must be used within AnnotationProvider');
    }
    return context;
}

interface AnnotationProviderProps {
    children: React.ReactNode;
    fileId?: string;
}

export function AnnotationProvider({ children, fileId }: AnnotationProviderProps) {
    const [annotations, setAnnotations] = useState<Annotation[]>([]);
    const [selectedTool, setSelectedTool] = useState<AnnotationType | null>(null);
    const [selectedColor, setSelectedColor] = useState('#fef08a'); // yellow default
    const [isLoading, setIsLoading] = useState(false);

    // Load annotations when fileId changes
    const loadFileAnnotations = useCallback(async (fId: string) => {
        setIsLoading(true);
        try {
            const loadedAnnotations = await loadAnnotations(fId);
            setAnnotations(loadedAnnotations);
        } catch (error) {
            console.error('Failed to load annotations:', error);
        } finally {
            setIsLoading(false);
        }
    }, []);

    useEffect(() => {
        if (fileId) {
            loadFileAnnotations(fileId);
        } else {
            setAnnotations([]);
        }
    }, [fileId, loadFileAnnotations]);

    const addAnnotation = useCallback(async (
        annotation: Omit<Annotation, 'id' | 'createdAt' | 'isAiGenerated'>
    ) => {
        if (!fileId) return;

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
                setAnnotations(prev => [...prev, saved]);
            }
        } catch (error) {
            console.error('Failed to add annotation:', error);
        }
    }, [fileId]);

    const removeAnnotation = useCallback(async (annotationId: string) => {
        try {
            const success = await deleteAnnotation(annotationId);
            if (success) {
                setAnnotations(prev => prev.filter(a => a.id !== annotationId));
            }
        } catch (error) {
            console.error('Failed to remove annotation:', error);
        }
    }, []);

    const updateAnnotationNote = useCallback(async (annotationId: string, note: string) => {
        try {
            const success = await updateAnnotation(annotationId, { note });
            if (success) {
                setAnnotations(prev => prev.map(a =>
                    a.id === annotationId ? { ...a, note } : a
                ));
            }
        } catch (error) {
            console.error('Failed to update annotation:', error);
        }
    }, []);

    const value: AnnotationContextType = {
        annotations,
        selectedTool,
        selectedColor,
        isLoading,
        setSelectedTool,
        setSelectedColor,
        loadFileAnnotations,
        addAnnotation,
        removeAnnotation,
        updateAnnotationNote,
    };

    return (
        <AnnotationContext.Provider value={value}>
            {children}
        </AnnotationContext.Provider>
    );
}
