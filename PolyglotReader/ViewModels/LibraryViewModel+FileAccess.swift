import Foundation

@MainActor
extension LibraryViewModel {
    // MARK: - Get File URL

    func getFileURL(_ file: PDFDocumentMetadata) async -> URL? {
        do {
            return try await supabaseService.getFileURL(storagePath: file.storagePath)
        } catch {
            errorMessage = "Dosya URL'i alınamadı"
            return nil
        }
    }

    // MARK: - Rename

    /// Dosyayı yeniden adlandırır; ".pdf" uzantısı korunur.
    func renameFile(_ file: PDFDocumentMetadata, to newName: String) async {
        var trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != file.name else { return }

        // Uzantıyı koru: kullanıcı silmişse geri ekle
        if file.name.lowercased().hasSuffix(".pdf") && !trimmed.lowercased().hasSuffix(".pdf") {
            trimmed += ".pdf"
        }

        do {
            try await supabaseService.renameFile(fileId: file.id, name: trimmed)
            if let index = files.firstIndex(where: { $0.id == file.id }) {
                files[index].name = trimmed
            }
            logInfo("LibraryViewModel", "Dosya yeniden adlandırıldı", details: trimmed)
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            ErrorHandlingService.shared.handle(
                appError,
                context: .init(
                    source: "LibraryViewModel",
                    operation: "RenameFile"
                ) { [weak self] in
                    Task { await self?.renameFile(file, to: newName) }
                    return
                }
            )
        }
    }

    // MARK: - Share

    /// PDF'i paylaşım için geçici dosyaya indirir; share sheet bu URL'i kullanır.
    /// Dosya adı korunur ki alıcı tarafta anlamlı görünsün.
    func downloadFileForSharing(_ file: PDFDocumentMetadata) async -> URL? {
        isPreparingShare = true
        defer { isPreparingShare = false }

        do {
            let url = try await supabaseService.getFileURL(storagePath: file.storagePath)
            let (data, _) = try await SecurityManager.shared.secureSession.data(from: url)

            let shareDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("share_exports", isDirectory: true)
            try FileManager.default.createDirectory(
                at: shareDirectory,
                withIntermediateDirectories: true
            )

            var fileName = file.name
            if !fileName.lowercased().hasSuffix(".pdf") {
                fileName += ".pdf"
            }
            let destination = shareDirectory.appendingPathComponent(fileName)
            try data.write(to: destination, options: [.atomic])
            return destination
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            logError("LibraryViewModel", "Paylaşım için indirme hatası", error: appError)
            errorMessage = "Dosya paylaşım için hazırlanamadı."
            return nil
        }
    }
}
