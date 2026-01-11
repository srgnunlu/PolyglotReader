import Foundation
import PDFKit

@MainActor
extension LibraryViewModel {
    // MARK: - Thumbnail Loading (Lazy)

    func loadThumbnailIfNeeded(for file: PDFDocumentMetadata) {
        // Zaten thumbnail varsa veya yükleme devam ediyorsa atla
        guard file.thumbnailData == nil else { return }
        guard thumbnailLoadingTasks[file.id] == nil else { return }

        // CacheService'ten kontrol et (memory cache)
        if let cachedData = CacheService.shared.getThumbnail(forFileId: file.id) {
            updateFileThumbnail(fileId: file.id, thumbnailData: cachedData)
            return
        }

        // Disk cache'ten kontrol et
        if let diskData = loadThumbnailFromDisk(fileId: file.id) {
            CacheService.shared.setThumbnail(diskData, forFileId: file.id)
            updateFileThumbnail(fileId: file.id, thumbnailData: diskData)
            return
        }

        // Arka planda thumbnail yükle
        let task = Task {
            await generateThumbnail(for: file)
        }
        thumbnailLoadingTasks[file.id] = task
    }

    private func generateThumbnail(for file: PDFDocumentMetadata) async {
        defer { thumbnailLoadingTasks[file.id] = nil }

        do {
            // PDF'i indir
            let url = try await supabaseService.getFileURL(storagePath: file.storagePath)

            // URL'den veri oku
            let (data, _) = try await SecurityManager.shared.secureSession.data(from: url)

            // PDFDocument oluştur ve thumbnail üret
            let document = try pdfService.loadPDF(from: data)
            let thumbnailData = try pdfService.generateThumbnailData(for: document)

            // CacheService'e ekle (memory cache)
            CacheService.shared.setThumbnail(thumbnailData, forFileId: file.id)
            saveThumbnailToDisk(thumbnailData, fileId: file.id)

            // Dosyayı güncelle
            updateFileThumbnail(fileId: file.id, thumbnailData: thumbnailData)
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            logError("LibraryViewModel", "Thumbnail oluşturulamadı: \(file.name)", error: appError)
            ErrorHandlingService.shared.handle(
                appError,
                context: .silent(source: "LibraryViewModel", operation: "Thumbnail")
            )
        }
    }

    private func updateFileThumbnail(fileId: String, thumbnailData: Data) {
        if let index = files.firstIndex(where: { $0.id == fileId }) {
            files[index].thumbnailData = thumbnailData
        }
    }

    // MARK: - Clear Cache

    func clearThumbnailCache() {
        // Memory cache CacheService üzerinden temizlenir
        // (CacheService.shared.clearAllCaches() memory warning'de otomatik çağrılır)
        thumbnailLoadingTasks.values.forEach { $0.cancel() }
        thumbnailLoadingTasks.removeAll()

        if let cacheDirectory = thumbnailCacheDirectoryURL() {
            do {
                try FileManager.default.removeItem(at: cacheDirectory)
            } catch {
                logWarning(
                    "LibraryViewModel",
                    "Thumbnail cache temizlenemedi",
                    details: error.localizedDescription
                )
            }
        }
    }

    // MARK: - Thumbnail Disk Cache

    private func thumbnailCacheDirectoryURL() -> URL? {
        guard let baseURL = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let directory = baseURL.appendingPathComponent("pdf_thumbnail_cache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            } catch {
                logWarning(
                    "LibraryViewModel",
                    "Thumbnail cache klasörü oluşturulamadı",
                    details: error.localizedDescription
                )
                return nil
            }
        }
        return directory
    }

    private func thumbnailDiskURL(for fileId: String) -> URL? {
        guard let directory = thumbnailCacheDirectoryURL() else { return nil }
        return directory.appendingPathComponent("\(fileId).jpg")
    }

    private func loadThumbnailFromDisk(fileId: String) -> Data? {
        guard let url = thumbnailDiskURL(for: fileId) else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            logWarning(
                "LibraryViewModel",
                "Disk thumbnail okunamadı",
                details: error.localizedDescription
            )
            return nil
        }
    }

    func saveThumbnailToDisk(_ data: Data, fileId: String) {
        guard let url = thumbnailDiskURL(for: fileId) else { return }
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            logWarning(
                "LibraryViewModel",
                "Disk thumbnail yazılamadı",
                details: error.localizedDescription
            )
        }
    }

    func removeThumbnailFromDisk(fileId: String) {
        guard let url = thumbnailDiskURL(for: fileId) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            logWarning(
                "LibraryViewModel",
                "Disk thumbnail silinemedi",
                details: error.localizedDescription
            )
        }
    }
}
