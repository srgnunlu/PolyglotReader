'use client';

import { useState, useRef, useCallback } from 'react';
import { getSupabase, getAccessToken } from '@/lib/supabase';
import { useToast } from '@/contexts/ToastContext';

interface FileUploadProps {
    onUploadComplete: () => void;
}

const MAX_FILE_SIZE = 50 * 1024 * 1024; // 50MB

export function FileUpload({ onUploadComplete }: FileUploadProps) {
    const [isUploading, setIsUploading] = useState(false);
    const [progress, setProgress] = useState(0);
    const [isDragOver, setIsDragOver] = useState(false);
    const [showModal, setShowModal] = useState(false);
    const fileInputRef = useRef<HTMLInputElement>(null);
    const { showToast } = useToast();

    const uploadFile = useCallback(async (file: File) => {
        if (file.type !== 'application/pdf') {
            showToast('Sadece PDF dosyaları yüklenebilir', 'error');
            return;
        }
        if (file.size > MAX_FILE_SIZE) {
            showToast('Dosya boyutu 50MB\'dan büyük olamaz', 'error');
            return;
        }

        setIsUploading(true);
        setProgress(10);

        try {
            const supabase = getSupabase();
            const { data: { user } } = await supabase.auth.getUser();
            if (!user) throw new Error('Giriş yapılmamış');

            setProgress(20);

            // Upload to Supabase Storage
            const storagePath = `${user.id}/${Date.now()}_${file.name}`;
            const { error: uploadError } = await supabase.storage
                .from('user_files')
                .upload(storagePath, file, {
                    contentType: 'application/pdf',
                    upsert: false,
                });

            if (uploadError) throw uploadError;
            setProgress(70);

            // Create file record in database
            const { error: dbError } = await supabase
                .from('files')
                .insert({
                    user_id: user.id,
                    name: file.name,
                    storage_path: storagePath,
                    file_type: 'pdf',
                    size: file.size,
                });

            if (dbError) throw dbError;
            setProgress(100);

            showToast(`"${file.name}" başarıyla yüklendi`, 'success');
            setShowModal(false);
            onUploadComplete();
        } catch (err) {
            console.error('Upload error:', err);
            showToast('Dosya yüklenirken hata oluştu', 'error');
        } finally {
            setIsUploading(false);
            setProgress(0);
        }
    }, [onUploadComplete, showToast]);

    const handleDrop = useCallback((e: React.DragEvent) => {
        e.preventDefault();
        setIsDragOver(false);
        const file = e.dataTransfer.files[0];
        if (file) uploadFile(file);
    }, [uploadFile]);

    const handleFileSelect = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
        const file = e.target.files?.[0];
        if (file) uploadFile(file);
        e.target.value = '';
    }, [uploadFile]);

    return (
        <>
            <button
                onClick={() => setShowModal(true)}
                style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 8,
                    padding: '10px 20px',
                    background: 'linear-gradient(135deg, var(--color-primary-500), var(--color-primary-600))',
                    color: 'white',
                    border: 'none',
                    borderRadius: 12,
                    cursor: 'pointer',
                    fontWeight: 600,
                    fontSize: '0.875rem',
                    transition: 'all 0.2s ease',
                    boxShadow: '0 2px 8px rgba(99,102,241,0.3)',
                }}
            >
                + Dosya Yükle
            </button>

            {showModal && (
                <div
                    style={{
                        position: 'fixed',
                        inset: 0,
                        zIndex: 1000,
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        background: 'rgba(0,0,0,0.5)',
                        backdropFilter: 'blur(4px)',
                    }}
                    onClick={(e) => { if (e.target === e.currentTarget && !isUploading) setShowModal(false); }}
                >
                    <div
                        style={{
                            background: 'var(--bg-secondary, white)',
                            borderRadius: 20,
                            padding: 32,
                            width: '90%',
                            maxWidth: 480,
                            boxShadow: '0 24px 48px rgba(0,0,0,0.2)',
                            animation: 'toastSlideIn 0.3s ease',
                        }}
                    >
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 24 }}>
                            <h2 style={{ fontSize: '1.25rem', fontWeight: 700, color: 'var(--text-primary)' }}>
                                PDF Yükle
                            </h2>
                            {!isUploading && (
                                <button
                                    onClick={() => setShowModal(false)}
                                    style={{
                                        background: 'none', border: 'none', cursor: 'pointer',
                                        color: 'var(--text-tertiary)', fontSize: '1.5rem',
                                    }}
                                >
                                    &times;
                                </button>
                            )}
                        </div>

                        <div
                            onDragOver={(e) => { e.preventDefault(); setIsDragOver(true); }}
                            onDragLeave={() => setIsDragOver(false)}
                            onDrop={handleDrop}
                            onClick={() => !isUploading && fileInputRef.current?.click()}
                            style={{
                                border: `2px dashed ${isDragOver ? 'var(--color-primary-500)' : 'var(--border-color, #e5e7eb)'}`,
                                borderRadius: 16,
                                padding: '48px 24px',
                                textAlign: 'center',
                                cursor: isUploading ? 'default' : 'pointer',
                                background: isDragOver ? 'rgba(99,102,241,0.05)' : 'transparent',
                                transition: 'all 0.2s ease',
                            }}
                        >
                            {isUploading ? (
                                <div>
                                    <div style={{
                                        width: '100%', height: 6, borderRadius: 3,
                                        background: 'var(--bg-tertiary, #f3f4f6)',
                                        overflow: 'hidden', marginBottom: 12,
                                    }}>
                                        <div style={{
                                            width: `${progress}%`, height: '100%',
                                            background: 'linear-gradient(90deg, var(--color-primary-500), var(--color-primary-400))',
                                            borderRadius: 3, transition: 'width 0.3s ease',
                                        }} />
                                    </div>
                                    <p style={{ color: 'var(--text-secondary)', fontSize: '0.875rem' }}>
                                        Yükleniyor... %{progress}
                                    </p>
                                </div>
                            ) : (
                                <>
                                    <div style={{ fontSize: '2.5rem', marginBottom: 12 }}>
                                        {isDragOver ? '📥' : '📄'}
                                    </div>
                                    <p style={{ color: 'var(--text-primary)', fontWeight: 600, marginBottom: 4 }}>
                                        PDF dosyanızı sürükleyin
                                    </p>
                                    <p style={{ color: 'var(--text-tertiary)', fontSize: '0.85rem' }}>
                                        veya tıklayarak seçin (maks. 50MB)
                                    </p>
                                </>
                            )}
                        </div>

                        <input
                            ref={fileInputRef}
                            type="file"
                            accept="application/pdf"
                            onChange={handleFileSelect}
                            style={{ display: 'none' }}
                        />
                    </div>
                </div>
            )}
        </>
    );
}
