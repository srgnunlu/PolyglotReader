import Foundation
import PDFKit

/// Renders PDF page images and runs Gemini vision analysis on them, then persists
/// the resulting captions/embeddings to Supabase.
///
/// Extracted from `ChatViewModel` to keep the view model focused on chat
/// orchestration rather than the image-analysis pipeline.
@MainActor
final class PDFImageAnalysisService {
    static let shared = PDFImageAnalysisService()

    private let imageService = PDFImageService.shared
    private let geminiService = GeminiService.shared
    private let supabaseService = SupabaseService.shared

    private init() {}

    /// Analyzes the not-yet-analyzed images in `images`, persists their captions,
    /// and returns the results so the caller can refresh its in-memory cache.
    func analyzeUnanalyzedImages(
        _ images: [PDFImageMetadata],
        document: PDFDocument
    ) async -> [ImageAnalysisResult] {
        let requests = buildAnalysisRequests(from: images, document: document)
        guard !requests.isEmpty else { return [] }

        let results = await geminiService.batchAnalyzeImages(requests)
        await persistCaptions(results)
        return results
    }

    // MARK: - Request Building

    private func buildAnalysisRequests(
        from images: [PDFImageMetadata],
        document: PDFDocument
    ) -> [ImageAnalysisRequest] {
        let unanalyzed = images.filter { !$0.isAnalyzed }
        guard !unanalyzed.isEmpty else { return [] }

        return unanalyzed.compactMap { makeAnalysisRequest(for: $0, document: document) }
    }

    private func makeAnalysisRequest(
        for image: PDFImageMetadata,
        document: PDFDocument
    ) -> ImageAnalysisRequest? {
        guard let bounds = image.bounds,
              let page = document.page(at: image.pageNumber - 1),
              let renderedImage = imageService.renderRegionFullSize(
                rect: bounds.cgRect,
                in: page
              ),
              let jpegData = renderedImage.jpegData(compressionQuality: 0.8) else {
            return nil
        }

        let contextRect = bounds.cgRect.insetBy(dx: -50, dy: -50)
        let context = page.selection(for: contextRect)?.string

        return ImageAnalysisRequest(
            imageId: image.id,
            imageData: jpegData,
            pageNumber: image.pageNumber,
            context: context
        )
    }

    // MARK: - Persistence

    private func persistCaptions(_ results: [ImageAnalysisResult]) async {
        for result in results {
            do {
                try await supabaseService.updateImageCaption(
                    imageId: result.imageId.uuidString,
                    caption: result.caption,
                    embedding: result.captionEmbedding
                )
            } catch {
                logWarning(
                    "PDFImageAnalysisService",
                    "Görsel açıklaması güncellenemedi",
                    details: error.localizedDescription
                )
            }
        }
    }
}
