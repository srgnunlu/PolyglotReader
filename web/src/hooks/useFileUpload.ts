'use client';

import { useState, useCallback } from 'react';
import { getSupabase } from '@/lib/supabase';
import { generatePdfThumbnail } from '@/lib/pdfThumbnail';
import { indexDocumentFile } from '@/lib/indexing';

interface UploadResult {
    succeeded: string[];
    failed: { name: string; error: string }[];
}

// Matches the iOS storage path convention: <userId>/<unixSeconds>_<sanitizedName>
// so storage RLS (first folder segment == auth.uid()) applies to both platforms.
function buildStoragePath(userId: string, fileName: string): string {
    const sanitized = fileName
        .replace(/[^a-zA-Z0-9._-]/g, '_')
        .replace(/_{2,}/g, '_');
    const timestamp = Math.floor(Date.now() / 1000);
    return `${userId.toLowerCase()}/${timestamp}_${sanitized}`;
}

export function useFileUpload() {
    const [isUploading, setIsUploading] = useState(false);
    const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);

    const uploadFiles = useCallback(async (files: File[]): Promise<UploadResult> => {
        const supabase = getSupabase();
        const result: UploadResult = { succeeded: [], failed: [] };

        setIsUploading(true);
        setProgress({ done: 0, total: files.length });

        try {
            const { data: { user } } = await supabase.auth.getUser();
            if (!user) {
                return {
                    succeeded: [],
                    failed: files.map(f => ({ name: f.name, error: 'Oturum bulunamadı' })),
                };
            }

            for (const file of files) {
                const storagePath = buildStoragePath(user.id, file.name);

                try {
                    const { error: storageError } = await supabase.storage
                        .from('user_files')
                        .upload(storagePath, file, { contentType: 'application/pdf' });

                    if (storageError) throw storageError;

                    // Pre-render a small first-page thumbnail so the library grid
                    // never downloads the full PDF just to draw a preview. Best
                    // effort — a null result simply falls back to live rendering.
                    const thumbnailBase64 = await generatePdfThumbnail(file);

                    const { data: inserted, error: insertError } = await supabase
                        .from('files')
                        .insert({
                            user_id: user.id,
                            name: file.name,
                            storage_path: storagePath,
                            file_type: 'pdf',
                            size: file.size,
                            thumbnail_base64: thumbnailBase64,
                        })
                        .select('id')
                        .single();

                    if (insertError) {
                        // Don't leave an orphaned object behind if metadata insert fails
                        await supabase.storage.from('user_files').remove([storagePath]);
                        throw insertError;
                    }

                    // Fire-and-forget RAG indexing so the document is chatable
                    // without needing to be opened on iOS first. Failure is
                    // non-fatal: chat falls back to broad context until the
                    // document gets indexed elsewhere.
                    if (inserted?.id) {
                        indexDocumentFile(file, inserted.id).catch(err =>
                            console.error('Background indexing failed:', err)
                        );
                    }

                    result.succeeded.push(file.name);
                } catch (err) {
                    result.failed.push({
                        name: file.name,
                        error: err instanceof Error ? err.message : 'Yükleme başarısız',
                    });
                } finally {
                    setProgress(prev =>
                        prev ? { ...prev, done: prev.done + 1 } : prev
                    );
                }
            }

            return result;
        } finally {
            setIsUploading(false);
            setProgress(null);
        }
    }, []);

    return { uploadFiles, isUploading, progress };
}
