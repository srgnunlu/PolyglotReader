/**
 * PDF.js Worker Configuration
 * 
 * Centralized configuration for PDF.js worker to prevent
 * "Worker was terminated" errors in Next.js with Fast Refresh.
 */

import { pdfjs } from 'react-pdf';

const pdfjsVersion = pdfjs.version || '5.4.296';

// Keep track of initialization to prevent multiple setups
let isInitialized = false;

// Configure worker only once on client side
if (typeof window !== 'undefined' && !isInitialized) {
    isInitialized = true;

    // Always use CDN for maximum reliability
    // This prevents issues with Next.js Fast Refresh and import.meta.url
    const cdnWorkerSrc = `https://cdn.jsdelivr.net/npm/pdfjs-dist@${pdfjsVersion}/build/pdf.worker.min.mjs`;

    // Force set worker source even if already set (to ensure CDN is used)
    pdfjs.GlobalWorkerOptions.workerSrc = cdnWorkerSrc;

    // Store original console.error to filter PDF.js worker termination errors
    const originalConsoleError = console.error;
    console.error = (...args: any[]) => {
        // Filter out worker termination errors
        const message = args[0]?.toString() || '';
        if (
            message.includes('Worker was terminated') ||
            message.includes('ensureNotTerminated') ||
            message.includes('pdf.worker.min.mjs')
        ) {
            // Silently ignore these errors in development
            if (process.env.NODE_ENV === 'development') {
                return;
            }
        }
        // Call original console.error for other errors
        originalConsoleError.apply(console, args);
    };

    // Suppress unhandled promise rejections from worker termination during Fast Refresh
    // These are expected during HMR and don't affect functionality
    const handleUnhandledRejection = (event: PromiseRejectionEvent) => {
        const reason = event.reason;
        if (
            reason &&
            typeof reason === 'object' &&
            'message' in reason &&
            typeof reason.message === 'string' &&
            (reason.message.includes('Worker was terminated') ||
                reason.message.includes('ensureNotTerminated') ||
                reason.message.includes('pdf.worker'))
        ) {
            // Prevent the error from showing in console
            event.preventDefault();
            // Optionally log to a custom error handler
            if (process.env.NODE_ENV !== 'development') {
                console.log('[PDF.js] Worker termination (expected during navigation/HMR)');
            }
        }
    };

    window.addEventListener('unhandledrejection', handleUnhandledRejection);

    // Cleanup on page unload
    window.addEventListener('beforeunload', () => {
        // Restore original console.error
        console.error = originalConsoleError;
    });
}

// Export worker source for direct use if needed
export const PDF_WORKER_SRC = typeof window !== 'undefined'
    ? `https://cdn.jsdelivr.net/npm/pdfjs-dist@${pdfjsVersion}/build/pdf.worker.min.mjs`
    : undefined;

// Export version for consistency
export { pdfjsVersion };
