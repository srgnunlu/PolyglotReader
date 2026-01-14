/**
 * PDF Cache Service
 * 
 * IndexedDB-based client-side cache for PDF files to reduce Supabase egress.
 * Implements cache-first strategy with LRU eviction and automatic cleanup.
 * 
 * Similar to iOS PDFCacheService but using browser IndexedDB instead of FileSystem.
 */

const DB_NAME = 'pdf-cache-db';
const STORE_NAME = 'pdfs';
const DB_VERSION = 1;
const MAX_CACHE_SIZE = 500 * 1024 * 1024; // 500 MB
const CACHE_EXPIRATION_DAYS = 7;

interface CachedPDF {
    storagePath: string;      // Primary key
    blob: Blob;               // PDF file data
    cachedAt: number;         // Timestamp when cached
    lastAccessed: number;     // Timestamp for LRU
    size: number;             // File size in bytes
}

interface CacheStats {
    fileCount: number;
    totalSize: number;
    maxSize: number;
    usagePercentage: number;
}

class PDFCacheService {
    private dbPromise: Promise<IDBDatabase> | null = null;

    constructor() {
        this.initDB();
    }

    /**
     * Initialize IndexedDB database
     */
    private initDB(): Promise<IDBDatabase> {
        if (this.dbPromise) return this.dbPromise;

        this.dbPromise = new Promise((resolve, reject) => {
            const request = indexedDB.open(DB_NAME, DB_VERSION);

            request.onerror = () => {
                console.error('[PDFCache] Failed to open database:', request.error);
                reject(request.error);
            };

            request.onsuccess = () => {
                console.log('[PDFCache] Database opened successfully');
                resolve(request.result);
            };

            request.onupgradeneeded = (event) => {
                const db = (event.target as IDBOpenDBRequest).result;

                // Create object store if it doesn't exist
                if (!db.objectStoreNames.contains(STORE_NAME)) {
                    const store = db.createObjectStore(STORE_NAME, { keyPath: 'storagePath' });
                    store.createIndex('lastAccessed', 'lastAccessed', { unique: false });
                    store.createIndex('cachedAt', 'cachedAt', { unique: false });
                    console.log('[PDFCache] Object store created');
                }
            };
        });

        return this.dbPromise;
    }

    /**
     * Get cached PDF blob
     * Returns null if not cached or error occurs
     */
    async getCachedPDF(storagePath: string): Promise<Blob | null> {
        try {
            const db = await this.initDB();
            const tx = db.transaction(STORE_NAME, 'readwrite');
            const store = tx.objectStore(STORE_NAME);

            return new Promise((resolve, reject) => {
                const request = store.get(storagePath);

                request.onsuccess = () => {
                    const cached = request.result as CachedPDF | undefined;

                    if (!cached) {
                        console.log('[PDFCache] Cache miss:', storagePath);
                        resolve(null);
                        return;
                    }

                    // Check if expired
                    const now = Date.now();
                    const expirationMs = CACHE_EXPIRATION_DAYS * 24 * 60 * 60 * 1000;
                    if (now - cached.cachedAt > expirationMs) {
                        console.log('[PDFCache] Cache expired:', storagePath);
                        // Remove expired entry
                        store.delete(storagePath);
                        resolve(null);
                        return;
                    }

                    // Update last accessed time for LRU
                    cached.lastAccessed = now;
                    store.put(cached);

                    const sizeKB = (cached.size / 1024).toFixed(2);
                    console.log(`[PDFCache] ✅ Cache hit: ${storagePath} (${sizeKB} KB)`);
                    resolve(cached.blob);
                };

                request.onerror = () => {
                    console.error('[PDFCache] Error reading from cache:', request.error);
                    reject(request.error);
                };
            });
        } catch (error) {
            console.error('[PDFCache] getCachedPDF error:', error);
            return null; // Gracefully degrade to network
        }
    }

    /**
     * Cache PDF blob
     */
    async cachePDF(blob: Blob, storagePath: string): Promise<void> {
        try {
            const size = blob.size;

            // Check if we need to evict
            const stats = await this.getCacheStats();
            if (stats.totalSize + size > MAX_CACHE_SIZE) {
                console.log('[PDFCache] Cache full, evicting LRU items...');
                await this.evictLRU(size);
            }

            const db = await this.initDB();
            const tx = db.transaction(STORE_NAME, 'readwrite');
            const store = tx.objectStore(STORE_NAME);

            const cached: CachedPDF = {
                storagePath,
                blob,
                cachedAt: Date.now(),
                lastAccessed: Date.now(),
                size,
            };

            return new Promise((resolve, reject) => {
                const request = store.put(cached);

                request.onsuccess = () => {
                    const sizeKB = (size / 1024).toFixed(2);
                    console.log(`[PDFCache] ✅ Cached: ${storagePath} (${sizeKB} KB)`);
                    resolve();
                };

                request.onerror = () => {
                    console.error('[PDFCache] Error caching PDF:', request.error);
                    reject(request.error);
                };
            });
        } catch (error) {
            console.error('[PDFCache] cachePDF error:', error);
            // Don't throw - caching failure shouldn't break the app
        }
    }

    /**
     * Remove specific cached PDF
     */
    async removeCached(storagePath: string): Promise<void> {
        try {
            const db = await this.initDB();
            const tx = db.transaction(STORE_NAME, 'readwrite');
            const store = tx.objectStore(STORE_NAME);

            return new Promise((resolve, reject) => {
                const request = store.delete(storagePath);

                request.onsuccess = () => {
                    console.log('[PDFCache] Removed:', storagePath);
                    resolve();
                };

                request.onerror = () => {
                    console.error('[PDFCache] Error removing cached PDF:', request.error);
                    reject(request.error);
                };
            });
        } catch (error) {
            console.error('[PDFCache] removeCached error:', error);
        }
    }

    /**
     * Clear all cached PDFs
     */
    async clearCache(): Promise<void> {
        try {
            const db = await this.initDB();
            const tx = db.transaction(STORE_NAME, 'readwrite');
            const store = tx.objectStore(STORE_NAME);

            return new Promise((resolve, reject) => {
                const request = store.clear();

                request.onsuccess = () => {
                    console.log('[PDFCache] Cache cleared');
                    resolve();
                };

                request.onerror = () => {
                    console.error('[PDFCache] Error clearing cache:', request.error);
                    reject(request.error);
                };
            });
        } catch (error) {
            console.error('[PDFCache] clearCache error:', error);
        }
    }

    /**
     * Get cache statistics
     */
    async getCacheStats(): Promise<CacheStats> {
        try {
            const db = await this.initDB();
            const tx = db.transaction(STORE_NAME, 'readonly');
            const store = tx.objectStore(STORE_NAME);

            return new Promise((resolve, reject) => {
                const request = store.getAll();

                request.onsuccess = () => {
                    const items = request.result as CachedPDF[];
                    const totalSize = items.reduce((sum, item) => sum + item.size, 0);
                    const usagePercentage = (totalSize / MAX_CACHE_SIZE) * 100;

                    resolve({
                        fileCount: items.length,
                        totalSize,
                        maxSize: MAX_CACHE_SIZE,
                        usagePercentage,
                    });
                };

                request.onerror = () => {
                    console.error('[PDFCache] Error getting stats:', request.error);
                    reject(request.error);
                };
            });
        } catch (error) {
            console.error('[PDFCache] getCacheStats error:', error);
            return {
                fileCount: 0,
                totalSize: 0,
                maxSize: MAX_CACHE_SIZE,
                usagePercentage: 0,
            };
        }
    }

    /**
     * Evict least recently used files to free space
     */
    private async evictLRU(bytesNeeded: number): Promise<void> {
        try {
            const db = await this.initDB();
            const tx = db.transaction(STORE_NAME, 'readwrite');
            const store = tx.objectStore(STORE_NAME);
            const index = store.index('lastAccessed');

            return new Promise((resolve, reject) => {
                const request = index.openCursor();
                let freedBytes = 0;

                request.onsuccess = (event) => {
                    const cursor = (event.target as IDBRequest).result as IDBCursorWithValue | null;

                    if (!cursor || freedBytes >= bytesNeeded) {
                        console.log(`[PDFCache] Evicted ${freedBytes} bytes`);
                        resolve();
                        return;
                    }

                    const cached = cursor.value as CachedPDF;
                    freedBytes += cached.size;

                    cursor.delete();
                    console.log(`[PDFCache] Evicted: ${cached.storagePath}`);

                    cursor.continue();
                };

                request.onerror = () => {
                    console.error('[PDFCache] Error during LRU eviction:', request.error);
                    reject(request.error);
                };
            });
        } catch (error) {
            console.error('[PDFCache] evictLRU error:', error);
        }
    }

    /**
     * Log cache statistics to console
     */
    async logStats(): Promise<void> {
        const stats = await this.getCacheStats();
        const totalMB = (stats.totalSize / 1024 / 1024).toFixed(2);
        const maxMB = (stats.maxSize / 1024 / 1024).toFixed(2);
        console.log(
            `[PDFCache] Stats: ${stats.fileCount} files | ${totalMB} MB / ${maxMB} MB (${stats.usagePercentage.toFixed(1)}%)`
        );
    }
}

// Singleton instance
export const pdfCache = new PDFCacheService();

// Export types
export type { CacheStats };
