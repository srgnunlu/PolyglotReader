import Foundation

@MainActor
extension LibraryViewModel {
    // MARK: - Selection Mode

    var selectedCount: Int { selectedFileIds.count }

    func toggleSelectionMode() {
        isSelectionMode.toggle()
        if !isSelectionMode {
            selectedFileIds.removeAll()
        }
    }

    func exitSelectionMode() {
        isSelectionMode = false
        selectedFileIds.removeAll()
    }

    func isSelected(_ file: PDFDocumentMetadata) -> Bool {
        selectedFileIds.contains(file.id)
    }

    func toggleSelection(_ file: PDFDocumentMetadata) {
        if selectedFileIds.contains(file.id) {
            selectedFileIds.remove(file.id)
        } else {
            selectedFileIds.insert(file.id)
        }
    }

    /// Selects every file currently visible under the active filters.
    func selectAllVisible() {
        selectedFileIds = Set(filteredFiles.map { $0.id })
    }

    // MARK: - Bulk Operations

    /// Deletes all selected files (storage + DB + RAG chunks), then cleans up tags.
    func deleteSelectedFiles() async {
        let targets = files.filter { selectedFileIds.contains($0.id) }
        guard !targets.isEmpty else { return }

        var failed = 0
        for file in targets {
            do {
                try await supabaseService.deleteFile(id: file.id, storagePath: file.storagePath)
                files.removeAll { $0.id == file.id }
                CacheService.shared.removeThumbnail(forFileId: file.id)
                removeThumbnailFromDisk(fileId: file.id)
                removeSummaryFromCache(fileId: file.id)
                try? await supabaseService.deleteDocumentChunks(fileId: file.id)
            } catch {
                failed += 1
                let appError = ErrorHandlingService.mapToAppError(error)
                logError("LibraryViewModel", "Toplu silme hatası", error: appError)
            }
        }

        if failed > 0 {
            errorMessage = "\(failed) dosya silinemedi."
        }

        try? await supabaseService.cleanupUnusedTags()
        await loadFoldersAndTags()
        exitSelectionMode()
    }

    /// Moves all selected files into `folder` (or the root when `nil`).
    func moveSelectedFiles(to folder: Folder?) async {
        let targets = files.filter { selectedFileIds.contains($0.id) }
        guard !targets.isEmpty else { return }

        var failed = 0
        for file in targets {
            do {
                try await supabaseService.moveFileToFolder(fileId: file.id, folderId: folder?.id)
                if let index = files.firstIndex(where: { $0.id == file.id }) {
                    files[index].folderId = folder?.id
                }
            } catch {
                failed += 1
                let appError = ErrorHandlingService.mapToAppError(error)
                logError("LibraryViewModel", "Toplu taşıma hatası", error: appError)
            }
        }

        if failed > 0 {
            errorMessage = "\(failed) dosya taşınamadı."
        }

        await loadFoldersAndTags()
        exitSelectionMode()
    }
}
