// PDFThumbnail - renders the first page of a PDF as a thumbnail image
// Supports: base64 pre-cached data (fastest), IndexedDB blob cache, or live Supabase download
'use client';

import { useEffect, useState, useCallback, useRef } from 'react';
import { Document, Page } from 'react-pdf';
import { getSupabase } from '@/lib/supabase';
import { thumbnailCache } from '@/lib/thumbnailCache';

import '@/lib/pdfjs-config'; // Initialize PDF.js worker configuration

interface PDFThumbnailProps {
    storagePath: string;
    alt: string;
    base64Data?: string; // Pre-cached base64 thumbnail
}

type LoadingState = 'idle' | 'loading' | 'loaded' | 'error';

// Shared skeleton used during load and error states
function ThumbnailSkeleton({ icon = '📄' }: { icon?: string }) {
    return (
        <div
            style={{
                width: '100%',
                height: '100%',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                background: 'rgba(42, 37, 32, 0.04)',
                fontSize: 28,
                minHeight: 80,
            }}
        >
            {icon}
        </div>
    );
}

export function PDFThumbnail({ storagePath, alt, base64Data }: PDFThumbnailProps) {
    const [pdfUrl, setPdfUrl] = useState<string | null>(null);
    const [loadingState, setLoadingState] = useState<LoadingState>('idle');
    const objectUrlRef = useRef<string | null>(null);

    // Cleanup function for object URLs
    const cleanupObjectUrl = useCallback(() => {
        if (objectUrlRef.current) {
            URL.revokeObjectURL(objectUrlRef.current);
            objectUrlRef.current = null;
        }
    }, []);

    useEffect(() => {
        // If we have base64 data, use it directly (fastest path)
        if (base64Data) {
            setLoadingState('loaded');
            return;
        }

        setLoadingState('loading');

        const fetchUrl = async () => {
            try {
                const cacheKey = `thumbnail:${storagePath}`;

                // 1. Check cache first — instant hit path
                const cachedBlob = await thumbnailCache.getCachedThumbnail(cacheKey);
                if (cachedBlob) {
                    cleanupObjectUrl();
                    const url = URL.createObjectURL(cachedBlob);
                    objectUrlRef.current = url;
                    setPdfUrl(url);
                    setLoadingState('loaded');
                    return;
                }

                // 2. Cache miss — download from Supabase
                const supabase = getSupabase();
                const { data, error } = await supabase.storage
                    .from('user_files')
                    .createSignedUrl(storagePath, 3600);

                if (error) throw error;

                const response = await fetch(data.signedUrl);
                if (!response.ok) throw new Error('Failed to fetch thumbnail');

                const blob = await response.blob();

                // 3. Cache for next time (fire and forget)
                thumbnailCache.cacheThumbnail(cacheKey, blob).catch(() => {
                    // Silently ignore cache errors — non-critical
                });

                // 4. Create object URL for rendering
                cleanupObjectUrl();
                const url = URL.createObjectURL(blob);
                objectUrlRef.current = url;
                setPdfUrl(url);
                setLoadingState('loaded');
            } catch (err) {
                console.error('Thumbnail URL error:', err);
                setLoadingState('error');
            }
        };

        fetchUrl();

        return cleanupObjectUrl;
    }, [storagePath, base64Data, cleanupObjectUrl]);

    if (loadingState === 'loading' || loadingState === 'idle') {
        return <ThumbnailSkeleton />;
    }

    if (loadingState === 'error') {
        return <ThumbnailSkeleton />;
    }

    // Render base64 pre-cached image (fastest path)
    if (base64Data) {
        return (
            <div style={{ width: '100%', height: '100%', position: 'relative', background: '#ffffff' }}>
                <img
                    src={`data:image/png;base64,${base64Data}`}
                    alt={alt}
                    style={{
                        width: '100%',
                        height: '100%',
                        objectFit: 'contain',
                        objectPosition: 'top center',
                        display: 'block',
                    }}
                />
            </div>
        );
    }

    // Render PDF first page via react-pdf — scale to fill container
    if (pdfUrl) {
        return (
            <div style={{
                width: '100%',
                height: '100%',
                position: 'relative',
                overflow: 'hidden',
                display: 'flex',
                alignItems: 'flex-start',
                justifyContent: 'center',
                background: '#ffffff',
            }}>
                <Document
                    file={pdfUrl}
                    loading={<ThumbnailSkeleton />}
                    error={<ThumbnailSkeleton />}
                    className="pdf-thumbnail-document"
                >
                    <Page
                        pageNumber={1}
                        width={300}
                        renderTextLayer={false}
                        renderAnnotationLayer={false}
                    />
                </Document>
                {/* Transparent overlay prevents accidental PDF interaction clicks */}
                <div style={{ position: 'absolute', inset: 0, zIndex: 10 }} />
            </div>
        );
    }

    return <ThumbnailSkeleton />;
}
