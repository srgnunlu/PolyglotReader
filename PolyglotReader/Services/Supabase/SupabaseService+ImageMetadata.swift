import Foundation

extension SupabaseService {
    // MARK: - Image Metadata

    func getImageMetadata(fileId: String) async throws -> [PDFImageMetadata] {
        try await perform(category: .database) {
            try await database.getImageMetadata(fileId: fileId)
        }
    }

    func saveImageMetadata(_ metadata: PDFImageMetadata) async throws {
        try await perform(category: .database) {
            try await database.saveImageMetadata(metadata)
        }
    }

    func saveImageMetadata(_ metadata: [PDFImageMetadata]) async throws {
        try await perform(category: .database) {
            try await database.saveImageMetadata(metadata)
        }
    }

    func updateImageCaption(imageId: String, caption: String, embedding: [Float]? = nil) async throws {
        try await perform(category: .database) {
            try await database.updateImageCaption(imageId: imageId, caption: caption, embedding: embedding)
        }
    }

    func searchImageCaptions(query: String, fileId: String) async throws -> [PDFImageMetadata] {
        try await perform(category: .database) {
            try await database.searchImageCaptions(query: query, fileId: fileId)
        }
    }

    func searchImageCaptions(
        embedding: [Float],
        fileId: String,
        limit: Int = 3,
        threshold: Float = 0.6
    ) async throws -> [PDFImageMetadata] {
        try await perform(category: .database) {
            try await database.searchImageCaptions(
                embedding: embedding,
                fileId: fileId,
                limit: limit,
                threshold: threshold
            )
        }
    }
}
