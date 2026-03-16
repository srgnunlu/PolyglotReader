'use client';

import { useState, useEffect, useRef } from 'react';
import { pdfCache } from '@/lib/pdfCache';
import { getSupabase } from '@/lib/supabase';

interface UsePDFLoaderOptions {
    pdfUrl: string;
    storagePath?: string;
}

interface UsePDFLoaderReturn {
    pdfDataUrl: string | null;
    isLoading: boolean;
    error: string | null;
}

export function usePDFLoader({ pdfUrl, storagePath }: UsePDFLoaderOptions): UsePDFLoaderReturn {
    const [pdfDataUrl, setPdfDataUrl] = useState<string | null>(null);
    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const objectUrlRef = useRef<string | null>(null);

    useEffect(() => {
        const abortController = new AbortController();
        const signal = abortController.signal;

        const loadPDF = async () => {
            setIsLoading(true);
            setError(null);

            try {
                if (storagePath) {
                    // Cache-first strategy
                    const cachedBlob = await pdfCache.getCachedPDF(storagePath);
                    if (signal.aborted) return;

                    if (cachedBlob) {
                        const url = URL.createObjectURL(cachedBlob);
                        objectUrlRef.current = url;
                        setPdfDataUrl(url);
                        setIsLoading(false);
                        return;
                    }

                    // Cache miss - download from Supabase
                    const supabase = getSupabase();
                    const { data: blob, error: dlError } = await supabase.storage
                        .from('user_files')
                        .download(storagePath, { signal });

                    if (signal.aborted) return;
                    if (dlError) throw dlError;
                    if (!blob) throw new Error('No blob returned from Supabase');

                    await pdfCache.cachePDF(blob, storagePath);
                    if (signal.aborted) return;

                    const url = URL.createObjectURL(blob);
                    objectUrlRef.current = url;
                    setPdfDataUrl(url);
                } else {
                    setPdfDataUrl(pdfUrl);
                }

                if (signal.aborted) return;
                setIsLoading(false);
            } catch (err) {
                if (signal.aborted) return;
                console.error('[usePDFLoader] Error:', err);
                setError(err instanceof Error ? err.message : 'Failed to load PDF');
                setIsLoading(false);
                // Fallback to direct URL
                setPdfDataUrl(pdfUrl);
            }
        };

        loadPDF();

        return () => {
            abortController.abort();
            if (objectUrlRef.current) {
                URL.revokeObjectURL(objectUrlRef.current);
                objectUrlRef.current = null;
            }
        };
    }, [pdfUrl, storagePath]);

    return { pdfDataUrl, isLoading, error };
}
