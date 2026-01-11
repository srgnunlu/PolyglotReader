import Foundation
import UIKit

// MARK: - Cache Service
/// Centralized caching service with NSCache for automatic memory management.
/// Provides separate caches for thumbnails, PDF pages, and images with LRU eviction.
final class CacheService {
    static let shared = CacheService()

    // MARK: - Cache Types

    /// Thumbnail cache for library view (stores Data for thumbnails)
    let thumbnailCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.name = "ThumbnailCache"
        cache.countLimit = 100  // Max 100 thumbnails
        cache.totalCostLimit = 50 * 1024 * 1024  // 50MB limit
        return cache
    }()

    /// PDF page cache for pre-rendered pages (stores UIImage)
    let pdfPageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.name = "PDFPageCache"
        cache.countLimit = 20  // Max 20 pages (current + adjacent)
        cache.totalCostLimit = 100 * 1024 * 1024  // 100MB limit
        return cache
    }()

    /// Image cache for chat/annotation images (stores UIImage)
    let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.name = "ImageCache"
        cache.countLimit = 50  // Max 50 images
        cache.totalCostLimit = 50 * 1024 * 1024  // 50MB limit
        return cache
    }()

    // MARK: - Initialization

    private init() {
        setupMemoryWarningObserver()
        logInfo("CacheService", "Cache servisi başlatıldı")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Memory Warning Handling

    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc private func handleMemoryWarning() {
        logWarning("CacheService", "Bellek uyarısı alındı - tüm cache temizleniyor")
        clearAllCaches()
    }

    // MARK: - Thumbnail Cache Methods

    /// Get thumbnail data from cache
    func getThumbnail(forFileId fileId: String) -> Data? {
        thumbnailCache.object(forKey: fileId as NSString) as Data?
    }

    /// Store thumbnail data in cache
    func setThumbnail(_ data: Data, forFileId fileId: String) {
        thumbnailCache.setObject(
            data as NSData,
            forKey: fileId as NSString,
            cost: data.count
        )
    }

    /// Remove thumbnail from cache
    func removeThumbnail(forFileId fileId: String) {
        thumbnailCache.removeObject(forKey: fileId as NSString)
    }

    // MARK: - PDF Page Cache Methods

    /// Create cache key for PDF page
    private func pdfPageKey(fileId: String, pageNumber: Int, scale: CGFloat) -> NSString {
        "\(fileId)_\(pageNumber)_\(Int(scale * 100))" as NSString
    }

    /// Get rendered PDF page from cache
    func getPDFPage(fileId: String, pageNumber: Int, scale: CGFloat = 1.0) -> UIImage? {
        let key = pdfPageKey(fileId: fileId, pageNumber: pageNumber, scale: scale)
        return pdfPageCache.object(forKey: key)
    }

    /// Store rendered PDF page in cache
    func setPDFPage(_ image: UIImage, fileId: String, pageNumber: Int, scale: CGFloat = 1.0) {
        let key = pdfPageKey(fileId: fileId, pageNumber: pageNumber, scale: scale)
        let cost = Int(image.size.width * image.size.height * image.scale * 4)  // Approximate bytes
        pdfPageCache.setObject(image, forKey: key, cost: cost)
    }

    /// Remove all pages for a specific file
    func removePDFPages(forFileId fileId: String) {
        // NSCache doesn't support iteration, so we just clear the whole cache
        // In practice, this is called when closing a document
        pdfPageCache.removeAllObjects()
    }

    // MARK: - Image Cache Methods

    /// Get image from cache
    func getImage(forKey key: String) -> UIImage? {
        imageCache.object(forKey: key as NSString)
    }

    /// Store image in cache
    func setImage(_ image: UIImage, forKey key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * 4)
        imageCache.setObject(image, forKey: key as NSString, cost: cost)
    }

    /// Remove image from cache
    func removeImage(forKey key: String) {
        imageCache.removeObject(forKey: key as NSString)
    }

    // MARK: - Cache Management

    /// Clear all caches
    func clearAllCaches() {
        thumbnailCache.removeAllObjects()
        pdfPageCache.removeAllObjects()
        imageCache.removeAllObjects()
        logInfo("CacheService", "Tüm cache temizlendi")
    }

    /// Clear only PDF page cache (useful when switching documents)
    func clearPDFPageCache() {
        pdfPageCache.removeAllObjects()
        logDebug("CacheService", "PDF page cache temizlendi")
    }

    /// Get cache statistics for debugging
    func getStats() -> CacheStats {
        CacheStats(
            thumbnailCountLimit: thumbnailCache.countLimit,
            thumbnailCostLimit: thumbnailCache.totalCostLimit,
            pdfPageCountLimit: pdfPageCache.countLimit,
            pdfPageCostLimit: pdfPageCache.totalCostLimit,
            imageCountLimit: imageCache.countLimit,
            imageCostLimit: imageCache.totalCostLimit
        )
    }
}

// MARK: - Cache Stats

struct CacheStats {
    let thumbnailCountLimit: Int
    let thumbnailCostLimit: Int
    let pdfPageCountLimit: Int
    let pdfPageCostLimit: Int
    let imageCountLimit: Int
    let imageCostLimit: Int

    var description: String {
        """
        Thumbnail: \(thumbnailCountLimit) items, \(thumbnailCostLimit / 1024 / 1024)MB
        PDF Page: \(pdfPageCountLimit) items, \(pdfPageCostLimit / 1024 / 1024)MB
        Image: \(imageCountLimit) items, \(imageCostLimit / 1024 / 1024)MB
        """
    }
}
