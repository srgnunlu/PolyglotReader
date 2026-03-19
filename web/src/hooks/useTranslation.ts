// Translation hook — calls Gemini translation API with session cache
"use client";

import { useState, useCallback, useRef } from "react";
import { translateText } from "@/lib/gemini";

interface TranslationResult {
  originalText: string;
  translatedText: string;
  isMedicalTerm: boolean;
}

export function useTranslation() {
  const [translation, setTranslation] = useState<TranslationResult | null>(null);
  const [isTranslating, setIsTranslating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const cacheRef = useRef<Map<string, TranslationResult>>(new Map());

  const translate = useCallback(async (text: string) => {
    const trimmed = text.trim();
    if (!trimmed) return;

    // Check cache
    const cached = cacheRef.current.get(trimmed);
    if (cached) {
      setTranslation(cached);
      return;
    }

    setIsTranslating(true);
    setError(null);

    try {
      const translatedText = await translateText(trimmed);
      const translationResult: TranslationResult = {
        originalText: trimmed,
        translatedText,
        isMedicalTerm: false,
      };

      cacheRef.current.set(trimmed, translationResult);
      setTranslation(translationResult);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Çeviri başarısız oldu");
    } finally {
      setIsTranslating(false);
    }
  }, []);

  const clearTranslation = useCallback(() => {
    setTranslation(null);
    setError(null);
  }, []);

  return { translate, translation, isTranslating, error, clearTranslation };
}
