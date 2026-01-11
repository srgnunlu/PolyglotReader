import Foundation
import CryptoKit

// MARK: - PDF Cache Service
/// Disk-based PDF caching service using FileManager.
/// Implements cache-first strategy with LRU eviction and automatic cleanup.
/// Similar to professional apps like Apple Books, Kindle, and PDF Expert.
final class PDFCacheService {
    static let shared = PDFCacheService()
    
    // MARK: - Configuration
    
    /// Maximum cache size in bytes (500MB)
    private let maxCacheSize: Int64 = 500 * 1024 * 1024
    
    /// Cache expiration time (7 days)
    private let cacheExpirationDays: Int = 7
    
    /// Cache directory name
    private let cacheDirectoryName = "PDFCache"
    
    // MARK: - Properties
    
    private let fileManager = FileManager.default
    private let cacheQueue = DispatchQueue(label: "com.polyglotreader.pdfcache", qos: .utility)
    
    private lazy var cacheDirectory: URL? = {
        guard let cachesDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            logWarning("PDFCacheService", "Caches dizini bulunamadı")
            return nil
        }
        let pdfCacheDir = cachesDir.appendingPathComponent(cacheDirectoryName)
        
        // Create directory if needed
        if !fileManager.fileExists(atPath: pdfCacheDir.path) {
            do {
                try fileManager.createDirectory(at: pdfCacheDir, withIntermediateDirectories: true)
                logInfo("PDFCacheService", "Cache dizini oluşturuldu", details: pdfCacheDir.path)
            } catch {
                logWarning("PDFCacheService", "Cache dizini oluşturulamadı", details: error.localizedDescription)
                return nil
            }
        }
        return pdfCacheDir
    }()
    
    // MARK: - Initialization
    
    private init() {
        logInfo("PDFCacheService", "PDF Cache Servisi başlatıldı")
        // Arka planda eski dosyaları temizle
        scheduleCleanup()
    }
    
    // MARK: - Public Methods
    
    /// Check if PDF is cached
    func isCached(storagePath: String) -> Bool {
        guard let cacheURL = getCacheURL(for: storagePath) else { return false }
        return fileManager.fileExists(atPath: cacheURL.path)
    }
    
    /// Get cached PDF data (returns nil if not cached)
    func getCachedPDF(for storagePath: String) -> Data? {
        guard let cacheURL = getCacheURL(for: storagePath) else { return nil }
        
        guard fileManager.fileExists(atPath: cacheURL.path) else {
            logDebug("PDFCacheService", "Cache miss", details: storagePath)
            return nil
        }
        
        do {
            let data = try Data(contentsOf: cacheURL)
            // Update access time for LRU
            updateAccessTime(for: cacheURL)
            logInfo("PDFCacheService", "Cache hit ✓", details: "\(storagePath) - \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
            return data
        } catch {
            logWarning("PDFCacheService", "Cache okuma hatası", details: error.localizedDescription)
            return nil
        }
    }
    
    /// Cache PDF data to disk
    func cachePDF(_ data: Data, for storagePath: String) {
        guard let cacheURL = getCacheURL(for: storagePath) else { return }
        
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                // Check disk space before caching
                if self.shouldEvictForSpace(newFileSize: Int64(data.count)) {
                    self.evictLRU(toFreeBytes: Int64(data.count))
                }
                
                try data.write(to: cacheURL, options: .atomic)
                logInfo("PDFCacheService", "PDF cached ✓", details: "\(storagePath) - \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
            } catch {
                logWarning("PDFCacheService", "Cache yazma hatası", details: error.localizedDescription)
            }
        }
    }
    
    /// Remove cached PDF
    func removeCachedPDF(for storagePath: String) {
        guard let cacheURL = getCacheURL(for: storagePath) else { return }
        
        do {
            if fileManager.fileExists(atPath: cacheURL.path) {
                try fileManager.removeItem(at: cacheURL)
                logDebug("PDFCacheService", "Cache silindi", details: storagePath)
            }
        } catch {
            logWarning("PDFCacheService", "Cache silme hatası", details: error.localizedDescription)
        }
    }
    
    /// Clear all cached PDFs
    func clearAll() {
        guard let cacheDir = cacheDirectory else { return }
        
        cacheQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let files = try self.fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
                for file in files {
                    try self.fileManager.removeItem(at: file)
                }
                logInfo("PDFCacheService", "Tüm cache temizlendi", details: "\(files.count) dosya silindi")
            } catch {
                logWarning("PDFCacheService", "Cache temizleme hatası", details: error.localizedDescription)
            }
        }
    }
    
    /// Get cache statistics
    func getCacheStats() -> CacheStatistics {
        guard let cacheDir = cacheDirectory else {
            return CacheStatistics(fileCount: 0, totalSize: 0, maxSize: maxCacheSize)
        }
        
        do {
            let files = try fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.fileSizeKey])
            var totalSize: Int64 = 0
            
            for file in files {
                let attributes = try file.resourceValues(forKeys: [.fileSizeKey])
                totalSize += Int64(attributes.fileSize ?? 0)
            }
            
            return CacheStatistics(fileCount: files.count, totalSize: totalSize, maxSize: maxCacheSize)
        } catch {
            return CacheStatistics(fileCount: 0, totalSize: 0, maxSize: maxCacheSize)
        }
    }
    
    // MARK: - Private Methods
    
    /// Generate cache URL from storage path using SHA256 hash
    private func getCacheURL(for storagePath: String) -> URL? {
        guard let cacheDir = cacheDirectory else { return nil }
        
        // Create SHA256 hash of the storage path for unique filename
        let hash = SHA256.hash(data: Data(storagePath.utf8))
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        return cacheDir.appendingPathComponent("\(hashString).pdf")
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
                    logDebug("PDFCacheService", "LRU eviction", details: file.lastPathComponent)
                }
            }
            
            logInfo("PDFCacheService", "LRU temizleme tamamlandı", details: ByteCountFormatter.string(fromByteCount: freedBytes, countStyle: .file))
        } catch {
            logWarning("PDFCacheService", "LRU eviction hatası", details: error.localizedDescription)
        }
    }
    
    /// Schedule periodic cleanup of old files
    private func scheduleCleanup() {
        cacheQueue.asyncAfter(deadline: .now() + 5) { [weak self] in
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
                logInfo("PDFCacheService", "Eski dosyalar temizlendi", details: "\(deletedCount) dosya (\(cacheExpirationDays) günden eski)")
            }
        } catch {
            logWarning("PDFCacheService", "Temizleme hatası", details: error.localizedDescription)
        }
    }
}

// MARK: - Cache Statistics

struct CacheStatistics {
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
        "\(fileCount) dosya, \(formattedTotalSize) / \(formattedMaxSize) (\(String(format: "%.1f", usagePercentage))%)"
    }
}
