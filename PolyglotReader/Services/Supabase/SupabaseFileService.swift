import Foundation
import Supabase

// MARK: - File Service

/// Handles file metadata CRUD operations in the database
@MainActor
final class SupabaseFileService {
    // MARK: - Properties

    private let client: SupabaseClient
    private let storageService: SupabaseStorageService

    // MARK: - Initialization

    init(
        client: SupabaseClient,
        storageService: SupabaseStorageService? = nil
    ) {
        self.client = client
        self.storageService = storageService ?? SupabaseStorageService(client: client)
    }

    // MARK: - Create

    /// Upload a file and save metadata
    /// - Parameters:
    ///   - data: File data to upload
    ///   - fileName: Name of the file
    ///   - userId: User ID
    ///   - progressHandler: Optional callback for upload progress (0.0 to 1.0)
    func uploadFile(
        data: Data,
        fileName: String,
        userId: String,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> PDFDocumentMetadata {
        let storagePath = storageService.generateStoragePath(
            userId: userId,
            fileName: fileName
        )

        // Upload to storage with progress tracking
        try await storageService.uploadFile(
            data: data,
            path: storagePath,
            progressHandler: progressHandler
        )

        // Save metadata to database
        let fileInsert = FileInsert(
            user_id: userId,
            name: fileName,
            storage_path: storagePath,
            file_type: "application/pdf",
            size: data.count
        )

        let response: FileRecord = try await client
            .from("files")
            .insert(fileInsert)
            .select()
            .single()
            .execute()
            .value

        return mapToMetadata(from: response, storagePath: storagePath)
    }

    // MARK: - Read

    /// List all files for current user
    func listFiles() async throws -> [PDFDocumentMetadata] {
        let files: [FileRecord] = try await client
            .from("files")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value

        return files.map { mapToMetadata(from: $0, storagePath: $0.storage_path) }
    }

    /// Get a single file by ID
    func getFile(id: String) async throws -> PDFDocumentMetadata? {
        let files: [FileRecord] = try await client
            .from("files")
            .select()
            .eq("id", value: id)
            .execute()
            .value

        guard let file = files.first else { return nil }
        return mapToMetadata(from: file, storagePath: file.storage_path)
    }

    /// Get signed URL for file download
    func getFileURL(storagePath: String) async throws -> URL {
        try await storageService.getSignedURL(for: storagePath)
    }

    // MARK: - Update

    /// Update file summary
    func updateSummary(fileId: String, summary: String) async throws {
        try await client
            .from("files")
            .update(SummaryUpdate(summary: summary))
            .eq("id", value: fileId)
            .execute()
    }

    /// Update file folder
    func moveToFolder(fileId: String, folderId: String?) async throws {
        struct FolderUpdate: Encodable {
            let folder_id: String?
        }

        try await client
            .from("files")
            .update(FolderUpdate(folder_id: folderId))
            .eq("id", value: fileId)
            .execute()
    }

    /// Update file AI category
    func updateCategory(fileId: String, category: String?) async throws {
        struct CategoryUpdate: Encodable {
            let ai_category: String?
        }

        try await client
            .from("files")
            .update(CategoryUpdate(ai_category: category))
            .eq("id", value: fileId)
            .execute()
    }

    /// Delete document chunks (RAG)
    func deleteDocumentChunks(fileId: String) async throws {
        try await client
            .from("document_chunks")
            .delete()
            .eq("file_id", value: fileId)
            .execute()
    }

    // MARK: - Delete

    /// Delete a file
    func deleteFile(id: String, storagePath: String) async throws {
        // Delete from storage first
        try await storageService.deleteFile(path: storagePath)

        // Delete from database
        try await client
            .from("files")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Private Helpers

    private func mapToMetadata(
        from record: FileRecord,
        storagePath: String
    ) -> PDFDocumentMetadata {
        PDFDocumentMetadata(
            id: record.id,
            name: record.name,
            size: record.size,
            uploadedAt: DateFormatting.date(from: record.created_at),
            storagePath: storagePath,
            summary: record.summary,
            folderId: record.folder_id.flatMap { UUID(uuidString: $0) },
            aiCategory: record.ai_category
        )
    }
}
