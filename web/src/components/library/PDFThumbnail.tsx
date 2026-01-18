'use client';

import { useEffect, useState, useCallback, useRef } from 'react';
import { Document, Page } from 'react-pdf';
import { getSupabase } from '@/lib/supabase';
import { thumbnailCache } from '@/lib/thumbnailCache';
import styles from '@/app/library/library.module.css';

import '@/lib/pdfjs-config'; // Initialize PDF.js worker configuration

interface PDFThumbnailProps {
    storagePath: string;
    alt: string;
    base64Data?: string; // Pre-cached base64 thumbnail
}

type LoadingState = 'idle' | 'loading' | 'loaded' | 'error';

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

                // 1. Check cache first - instant hit path
                const cachedBlob = await thumbnailCache.getCachedThumbnail(cacheKey);
                if (cachedBlob) {
                    cleanupObjectUrl();
                    const url = URL.createObjectURL(cachedBlob);
                    objectUrlRef.current = url;
                    setPdfUrl(url);
                    setLoadingState('loaded');
                    return;
                }

                // 2. Cache miss - download from Supabase
                const supabase = getSupabase();
                const { data, error } = await supabase.storage
                    .from('user_files')
                    .createSignedUrl(storagePath, 3600);

                if (error) throw error;

                // Fetch the actual file
                const response = await fetch(data.signedUrl);
                if (!response.ok) throw new Error('Failed to fetch thumbnail');

                const blob = await response.blob();

                // 3. Cache for next time (fire and forget)
                thumbnailCache.cacheThumbnail(cacheKey, blob).catch(() => {
                    // Silently ignore cache errors
                });

                // 4. Create object URL
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

        // Cleanup on unmount
        return cleanupObjectUrl;
    }, [storagePath, base64Data, cleanupObjectUrl]);

    // Loading state - Skeleton loader
    if (loadingState === 'loading' || loadingState === 'idle') {
        return (
            <div className={styles.skeleton}>
                <span className={styles.skeletonIcon}>📄</span>
            </div>
        );
    }

    // Error state
    if (loadingState === 'error') {
        return (
            <div className={styles.cardPlaceholder}>
                <span>📄</span>
            </div>
        );
    }

    // If base64 data exists, render as image (fastest)
    if (base64Data) {
        return (
            <div className={styles.cardThumbnailWrapper}>
                <img
                    src={`data:image/png;base64,${base64Data}`}
                    alt={alt}
                    className={styles.thumbnailLoaded}
                />
            </div>
        );
    }

    // Render PDF first page
    if (pdfUrl) {
        return (
            <div className={styles.cardThumbnailWrapper}>
                <Document
                    file={pdfUrl}
                    loading={
                        <div className={styles.skeleton}>
                            <span className={styles.skeletonIcon}>📄</span>
                        </div>
                    }
                    error={<div className={styles.cardPlaceholder}>📄</div>}
                    className="pdf-thumbnail-document"
                >
                    <Page
                        pageNumber={1}
                        width={200}
                        renderTextLayer={false}
                        renderAnnotationLayer={false}
                        className={styles.thumbnailLoaded}
                    />
                </Document>
                {/* Overlay to prevent interaction */}
                <div style={{ position: 'absolute', inset: 0, zIndex: 10 }} />
            </div>
        );
    }

    return (
        <div className={styles.cardPlaceholder}>
            <span>📄</span>
        </div>
    );
}
