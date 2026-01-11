import Foundation
import UIKit

// MARK: - PDF Image Metadata Model
/// PDF'den çıkarılan görsel bilgisi (veritabanı ile senkronize)
struct PDFImageMetadata: Identifiable, Codable {
    let id: UUID
    let fileId: UUID
    let pageNumber: Int
    let imageIndex: Int
    let bounds: ImageBounds?
    var thumbnailBase64: String?
    var caption: String?
    var analyzedAt: Date?
    let createdAt: Date

    // CodingKeys for snake_case <-> camelCase conversion
    enum CodingKeys: String, CodingKey {
        case id
        case fileId = "file_id"
        case pageNumber = "page_number"
        case imageIndex = "image_index"
        case bounds
        case thumbnailBase64 = "thumbnail_base64"
        case caption
        case analyzedAt = "analyzed_at"
        case createdAt = "created_at"
    }

    init(
        id: UUID = UUID(),
        fileId: UUID,
        pageNumber: Int,
        imageIndex: Int = 0,
        bounds: ImageBounds? = nil,
        thumbnailBase64: String? = nil,
        caption: String? = nil,
        analyzedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileId = fileId
        self.pageNumber = pageNumber
        self.imageIndex = imageIndex
        self.bounds = bounds
        self.thumbnailBase64 = thumbnailBase64
        self.caption = caption
        self.analyzedAt = analyzedAt
        self.createdAt = createdAt
    }

    /// Görsel analiz edilmiş mi?
    var isAnalyzed: Bool {
        analyzedAt != nil && caption != nil
    }

    /// Thumbnail'ı UIImage olarak döndür
    var thumbnailImage: UIImage? {
        guard let base64 = thumbnailBase64,
              let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - Image Bounds
/// Görsel koordinatları (PDF sayfa koordinat sisteminde)
struct ImageBounds: Codable, Equatable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    init(rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.width
        self.height = rect.height
    }

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

// MARK: - Page Image Info
/// Bir sayfadaki tüm görseller için özet bilgi
struct PageImagesInfo {
    let pageNumber: Int
    let images: [PDFImageMetadata]

    var imageCount: Int { images.count }
    var hasImages: Bool { !images.isEmpty }
    var hasUnanalyzedImages: Bool { images.contains { !$0.isAnalyzed } }
}

// MARK: - Image Analysis Request
/// Görsel analiz isteği
struct ImageAnalysisRequest {
    let imageId: UUID
    let imageData: Data
    let pageNumber: Int
    let context: String?  // Opsiyonel: Çevredeki metin bağlamı
}

// MARK: - Image Analysis Result
/// Görsel analiz sonucu
struct ImageAnalysisResult {
    let imageId: UUID
    let caption: String
    let captionEmbedding: [Float]?
    let analyzedAt: Date

    init(imageId: UUID, caption: String, captionEmbedding: [Float]? = nil) {
        self.imageId = imageId
        self.caption = caption
        self.captionEmbedding = captionEmbedding
        self.analyzedAt = Date()
    }
}

// MARK: - Supabase Response Types
extension PDFImageMetadata {
    /// Supabase'den gelen veriyi parse etmek için
    struct SupabaseRecord: Decodable {
        let id: UUID
        let file_id: UUID
        let page_number: Int
        let image_index: Int
        let bounds: ImageBounds?
        let thumbnail_base64: String?
        let caption: String?
        let analyzed_at: String?
        let created_at: String

        func toModel() -> PDFImageMetadata {
            let dateFormatter = ISO8601DateFormatter()

            return PDFImageMetadata(
                id: id,
                fileId: file_id,
                pageNumber: page_number,
                imageIndex: image_index,
                bounds: bounds,
                thumbnailBase64: thumbnail_base64,
                caption: caption,
                analyzedAt: analyzed_at.flatMap { dateFormatter.date(from: $0) },
                createdAt: dateFormatter.date(from: created_at) ?? Date()
            )
        }
    }

    /// Supabase'e kaydetmek için
    struct InsertPayload: Encodable {
        let file_id: UUID
        let page_number: Int
        let image_index: Int
        let bounds: ImageBounds?
        let thumbnail_base64: String?
    }

    /// Caption güncelleme için
    struct CaptionUpdatePayload: Encodable {
        let caption: String
        let caption_embedding: String?  // pgvector format
        let analyzed_at: String
    }
}
