/**
 * Thumbnail Cache Service
 * 
 * Browser Cache API-based thumbnail caching for faster library browsing.
 * Simple and lightweight compared to IndexedDB approach.
 */

const CACHE_NAME = 'pdf-thumbnails-v1';
const CACHE_TTL_DAYS = 7;
// Cache API requires valid URL scheme - use a fake https URL
const CACHE_URL_PREFIX = 'https://thumbnail.cache.local/';

class ThumbnailCacheService {
    /**
     * Convert storage path to valid cache URL
     */
    private toCacheUrl(storagePath: string): string {
        // Encode the path to handle special characters
        return `${CACHE_URL_PREFIX}${encodeURIComponent(storagePath)}`;
    }

    /**
     * Get cached thumbnail blob
     */
    async getCachedThumbnail(cacheKey: string): Promise<Blob | null> {
        try {
            const cache = await caches.open(CACHE_NAME);
            const cacheUrl = this.toCacheUrl(cacheKey);
            const response = await cache.match(cacheUrl);

            if (!response) {
                console.log('[ThumbnailCache] Cache miss:', cacheKey);
                return null;
            }

            // Check if expired
            const cachedAt = response.headers.get('X-Cached-At');
            if (cachedAt) {
                const cacheAge = Date.now() - parseInt(cachedAt, 10);
                const maxAge = CACHE_TTL_DAYS * 24 * 60 * 60 * 1000;

                if (cacheAge > maxAge) {
                    console.log('[ThumbnailCache] Cache expired:', cacheKey);
                    await cache.delete(cacheUrl);
                    return null;
                }
            }

            console.log('[ThumbnailCache] ✅ Cache hit:', cacheKey);
            return await response.blob();
        } catch (error) {
            console.error('[ThumbnailCache] getCachedThumbnail error:', error);
            return null; // Gracefully degrade to network
        }
    }

    /**
     * Cache thumbnail blob
     */
    async cacheThumbnail(cacheKey: string, blob: Blob): Promise<void> {
        try {
            const cache = await caches.open(CACHE_NAME);
            const cacheUrl = this.toCacheUrl(cacheKey);

            // Create response with custom header for expiration tracking
            const headers = new Headers({
                'Content-Type': blob.type || 'application/pdf',
                'X-Cached-At': Date.now().toString(),
            });

            const response = new Response(blob, { headers });

            await cache.put(cacheUrl, response);
            console.log('[ThumbnailCache] ✅ Cached:', cacheKey);
        } catch (error) {
            console.error('[ThumbnailCache] cacheThumbnail error:', error);
            // Don't throw - caching failure shouldn't break the app
        }
    }

    /**
     * Clear all cached thumbnails
     */
    async clearCache(): Promise<void> {
        try {
            const deleted = await caches.delete(CACHE_NAME);
            if (deleted) {
                console.log('[ThumbnailCache] Cache cleared');
            } else {
                console.log('[ThumbnailCache] No cache to clear');
            }
        } catch (error) {
            console.error('[ThumbnailCache] clearCache error:', error);
        }
    }

    /**
     * Remove specific cached thumbnail
     */
    async removeCached(cacheKey: string): Promise<void> {
        try {
            const cache = await caches.open(CACHE_NAME);
            const cacheUrl = this.toCacheUrl(cacheKey);
            const deleted = await cache.delete(cacheUrl);
            if (deleted) {
                console.log('[ThumbnailCache] Removed:', cacheKey);
            }
        } catch (error) {
            console.error('[ThumbnailCache] removeCached error:', error);
        }
    }
}

// Singleton instance
export const thumbnailCache = new ThumbnailCacheService();
