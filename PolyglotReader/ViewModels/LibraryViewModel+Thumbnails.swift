import Foundation
import PDFKit

@MainActor
extension LibraryViewModel {
    // MARK: - Thumbnail Loading (Lazy)

    /// True while the file's thumbnail is being generated — drives the
    /// card skeleton state.
    func isThumbnailPending(_ file: PDFDocumentMetadata) -> Bool {
        file.thumbnailData == nil && pendingThumbnailIds.contains(file.id)
    }

    func loadThumbnailIfNeeded(for file: PDFDocumentMetadata) {
        // Zaten thumbnail varsa veya yükleme devam ediyorsa atla
        guard file.thumbnailData == nil else { return }
        guard thumbnailLoadingTasks[file.id] == nil else { return }
        guard !thumbnailWaitQueue.contains(where: { $0.id == file.id }) else { return }

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

        // Kuyruğa al — aynı anda en fazla `maxConcurrentThumbnailTasks` indirme
        pendingThumbnailIds.insert(file.id)
        thumbnailWaitQueue.append(file)
        processThumbnailQueue()
    }

    /// Kuyruktan boş slot sayısı kadar iş başlatır; her iş bitişinde tekrar çağrılır.
    private func processThumbnailQueue() {
        while activeThumbnailTaskCount < maxConcurrentThumbnailTasks, !thumbnailWaitQueue.isEmpty {
            let file = thumbnailWaitQueue.removeFirst()

            // Kuyrukta beklerken silinmiş/yüklenmiş olabilir
            guard thumbnailLoadingTasks[file.id] == nil,
                  files.contains(where: { $0.id == file.id && $0.thumbnailData == nil }) else {
                pendingThumbnailIds.remove(file.id)
                continue
            }

            activeThumbnailTaskCount += 1
            let task = Task { [weak self] in
                await self?.fetchOrGenerateThumbnail(for: file)
                guard let self else { return }
                self.thumbnailLoadingTasks[file.id] = nil
                self.pendingThumbnailIds.remove(file.id)
                self.activeThumbnailTaskCount -= 1
                self.processThumbnailQueue()
            }
            thumbnailLoadingTasks[file.id] = task
        }
    }

    private func fetchOrGenerateThumbnail(for file: PDFDocumentMetadata) async {
        // 1) Hızlı yol: yükleme anında Storage'a konan küçük JPEG'i indir
        //    (~50 KB; tam PDF indirmeye kıyasla kat kat ucuz).
        if let thumbData = try? await supabaseService.downloadThumbnail(
            forFileStoragePath: file.storagePath
        ), !thumbData.isEmpty {
            CacheService.shared.setThumbnail(thumbData, forFileId: file.id)
            saveThumbnailToDisk(thumbData, fileId: file.id)
            updateFileThumbnail(fileId: file.id, thumbnailData: thumbData)
            return
        }

        // 2) Legacy yol: Storage'da kapak yok (eski yüklemeler) — tam PDF'ten
        //    üret ve bir defalık Storage'a geri yaz (backfill).
        do {
            let url = try await supabaseService.getFileURL(storagePath: file.storagePath)
            let (data, _) = try await SecurityManager.shared.secureSession.data(from: url)

            let document = try pdfService.loadPDF(from: data)
            let thumbnailData = try pdfService.generateThumbnailData(for: document)

            CacheService.shared.setThumbnail(thumbnailData, forFileId: file.id)
            saveThumbnailToDisk(thumbnailData, fileId: file.id)
            updateFileThumbnail(fileId: file.id, thumbnailData: thumbnailData)

            try? await supabaseService.uploadThumbnail(
                thumbnailData,
                forFileStoragePath: file.storagePath
            )

            // Fırsatçı backfill: PDF zaten elimizdeyken eksik sayfa sayısını yaz
            if file.pageCount == nil, document.pageCount > 0 {
                try? await supabaseService.updateFilePageCount(
                    fileId: file.id,
                    pageCount: document.pageCount
                )
                if let index = files.firstIndex(where: { $0.id == file.id }) {
                    files[index].pageCount = document.pageCount
                }
            }
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
        thumbnailWaitQueue.removeAll()
        activeThumbnailTaskCount = 0
        pendingThumbnailIds.removeAll()

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
        // "_v2": thumbnail çözünürlüğü 300x400 → 600x800 yükseltildi; eski
        // düşük çözünürlüklü disk cache'i atlanır ve bir defalık yeniden üretilir.
        return directory.appendingPathComponent("\(fileId)_v2.jpg")
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
