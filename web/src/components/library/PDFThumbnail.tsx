'use client';

import { useEffect, useState } from 'react';
import { Document, Page, pdfjs } from 'react-pdf';
import { getSupabase } from '@/lib/supabase';
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
        const fetchUrl = async () => {
            try {
                const supabase = getSupabase();
                const { data, error } = await supabase.storage
                    .from('user_files')
                    .createSignedUrl(storagePath, 3600);

                if (error) throw error;
                setPdfUrl(data.signedUrl);
            } catch (err) {
                console.error('Thumbnail URL error:', err);
                setError(true);
            }
        };

        fetchUrl();
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
