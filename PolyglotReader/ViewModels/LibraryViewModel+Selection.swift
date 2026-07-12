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

    /// Moves all selected files to the trash (soft delete) — restorable from
    /// "Son Silinenler"; kalıcı temizlik oradan yapılır.
    func deleteSelectedFiles() async {
        let targets = files.filter { selectedFileIds.contains($0.id) }
        guard !targets.isEmpty else { return }

        var failed = 0
        var trashed: [PDFDocumentMetadata] = []
        for file in targets {
            do {
                try await supabaseService.softDeleteFile(id: file.id)
                files.removeAll { $0.id == file.id }
                var copy = file
                copy.deletedAt = Date()
                trashedFiles.insert(copy, at: 0)
                trashed.append(copy)
            } catch {
                failed += 1
                let appError = ErrorHandlingService.mapToAppError(error)
                logError("LibraryViewModel", "Toplu silme hatası", error: appError)
            }
        }

        if failed > 0 {
            errorMessage = "\(failed) dosya silinemedi."
        }
        if !trashed.isEmpty {
            let toRestore = trashed
            offerUndo(message: "\(trashed.count) dosya silindi") { [weak self] in
                for file in toRestore {
                    await self?.restoreFromTrash(file)
                }
            }
        }

        await loadFoldersAndTags()
        exitSelectionMode()
    }

    /// Seçili tüm dosyalara verilen etiketleri ekler (toplu etiketleme).
    func assignTagsToSelectedFiles(tagIds: [UUID]) async {
        let targets = files.filter { selectedFileIds.contains($0.id) }
        guard !targets.isEmpty, !tagIds.isEmpty else { return }

        var failed = 0
        for file in targets {
            do {
                try await supabaseService.addTagsToFile(fileId: file.id, tagIds: tagIds)
            } catch {
                failed += 1
                let appError = ErrorHandlingService.mapToAppError(error)
                logError("LibraryViewModel", "Toplu etiketleme hatası", error: appError)
            }
        }

        if failed > 0 {
            errorMessage = "\(failed) dosya etiketlenemedi."
        }

        // Etiketleri tazele (dosya bazlı + sayaçlar)
        do {
            let fileIds = targets.map { $0.id }
            let tagsByFile = try await supabaseService.getFileTagsBatch(fileIds: fileIds)
            for index in files.indices where tagsByFile[files[index].id] != nil {
                files[index].tags = tagsByFile[files[index].id] ?? []
            }
            allTags = try await supabaseService.listTags()
        } catch {
            logWarning("LibraryViewModel", "Etiket tazeleme hatası", details: error.localizedDescription)
        }

        exitSelectionMode()
    }

    /// Moves all selected files into `folder` (or the root when `nil`).
    func moveSelectedFiles(to folder: Folder?) async {
        let targets = files.filter { selectedFileIds.contains($0.id) }
        guard !targets.isEmpty else { return }

        var failed = 0
        var moved: [(fileId: String, folderId: UUID?)] = []
        for file in targets {
            do {
                try await supabaseService.moveFileToFolder(fileId: file.id, folderId: folder?.id)
                moved.append((file.id, file.folderId))
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
        if !moved.isEmpty {
            let assignments = moved
            offerUndo(message: "\(moved.count) dosya → \(folder?.name ?? "Ana Klasör")") { [weak self] in
                await self?.restoreFolderAssignments(assignments)
            }
        }

        await loadFoldersAndTags()
        exitSelectionMode()
    }
}
