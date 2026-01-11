import Foundation

@MainActor
extension LibraryViewModel {
    // MARK: - Delete File

    func deleteFile(_ file: PDFDocumentMetadata) async {
        do {
            try await deleteFileFromServer(file)
            removeFileFromState(file)
            schedulePostDeletionCleanup(for: file)
        } catch {
            handleDeleteError(error, file: file)
        }
    }

    private func deleteFileFromServer(_ file: PDFDocumentMetadata) async throws {
        try await supabaseService.deleteFile(id: file.id, storagePath: file.storagePath)
    }

    private func removeFileFromState(_ file: PDFDocumentMetadata) {
        files.removeAll { $0.id == file.id }
        CacheService.shared.removeThumbnail(forFileId: file.id)
        removeThumbnailFromDisk(fileId: file.id)
        removeSummaryFromCache(fileId: file.id)
    }

    private func schedulePostDeletionCleanup(for file: PDFDocumentMetadata) {
        Task {
            await deleteChunksAfterDeletion(for: file)
            await cleanupTagsAfterDeletion()
        }
    }

    private func deleteChunksAfterDeletion(for file: PDFDocumentMetadata) async {
        do {
            try await supabaseService.deleteDocumentChunks(fileId: file.id)
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            logWarning(
                "LibraryViewModel",
                "RAG chunk'ları silinemedi",
                details: appError.localizedDescription
            )
            ErrorHandlingService.shared.handle(
                appError,
                context: .silent(source: "LibraryViewModel", operation: "DeleteChunks")
            )
        }
    }

    private func cleanupTagsAfterDeletion() async {
        do {
            try await supabaseService.cleanupUnusedTags()
            await loadFoldersAndTags()
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            logWarning(
                "LibraryViewModel",
                "Etiket temizliği başarısız",
                details: appError.localizedDescription
            )
            ErrorHandlingService.shared.handle(
                appError,
                context: .silent(source: "LibraryViewModel", operation: "CleanupTags")
            )
        }
    }

    private func handleDeleteError(_ error: Error, file: PDFDocumentMetadata) {
        let appError = ErrorHandlingService.mapToAppError(error)
        errorMessage = appError.localizedDescription
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
