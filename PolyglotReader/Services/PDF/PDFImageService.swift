import Foundation
import PDFKit
import UIKit
import Combine

// MARK: - PDF Image Service
/// PDF görsel işlemlerini (tespit, çıkarma) yöneten birleşik servis.
/// Vision tabanlı tespit ve çıkarma akışını tek noktada toplar.
/// NOT: MainActor'dan çıkarıldı - görsel işlemleri background thread'de yapılmalı
class PDFImageService: ObservableObject {
    static let shared = PDFImageService()

    @MainActor @Published var isExtracting = false
    @MainActor @Published var extractionProgress: Float = 0

    private let visionHelper = PDFImageVisionHelper.shared

    private init() {
        Task { @MainActor in
            logInfo("PDFImageService", "Servis başlatıldı")
        }
    }

    // MARK: - Interactive Detection (Single Tap)

    /// Bir noktadaki görseli tespit eder (Kullanıcı dokunuşu için)
    func detectImage(at point: CGPoint, in page: PDFPage) async -> CGRect? {
        // 1. Hızlı Annotation Kontrolü
        if let annotationBounds = detectAnnotationImage(at: point, in: page) {
            logInfo("PDFImageService", "Annotation görsel bulundu")
            return annotationBounds
        }

        // 2. Vision ile Taraması
        // Tüm sayfayı taramak yerine, sadece noktaya yakın adayları bulabiliriz
        // Ancak tutarlılık için helper'ı kullanıp hit-test yapacağız.
        let regions = await visionHelper.detectImageRegions(in: page)

        // 3. Hit-Test: Hangi region noktayı içeriyor?
        // En "anlamlı" region'ı seç (en kapsamlı, yani area'sı büyük olan değil, en iyi cluster)
        // Helper zaten cluster edilmiş regionları döndürüyor.

        let hittingRegions = regions.filter { region in
            let hitRect = region.insetBy(dx: -20, dy: -20)
            return hitRect.contains(point)
        }

        if let bestRegion = hittingRegions.max(by: { $0.width * $0.height < $1.width * $1.height }) {
             logInfo("PDFImageService", "Vision görsel bulundu")
            return bestRegion
        }

        // 4. Heuristic Fallback (Vision bulamazsa)
        if let heuristic = detectPotentialImageRegion(at: point, in: page) {
            logInfo("PDFImageService", "Heuristic görsel bulundu")
            return heuristic
        }

        return nil
    }

    // MARK: - Batch Extraction

    /// Dokümandaki TÜM görselleri çıkarır
    /// NOT: Bu işlem ağır olabilir, background thread'de çağırılmalı
    func extractAllImages(from document: PDFDocument, fileId: UUID) async -> [PDFImageMetadata] {
        await MainActor.run {
            isExtracting = true
            extractionProgress = 0
        }
        defer {
            Task { @MainActor in
                isExtracting = false
                extractionProgress = 1
            }
        }

        var allImages: [PDFImageMetadata] = []
        let pageCount = document.pageCount

        await MainActor.run {
            logInfo("PDFImageService", "Toplu görsel tarama başladı", details: "\(pageCount) sayfa")
        }

        for pageIndex in 0..<pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let pageNumber = pageIndex + 1

            let images = await extractImagesFromPage(page, pageNumber: pageNumber, fileId: fileId)
            allImages.append(contentsOf: images)

            await MainActor.run {
                extractionProgress = Float(pageIndex + 1) / Float(pageCount)
            }

            // Daha uzun yield - main thread'i boşalt
            if pageIndex % 5 == 0 {
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            }
        }

        return allImages
    }

    /// Tek bir sayfadaki görselleri çıkarır
    func extractImagesFromPage(_ page: PDFPage, pageNumber: Int, fileId: UUID) async -> [PDFImageMetadata] {
        let regions = await visionHelper.detectImageRegions(in: page)
        var metadataList: [PDFImageMetadata] = []

        for (index, rect) in regions.enumerated() {
            // Thumbnail oluştur
            let thumbnail = visionHelper.renderRegion(rect: rect, in: page, scale: 0.5) // Thumbnail için düşük scale
            let thumbnailBase64 = thumbnail?.jpegData(compressionQuality: 0.5)?.base64EncodedString()

            let metadata = PDFImageMetadata(
                fileId: fileId,
                pageNumber: pageNumber,
                imageIndex: index,
                bounds: ImageBounds(rect: rect),
                thumbnailBase64: thumbnailBase64
            )
            metadataList.append(metadata)
        }

        return metadataList
    }

    /// Cache destekli görsel getirme
    func getImagesForPage(
        _ page: PDFPage,
        pageNumber: Int,
        fileId: UUID,
        cachedImages: [PDFImageMetadata]
    ) async -> [PDFImageMetadata] {
        let cached = cachedImages.filter { $0.pageNumber == pageNumber }
        if !cached.isEmpty { return cached }
        return await extractImagesFromPage(page, pageNumber: pageNumber, fileId: fileId)
    }

    /// Belirli bir bölgeyi tam boyutlu render eder
    func renderRegionFullSize(rect: CGRect, in page: PDFPage) -> UIImage? {
        visionHelper.renderRegion(rect: rect, in: page, scale: 2.0)
    }

    // MARK: - Helpers

    private func detectAnnotationImage(at point: CGPoint, in page: PDFPage) -> CGRect? {
        let ignoredTypes: Set<String> = ["Link", "Highlight", "Underline"]
        for annotation in page.annotations {
            guard let type = annotation.type, !ignoredTypes.contains(type) else { continue }
            let bounds = annotation.bounds
            if bounds.contains(point) || bounds.insetBy(dx: -20, dy: -20).contains(point) {
                return bounds
            }
        }
        return nil
    }

    private func detectPotentialImageRegion(at point: CGPoint, in page: PDFPage, radius: CGFloat = 80) -> CGRect? {
        // Basit boşluk kontrolü
        if let selection = page.selectionForWord(at: point),
           let text = selection.string,
           !text.trimmed.isEmpty {
            return nil
        }
        // ... (Detaylı heuristic buraya eklenebilir, şimdilik basit)
        return CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
    }
}

fileprivate extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
