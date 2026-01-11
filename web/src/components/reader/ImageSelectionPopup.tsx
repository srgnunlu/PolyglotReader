'use client';

import { useState, useEffect, useRef } from 'react';
import styles from './ImageSelectionPopup.module.css';

interface ImageSelectionPopupProps {
    imageBase64: string;
    position: { x: number; y: number };
    onClose: () => void;
    onAskAI: (imageBase64: string) => void;
}

export function ImageSelectionPopup({
    imageBase64,
    position,
    onClose,
    onAskAI,
}: ImageSelectionPopupProps) {
    // Ensure we have a valid data URL
    const imgSrc = imageBase64.startsWith('data:')
        ? imageBase64
        : `data:image/png;base64,${imageBase64}`;

    const [adjustedPosition, setAdjustedPosition] = useState(position);
    const [copySuccess, setCopySuccess] = useState(false);
    const popupRef = useRef<HTMLDivElement>(null);

    // Adjust position to keep popup in viewport
    useEffect(() => {
        if (!popupRef.current) return;

        const popup = popupRef.current;
        const rect = popup.getBoundingClientRect();
        const viewportWidth = window.innerWidth;

        let adjustedX = position.x;
        let adjustedY = position.y;

        // Check horizontal overflow
        if (rect.right > viewportWidth) {
            adjustedX = viewportWidth - rect.width / 2 - 20;
        } else if (rect.left < 0) {
            adjustedX = rect.width / 2 + 20;
        }

        // Check vertical overflow
        if (rect.top < 0) {
            adjustedY = 60;
        }

        setAdjustedPosition({ x: adjustedX, y: adjustedY });
    }, [position]);

    // Close on click outside
    useEffect(() => {
        const handleClickOutside = (e: MouseEvent) => {
            const target = e.target as HTMLElement;
            if (!target.closest(`.${styles.popup}`)) {
                onClose();
            }
        };

        document.addEventListener('mousedown', handleClickOutside);
        return () => document.removeEventListener('mousedown', handleClickOutside);
    }, [onClose]);

    const handleAskAI = () => {
        // Pass original raw base64 to AI if it expects that, or handle stripping if needed.
        // gemini.ts likely expects raw base64 or handles it. 
        // Let's pass the raw base64 (without prefix) which is cleaner for API if we strip it,
        // BUT current prop is named imageBase64.
        // Let's pass what we received (assuming it's raw base64 from PDFViewer).
        // If PDFViewer passed raw base64, we keep passing raw base64.
        onAskAI(imageBase64);
        onClose();
    };

    const handleCopy = async () => {
        try {
            // Convert base64 to blob
            const response = await fetch(imgSrc);
            const blob = await response.blob();

            // Use Clipboard API to copy image
            await navigator.clipboard.write([
                new ClipboardItem({
                    [blob.type]: blob,
                }),
            ]);

            setCopySuccess(true);
            setTimeout(() => {
                setCopySuccess(false);
                onClose();
            }, 1000);
        } catch (err) {
            console.error('Failed to copy image:', err);
            // Fallback: copy as data URL
            try {
                await navigator.clipboard.writeText(imageBase64);
                setCopySuccess(true);
                setTimeout(() => {
                    setCopySuccess(false);
                    onClose();
                }, 1000);
            } catch {
                console.error('Fallback copy also failed');
            }
        }
    };

    return (
        <div
            ref={popupRef}
            className={styles.popup}
            style={{
                left: adjustedPosition.x,
                top: adjustedPosition.y,
            }}
        >
            {/* Image preview */}
            <div className={styles.preview}>
                <img
                    src={imgSrc}
                    alt="Seçili görsel"
                    className={styles.previewImage}
                />
            </div>

            {/* Actions */}
            <div className={styles.actions}>
                <button
                    className={styles.actionBtn}
                    onClick={handleAskAI}
                >
                    <span className={styles.icon}>✨</span>
                    <span>AI&apos;a Sor</span>
                </button>

                <button
                    className={styles.actionBtn}
                    onClick={handleCopy}
                    disabled={copySuccess}
                >
                    <span className={styles.icon}>
                        {copySuccess ? '✓' : '📋'}
                    </span>
                    <span>{copySuccess ? 'Kopyalandı!' : 'Kopyala'}</span>
                </button>
            </div>
        </div>
    );
}
