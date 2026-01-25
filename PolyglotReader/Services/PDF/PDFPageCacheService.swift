import Foundation
import UIKit
import CryptoKit

// MARK: - PDF Page Cache Service
/// Disk-based cache for rendered PDF page images.
/// Enables instant PDF opening by caching the first few pages as JPEG images.
/// Similar strategy to Apple Books and Kindle for instant page display.
final class PDFPageCacheService {
    static let shared = PDFPageCacheService()

    // MARK: - Configuration

    /// Maximum cache size in bytes (200MB for page images)
    private let maxCacheSize: Int64 = 200 * 1024 * 1024

    /// Cache expiration time (14 days - longer than PDF cache since images are smaller)
    private let cacheExpirationDays: Int = 14

    /// JPEG compression quality (0.0 - 1.0)
    private let jpegQuality: CGFloat = 0.85

    /// Maximum pages to cache per document
    private let maxPagesPerDocument: Int = 3

    /// Cache directory name
    private let cacheDirectoryName = "PDFPageCache"

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let cacheQueue = DispatchQueue(label: "com.polyglotreader.pagecache", qos: .utility)

    private lazy var cacheDirectory: URL? = {
        guard let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            logWarning("PDFPageCacheService", "Caches dizini bulunamadı")
            return nil
        }
        let pageCacheDir = cachesDir.appendingPathComponent(cacheDirectoryName)

        // Create directory if needed
        if !fileManager.fileExists(atPath: pageCacheDir.path) {
            do {
                try fileManager.createDirectory(at: pageCacheDir, withIntermediateDirectories: true)
                logInfo("PDFPageCacheService", "Page cache dizini oluşturuldu", details: pageCacheDir.path)
            } catch {
                logWarning("PDFPageCacheService", "Page cache dizini oluşturulamadı", details: error.localizedDescription)
                return nil
            }
        }
        return pageCacheDir
    }()

    // MARK: - Initialization

    private init() {
        logInfo("PDFPageCacheService", "PDF Page Cache Servisi başlatıldı")
        scheduleCleanup()
    }

    // MARK: - Public Methods

    /// Check if page image is cached
    func isCached(fileId: String, pageNumber: Int) -> Bool {
        guard let cacheURL = getCacheURL(for: fileId, pageNumber: pageNumber) else { return false }
        return fileManager.fileExists(atPath: cacheURL.path)
    }

    /// Get cached page image (returns nil if not cached)
    func getCachedPageImage(fileId: String, pageNumber: Int) -> UIImage? {
        guard let cacheURL = getCacheURL(for: fileId, pageNumber: pageNumber) else { return nil }

        guard fileManager.fileExists(atPath: cacheURL.path) else {
            logDebug("PDFPageCacheService", "Page cache miss", details: "File: \(fileId), Page: \(pageNumber)")
            return nil
        }

        do {
            let data = try Data(contentsOf: cacheURL)
            guard let image = UIImage(data: data) else {
                logWarning("PDFPageCacheService", "Geçersiz image data", details: cacheURL.path)
                // Remove corrupted cache file
                try? fileManager.removeItem(at: cacheURL)
                return nil
            }

            // Update access time for LRU
            updateAccessTime(for: cacheURL)
            logInfo("PDFPageCacheService", "Page cache hit ✓", details: "File: \(fileId), Page: \(pageNumber)")
            return image
        } catch {
            logWarning("PDFPageCacheService", "Page cache okuma hatası", details: error.localizedDescription)
            return nil
        }
    }

    /// Cache page image to disk
    func cachePageImage(_ image: UIImage, fileId: String, pageNumber: Int) {
        guard pageNumber <= maxPagesPerDocument else {
            logDebug("PDFPageCacheService", "Sayfa limiti aşıldı, cache atlanıyor", details: "Page: \(pageNumber)")
            return
        }

        guard let cacheURL = getCacheURL(for: fileId, pageNumber: pageNumber) else { return }

        cacheQueue.async { [weak self] in
            guard let self = self else { return }

            // Convert to JPEG data
            guard let jpegData = image.jpegData(compressionQuality: self.jpegQuality) else {
                logWarning("PDFPageCacheService", "JPEG dönüşümü başarısız")
                return
            }

            do {
                // Check disk space before caching
                if self.shouldEvictForSpace(newFileSize: Int64(jpegData.count)) {
                    self.evictLRU(toFreeBytes: Int64(jpegData.count))
                }

                try jpegData.write(to: cacheURL, options: .atomic)
                logInfo("PDFPageCacheService", "Page cached ✓", details: "File: \(fileId), Page: \(pageNumber), Size: \(ByteCountFormatter.string(fromByteCount: Int64(jpegData.count), countStyle: .file))")
            } catch {
                logWarning("PDFPageCacheService", "Page cache yazma hatası", details: error.localizedDescription)
            }
        }
    }

    /// Remove cached pages for a specific file
    func removeCachedPages(for fileId: String) {
        guard let cacheDir = cacheDirectory else { return }
        let prefix = generateFilePrefix(fileId)

        cacheQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                let files = try self.fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
                var deletedCount = 0

                for file in files {
                    if file.lastPathComponent.hasPrefix(prefix) {
                        try self.fileManager.removeItem(at: file)
                        deletedCount += 1
                    }
                }

                if deletedCount > 0 {
                    logDebug("PDFPageCacheService", "File pages cache silindi", details: "FileId: \(fileId), \(deletedCount) sayfa")
                }
            } catch {
                logWarning("PDFPageCacheService", "Page cache silme hatası", details: error.localizedDescription)
            }
        }
    }

    /// Clear all cached pages
    func clearAll() {
        guard let cacheDir = cacheDirectory else { return }

        cacheQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                let files = try self.fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
                for file in files {
                    try self.fileManager.removeItem(at: file)
                }
                logInfo("PDFPageCacheService", "Tüm page cache temizlendi", details: "\(files.count) dosya silindi")
            } catch {
                logWarning("PDFPageCacheService", "Page cache temizleme hatası", details: error.localizedDescription)
            }
        }
    }

    /// Get cache statistics
    func getCacheStats() -> PageCacheStatistics {
        guard let cacheDir = cacheDirectory else {
            return PageCacheStatistics(fileCount: 0, totalSize: 0, maxSize: maxCacheSize)
        }

        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey])
            var totalSize: Int64 = 0

            for file in files {
                let attributes = try file.resourceValues(forKeys: [.fileSizeKey])
                totalSize += Int64(attributes.fileSize ?? 0)
            }

            return PageCacheStatistics(fileCount: files.count, totalSize: totalSize, maxSize: maxCacheSize)
        } catch {
            return PageCacheStatistics(fileCount: 0, totalSize: 0, maxSize: maxCacheSize)
        }
    }

    // MARK: - Private Methods

    /// Generate file prefix for a document
    private func generateFilePrefix(_ fileId: String) -> String {
        let hash = SHA256.hash(data: Data(fileId.utf8))
        return hash.prefix(16).compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Generate cache URL for a specific page
    private func getCacheURL(for fileId: String, pageNumber: Int) -> URL? {
        guard let cacheDir = cacheDirectory else { return nil }

        let prefix = generateFilePrefix(fileId)
        let filename = "\(prefix)_page\(pageNumber).jpg"

        return cacheDir.appendingPathComponent(filename)
    }

    /// Update file access time for LRU tracking
    private func updateAccessTime(for url: URL) {
        cacheQueue.async { [weak self] in
            do {
                try self?.fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            } catch {
                // Ignore - not critical
            }
        }
    }

    /// Check if we need to evict files to make room
    private func shouldEvictForSpace(newFileSize: Int64) -> Bool {
        let stats = getCacheStats()
        return (stats.totalSize + newFileSize) > maxCacheSize
    }

    /// Evict least recently used files to free space
    private func evictLRU(toFreeBytes bytesNeeded: Int64) {
        guard let cacheDir = cacheDirectory else { return }

        do {
            let files = try fileManager.contentsOfDirectory(
                at: cacheDir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            )

            // Sort by modification date (oldest first = LRU)
            let sortedFiles = files.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return date1 < date2
            }

            var freedBytes: Int64 = 0
            for file in sortedFiles {
                guard freedBytes < bytesNeeded else { break }

                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    try fileManager.removeItem(at: file)
                    freedBytes += Int64(size)
                    logDebug("PDFPageCacheService", "LRU eviction", details: file.lastPathComponent)
                }
            }

            logInfo("PDFPageCacheService", "LRU temizleme tamamlandı", details: ByteCountFormatter.string(fromByteCount: freedBytes, countStyle: .file))
        } catch {
            logWarning("PDFPageCacheService", "LRU eviction hatası", details: error.localizedDescription)
        }
    }

    /// Schedule periodic cleanup of old files
    private func scheduleCleanup() {
        cacheQueue.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.cleanupExpiredFiles()
        }
    }

    /// Remove files older than expiration time
    private func cleanupExpiredFiles() {
        guard let cacheDir = cacheDirectory else { return }

        let expirationDate = Calendar.current.date(byAdding: .day, value: -cacheExpirationDays, to: Date()) ?? Date.distantPast

        do {
            let files = try fileManager.contentsOfDirectory(
                at: cacheDir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )

            var deletedCount = 0
            for file in files {
                if let modDate = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   modDate < expirationDate {
                    try fileManager.removeItem(at: file)
                    deletedCount += 1
                }
            }

            if deletedCount > 0 {
                logInfo("PDFPageCacheService", "Eski sayfa görselleri temizlendi", details: "\(deletedCount) dosya (\(cacheExpirationDays) günden eski)")
            }
        } catch {
            logWarning("PDFPageCacheService", "Temizleme hatası", details: error.localizedDescription)
        }
    }
}

// MARK: - Page Cache Statistics

struct PageCacheStatistics {
    let fileCount: Int
    let totalSize: Int64
    let maxSize: Int64

    var usagePercentage: Double {
        guard maxSize > 0 else { return 0 }
        return Double(totalSize) / Double(maxSize) * 100
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    var formattedMaxSize: String {
        ByteCountFormatter.string(fromByteCount: maxSize, countStyle: .file)
    }

    var description: String {
        "\(fileCount) sayfa, \(formattedTotalSize) / \(formattedMaxSize) (\(String(format: "%.1f", usagePercentage))%)"
    }
}
