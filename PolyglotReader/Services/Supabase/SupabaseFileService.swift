import Foundation
import Supabase

// RPC payload'ları sınıf dışında: @MainActor izolasyonuna takılmadan Sendable
// Encodable/Decodable uyumu sağlanır.
private nonisolated struct ContentSearchParams: Encodable, Sendable {
    let search_query: String
    let match_count: Int
}

private nonisolated struct ContentSearchMatch: Decodable, Sendable {
    let file_id: UUID
}

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

    /// List all files for current user, with per-user reading progress embedded
    /// (RLS keeps the embed to the caller's own row). Trashed files are excluded.
    func listFiles() async throws -> [PDFDocumentMetadata] {
        let files: [FileRecord] = try await client
            .from("files")
            .select("*, reading_progress(page, updated_at)")
            .is("deleted_at", value: nil)
            .order("created_at", ascending: false)
            .execute()
            .value

        return files.map { mapToMetadata(from: $0, storagePath: $0.storage_path) }
    }

    /// Files in the trash ("Son Silinenler"), newest deletion first.
    func listTrashedFiles() async throws -> [PDFDocumentMetadata] {
        let files: [FileRecord] = try await client
            .from("files")
            .select()
            .not("deleted_at", operator: .is, value: "null")
            .order("deleted_at", ascending: false)
            .execute()
            .value

        return files.map { mapToMetadata(from: $0, storagePath: $0.storage_path) }
    }

    /// Soft delete: stamp deleted_at; storage/chunks/tags survive for restore.
    func softDeleteFile(id: String) async throws {
        struct SoftDelete: Encodable {
            let deleted_at: String
        }

        try await client
            .from("files")
            .update(SoftDelete(deleted_at: ISO8601DateFormatter().string(from: Date())))
            .eq("id", value: id)
            .execute()
    }

    /// Restore from trash: clear deleted_at (explicit NULL via AnyJSON).
    func restoreFile(id: String) async throws {
        try await client
            .from("files")
            .update(["deleted_at": AnyJSON.null])
            .eq("id", value: id)
            .execute()
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

    /// Toggle favorite flag
    func updateFavorite(fileId: String, isFavorite: Bool) async throws {
        struct FavoriteUpdate: Encodable {
            let is_favorite: Bool
        }

        try await client
            .from("files")
            .update(FavoriteUpdate(is_favorite: isFavorite))
            .eq("id", value: fileId)
            .execute()
    }

    /// Persist total page count (set at upload, backfilled for legacy files)
    func updatePageCount(fileId: String, pageCount: Int) async throws {
        struct PageCountUpdate: Encodable {
            let page_count: Int
        }

        try await client
            .from("files")
            .update(PageCountUpdate(page_count: pageCount))
            .eq("id", value: fileId)
            .execute()
    }

    /// Library-wide content search: returns IDs of files whose chunks match
    /// the query (Turkish + English BM25 via `search_files_by_content` RPC).
    func searchFileIdsByContent(query: String, limit: Int = 20) async throws -> [String] {
        let matches: [ContentSearchMatch] = try await client
            .rpc(
                "search_files_by_content",
                params: ContentSearchParams(search_query: query, match_count: limit)
            )
            .execute()
            .value

        return matches.map { $0.file_id.uuidString.lowercased() }
    }

    /// Update file display name
    func updateName(fileId: String, name: String) async throws {
        struct NameUpdate: Encodable {
            let name: String
        }

        try await client
            .from("files")
            .update(NameUpdate(name: name))
            .eq("id", value: fileId)
            .execute()
    }

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
        let progress = record.reading_progress?.first
        return PDFDocumentMetadata(
            id: record.id,
            name: record.name,
            size: record.size,
            uploadedAt: DateFormatting.date(from: record.created_at),
            storagePath: storagePath,
            summary: record.summary,
            folderId: record.folder_id.flatMap { UUID(uuidString: $0) },
            aiCategory: record.ai_category,
            isFavorite: record.is_favorite ?? false,
            pageCount: record.page_count,
            lastReadPage: progress?.page,
            lastOpenedAt: progress?.updated_at.map { DateFormatting.date(from: $0) },
            deletedAt: record.deleted_at.map { DateFormatting.date(from: $0) }
        )
    }
}
