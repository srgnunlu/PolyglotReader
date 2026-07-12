import Foundation

extension SupabaseService {
    // MARK: - File Delegation (Backward Compatibility)

    func uploadFile(
        _ data: Data,
        fileName: String,
        userId: String,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> PDFDocumentMetadata {
        try await perform(category: .storage) {
            try await files.uploadFile(
                data: data,
                fileName: fileName,
                userId: userId,
                progressHandler: progressHandler
            )
        }
    }

    func listFiles() async throws -> [PDFDocumentMetadata] {
        try await perform(category: .database) {
            try await files.listFiles()
        }
    }

    func getFile(id: String) async throws -> PDFDocumentMetadata? {
        try await perform(category: .database) {
            try await files.getFile(id: id)
        }
    }

    func getFileURL(storagePath: String) async throws -> URL {
        try await perform(category: .storage) {
            try await files.getFileURL(storagePath: storagePath)
        }
    }

    func renameFile(fileId: String, name: String) async throws {
        try await perform(category: .database) {
            try await files.updateName(fileId: fileId, name: name)
        }
    }

    func listTrashedFiles() async throws -> [PDFDocumentMetadata] {
        try await perform(category: .database) {
            try await files.listTrashedFiles()
        }
    }

    func softDeleteFile(id: String) async throws {
        try await perform(category: .database) {
            try await files.softDeleteFile(id: id)
        }
    }

    func restoreFile(id: String) async throws {
        try await perform(category: .database) {
            try await files.restoreFile(id: id)
        }
    }

    func updateFileFavorite(fileId: String, isFavorite: Bool) async throws {
        try await perform(category: .database) {
            try await files.updateFavorite(fileId: fileId, isFavorite: isFavorite)
        }
    }

    func updateFilePageCount(fileId: String, pageCount: Int) async throws {
        try await perform(category: .database) {
            try await files.updatePageCount(fileId: fileId, pageCount: pageCount)
        }
    }

    func searchFileIdsByContent(query: String, limit: Int = 20) async throws -> [String] {
        try await perform(category: .database) {
            try await files.searchFileIdsByContent(query: query, limit: limit)
        }
    }

    func updateFileSummary(fileId: String, summary: String) async throws {
        try await perform(category: .database) {
            try await files.updateSummary(fileId: fileId, summary: summary)
        }
    }

    // MARK: - Advanced File Operations

    func updateFileCategory(fileId: String, category: String?) async throws {
        try await perform(category: .database) {
            try await files.updateCategory(fileId: fileId, category: category)
        }
    }

    func deleteDocumentChunks(fileId: String) async throws {
        try await perform(category: .database) {
            try await files.deleteDocumentChunks(fileId: fileId)
        }
    }

    func moveFileToFolder(fileId: String, folderId: UUID?) async throws {
        try await perform(category: .database) {
            try await files.moveToFolder(fileId: fileId, folderId: folderId?.uuidString)
        }
    }

    func deleteFile(id: String, storagePath: String) async throws {
        try await perform(category: .storage) {
            try await files.deleteFile(id: id, storagePath: storagePath)
        }
    }

    // MARK: - Thumbnails (Storage)

    func uploadThumbnail(_ data: Data, forFileStoragePath storagePath: String) async throws {
        try await perform(category: .storage) {
            try await storage.uploadThumbnail(data, forFileStoragePath: storagePath)
        }
    }

    func downloadThumbnail(forFileStoragePath storagePath: String) async throws -> Data {
        try await perform(category: .storage) {
            try await storage.downloadThumbnail(forFileStoragePath: storagePath)
        }
    }

    func deleteThumbnail(forFileStoragePath storagePath: String) async throws {
        try await perform(category: .storage) {
            try await storage.deleteThumbnail(forFileStoragePath: storagePath)
        }
    }
}
