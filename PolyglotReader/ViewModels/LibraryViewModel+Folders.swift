import Foundation

@MainActor
extension LibraryViewModel {
    // MARK: - Folder Management

    /// Klasöre git
    func navigateToFolder(_ folder: Folder?) {
        if let folder = folder {
            folderPath.append(folder)
            currentFolder = folder
        } else {
            folderPath.removeAll()
            currentFolder = nil
        }
        Task {
            await loadFoldersAndTags()
        }
    }

    /// Bir önceki klasöre dön
    func navigateBack() {
        guard !folderPath.isEmpty else { return }
        folderPath.removeLast()
        currentFolder = folderPath.last
        Task {
            await loadFoldersAndTags()
        }
    }

    /// Yeni klasör oluştur
    func createFolder(name: String, color: String = "#6366F1") async {
        do {
            let folder = try await supabaseService.createFolder(
                name: name,
                parentId: currentFolder?.id
            )
            await loadFoldersAndTags()
            logInfo("LibraryViewModel", "Klasör oluşturuldu", details: folder.name)
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            errorMessage = appError.localizedDescription
            logError("LibraryViewModel", "Klasör oluşturma hatası", error: appError)
            ErrorHandlingService.shared.handle(
                appError,
                context: .init(
                    source: "LibraryViewModel",
                    operation: "CreateFolder"
                ) { [weak self] in
                    Task { await self?.createFolder(name: name, color: color) }
                    return
                }
            )
        }
    }

    /// Klasör sil
    func deleteFolder(_ folder: Folder) async {
        do {
            try await supabaseService.deleteFolder(id: folder.id.uuidString)
            await loadFoldersAndTags()
            logInfo("LibraryViewModel", "Klasör silindi", details: folder.name)
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            errorMessage = appError.localizedDescription
            logError("LibraryViewModel", "Klasör silme hatası", error: appError)
            ErrorHandlingService.shared.handle(
                appError,
                context: .init(
                    source: "LibraryViewModel",
                    operation: "DeleteFolder"
                ) { [weak self] in
                    Task { await self?.deleteFolder(folder) }
                    return
                }
            )
        }
    }

    /// Dosyayı klasöre taşı
    func moveFile(_ file: PDFDocumentMetadata, to folder: Folder?) async {
        do {
            try await supabaseService.moveFileToFolder(
                fileId: file.id,
                folderId: folder?.id
            )
            if let index = files.firstIndex(where: { $0.id == file.id }) {
                files[index].folderId = folder?.id
            }
            await loadFoldersAndTags()
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            errorMessage = appError.localizedDescription
            ErrorHandlingService.shared.handle(
                appError,
                context: .init(
                    source: "LibraryViewModel",
                    operation: "MoveFile"
                ) { [weak self] in
                    Task { await self?.moveFile(file, to: folder) }
                    return
                }
            )
        }
    }
}
