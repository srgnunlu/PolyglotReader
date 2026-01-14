'use client';

import { useEffect, useState } from 'react';
import { Document, Page, pdfjs } from 'react-pdf';
import { getSupabase } from '@/lib/supabase';
import { thumbnailCache } from '@/lib/thumbnailCache';
import styles from '@/app/library/library.module.css';

import '@/lib/pdfjs-config'; // Initialize PDF.js worker configuration

interface PDFThumbnailProps {
    storagePath: string;
    alt: string;
}

export function PDFThumbnail({ storagePath, alt }: PDFThumbnailProps) {
    const [pdfUrl, setPdfUrl] = useState<string | null>(null);
    const [error, setError] = useState(false);

    useEffect(() => {
        let objectUrl: string | null = null;

        const fetchUrl = async () => {
            try {
                const cacheKey = `thumbnail:${storagePath}`;

                // 1. Check cache first
                const cachedBlob = await thumbnailCache.getCachedThumbnail(cacheKey);
                if (cachedBlob) {
                    objectUrl = URL.createObjectURL(cachedBlob);
                    setPdfUrl(objectUrl);
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

                // 3. Cache for next time
                await thumbnailCache.cacheThumbnail(cacheKey, blob);

                // 4. Create object URL
                objectUrl = URL.createObjectURL(blob);
                setPdfUrl(objectUrl);
            } catch (err) {
                console.error('Thumbnail URL error:', err);
                setError(true);
            }
        };

        fetchUrl();

        // Cleanup: revoke object URL
        return () => {
            if (objectUrl) {
                URL.revokeObjectURL(objectUrl);
            }
        };
    }, [storagePath]);

    if (error || !pdfUrl) {
        return <div className={styles.cardPlaceholder}>📄</div>;
    }

    return (
        <div className={styles.cardThumbnailWrapper} style={{ width: '100%', height: '100%', overflow: 'hidden', position: 'relative' }}>
            <Document
                file={pdfUrl}
                loading={<div className={styles.cardPlaceholder}>📄</div>}
                error={<div className={styles.cardPlaceholder}>📄</div>}
                className="pdf-thumbnail-document"
            >
                <Page
                    pageNumber={1}
                    width={200} // Approximate width of the card
                    renderTextLayer={false}
                    renderAnnotationLayer={false}
                />
            </Document>
            {/* Overlay to prevent interaction and ensure it acts like an image */}
            <div style={{ position: 'absolute', inset: 0, zIndex: 10 }} />
        </div>
    );
}
