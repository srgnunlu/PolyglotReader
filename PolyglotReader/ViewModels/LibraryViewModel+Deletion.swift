import Foundation

@MainActor
extension LibraryViewModel {
    // MARK: - Delete (Soft → Trash)

    /// Kütüphaneden silme artık çöp kutusuna taşır: storage, RAG chunk'ları ve
    /// etiketler korunur; "Son Silinenler"den geri yüklenebilir.
    func deleteFile(_ file: PDFDocumentMetadata) async {
        do {
            try await supabaseService.softDeleteFile(id: file.id)
            files.removeAll { $0.id == file.id }

            var trashed = file
            trashed.deletedAt = Date()
            trashedFiles.insert(trashed, at: 0)

            offerUndo(message: "\"\(file.name)\" silindi") { [weak self] in
                await self?.restoreFromTrash(trashed)
            }
            await loadFoldersAndTags()
        } catch {
            handleDeleteError(error, file: file)
        }
    }

    // MARK: - Trash

    /// Çöp kutusunu yükler ve 30 günden eski kayıtları kalıcı temizler.
    func loadTrash() async {
        do {
            trashedFiles = try await supabaseService.listTrashedFiles()

            let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
            let expired = trashedFiles.filter { ($0.deletedAt ?? .distantFuture) < cutoff }
            for file in expired {
                await permanentlyDeleteFile(file)
            }
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            logWarning("LibraryViewModel", "Çöp kutusu yüklenemedi", details: appError.localizedDescription)
            ErrorHandlingService.shared.handle(
                appError,
                context: .silent(source: "LibraryViewModel", operation: "LoadTrash")
            )
        }
    }

    /// Dosyayı çöpten geri yükler (klasörü korunur; klasör silindiyse köke döner).
    func restoreFromTrash(_ file: PDFDocumentMetadata) async {
        do {
            try await supabaseService.restoreFile(id: file.id)
            trashedFiles.removeAll { $0.id == file.id }

            var restored = file
            restored.deletedAt = nil
            files.insert(restored, at: 0)

            await loadFoldersAndTags()
            logInfo("LibraryViewModel", "Dosya geri yüklendi", details: file.name)
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            errorMessage = "Dosya geri yüklenemedi."
            logError("LibraryViewModel", "Geri yükleme hatası", error: appError)
        }
    }

    /// Kalıcı silme: storage + DB satırı + RAG chunk'ları + önbellekler.
    func permanentlyDeleteFile(_ file: PDFDocumentMetadata) async {
        do {
            try await supabaseService.deleteFile(id: file.id, storagePath: file.storagePath)
            trashedFiles.removeAll { $0.id == file.id }
            CacheService.shared.removeThumbnail(forFileId: file.id)
            removeThumbnailFromDisk(fileId: file.id)
            removeSummaryFromCache(fileId: file.id)
            try? await supabaseService.deleteThumbnail(forFileStoragePath: file.storagePath)
            try? await supabaseService.deleteDocumentChunks(fileId: file.id)
            try? await supabaseService.cleanupUnusedTags()
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            errorMessage = "Dosya kalıcı olarak silinemedi."
            logError("LibraryViewModel", "Kalıcı silme hatası", error: appError)
        }
    }

    /// Çöp kutusunu tamamen boşaltır.
    func emptyTrash() async {
        let targets = trashedFiles
        for file in targets {
            await permanentlyDeleteFile(file)
        }
        await loadFoldersAndTags()
    }

    private func handleDeleteError(_ error: Error, file: PDFDocumentMetadata) {
        // Kullanıcıya sunum ErrorHandlingService banner/alert'i üzerinden yapılır.
        let appError = ErrorHandlingService.mapToAppError(error)
        ErrorHandlingService.shared.handle(
            appError,
            context: .init(
                source: "LibraryViewModel",
                operation: "DeleteFile"
            ) { [weak self] in
                Task { await self?.deleteFile(file) }
                return
            }
        )
    }
}
