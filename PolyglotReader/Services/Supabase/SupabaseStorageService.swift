import Foundation
import Supabase

// MARK: - Storage Service

/// Handles all Supabase Storage operations (upload/download)
@MainActor
final class SupabaseStorageService {
    // MARK: - Constants

    private static let bucketName = "user_files"
    private static let signedURLExpiration: TimeInterval = 3600
    /// File size threshold for using extended timeout (10 MB)
    private static let largeFileThreshold: Int = 10 * 1024 * 1024
    /// Chunk size for multipart uploads (5 MB)
    private static let chunkSize: Int = 5 * 1024 * 1024

    // MARK: - Properties

    private let client: SupabaseClient

    // MARK: - Initialization

    init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Upload Operations

    /// Upload a file to storage with automatic timeout adjustment for large files
    /// - Parameters:
    ///   - data: File data to upload
    ///   - path: Storage path
    ///   - contentType: MIME type
    ///   - progressHandler: Optional callback for upload progress (0.0 to 1.0)
    func uploadFile(
        data: Data,
        path: String,
        contentType: String = "application/pdf",
        progressHandler: ((Double) -> Void)? = nil
    ) async throws {
        let shouldTrackProgress = progressHandler != nil || data.count > Self.largeFileThreshold

        // Use extended timeout for large files or when progress is requested
        if shouldTrackProgress {
            try await uploadFileWithProgress(
                data: data,
                path: path,
                contentType: contentType,
                progressHandler: progressHandler
            )
        } else {
            try await client.storage
                .from(Self.bucketName)
                .upload(path, data: data, options: .init(contentType: contentType))
            progressHandler?(1.0)
        }
    }
    
    /// Upload files with progress tracking
    private func uploadFileWithProgress(
        data: Data,
        path: String,
        contentType: String,
        progressHandler: ((Double) -> Void)?
    ) async throws {
        let session = try await client.auth.session
        let accessToken = session.accessToken
        
        let baseURL = SupabaseConfig.url
        let uploadURL = baseURL
            .appendingPathComponent("storage/v1/object")
            .appendingPathComponent(Self.bucketName)
            .appendingPathComponent(path)
        
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        
        // Use the extended timeout session
        let uploadSession = SecurityManager.shared.uploadSession
        
        logInfo(
            "SupabaseStorageService",
            "Dosya yükleniyor",
            details: "Boyut: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
        )
        
        // Use URLSession delegate for progress tracking
        let delegate = UploadProgressDelegate(totalBytes: Int64(data.count), progressHandler: progressHandler)
        let sessionWithDelegate = URLSession(configuration: uploadSession.configuration, delegate: delegate, delegateQueue: nil)
        
        let (responseData, response) = try await sessionWithDelegate.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.storageError("Geçersiz yanıt")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: responseData, encoding: .utf8) ?? "Bilinmeyen hata"
            logError(
                "SupabaseStorageService",
                "Yükleme başarısız: \(httpResponse.statusCode)",
                error: nil
            )
            
            // Check for file size limit error
            if httpResponse.statusCode == 413 || errorMessage.contains("Payload too large") {
                let fileSizeMB = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
                throw SupabaseError.storageError(
                    "Dosya boyutu çok büyük (\(fileSizeMB)). " +
                    "Supabase Dashboard'dan Storage → Settings → Global file size limit değerini artırın. " +
                    "Free plan'da maksimum 50 MB desteklenir, daha büyük dosyalar için Pro plan gereklidir."
                )
            }
            
            throw SupabaseError.storageError("Yükleme hatası: \(httpResponse.statusCode) - \(errorMessage)")
        }
        
        progressHandler?(1.0)
        logInfo("SupabaseStorageService", "Dosya başarıyla yüklendi")
    }

    /// Generate a unique storage path for a file
    func generateStoragePath(userId: String, fileName: String) -> String {
        let sanitizedName = sanitizeFileName(fileName)
        let timestamp = Int(Date().timeIntervalSince1970)
        return "\(userId.lowercased())/\(timestamp)_\(sanitizedName)"
    }

    // MARK: - Download Operations

    /// Get a signed URL for file download
    func getSignedURL(for storagePath: String) async throws -> URL {
        logDebug("SupabaseStorageService", "Getting signed URL for: \(storagePath)")

        let signedURL = try await client.storage
            .from(Self.bucketName)
            .createSignedURL(path: storagePath, expiresIn: Int(Self.signedURLExpiration))

        return signedURL
    }

    /// Download file data directly
    func downloadFile(path: String) async throws -> Data {
        try await client.storage
            .from(Self.bucketName)
            .download(path: path)
    }

    // MARK: - Delete Operations

    /// Delete a file from storage
    func deleteFile(path: String) async throws {
        try await client.storage
            .from(Self.bucketName)
            .remove(paths: [path])
    }

    /// Delete multiple files
    func deleteFiles(paths: [String]) async throws {
        try await client.storage
            .from(Self.bucketName)
            .remove(paths: paths)
    }

    // MARK: - Private Helpers

    private func sanitizeFileName(_ fileName: String) -> String {
        fileName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(
                of: "[^a-zA-Z0-9._-]",
                with: "",
                options: .regularExpression
            )
    }
}
