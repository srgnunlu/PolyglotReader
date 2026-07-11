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

        // 2. Content stream taraması: PDF'in GERÇEK görsel yerleşimleri.
        // Vision kenar tespitinin aksine tam sınırları verir; panelli
        // figürler parçalanmaz, altyazı/başlık metni kutuya karışmaz.
        if let exactBounds = detectImageFromContentStream(at: point, in: page) {
            logInfo("PDFImageService", "XObject görsel bulundu")
            return exactBounds
        }

        // 3. Vision ile Tarama (fallback — content stream'de görsel yoksa,
        // örn. vektör çizimli figürler)
        let regions = await visionHelper.detectImageRegions(in: page)

        // 4. Hit-Test: Hangi region noktayı içeriyor?
        // En "anlamlı" region'ı seç (en kapsamlı, yani area'sı büyük olan değil, en iyi cluster)
        // Helper zaten cluster edilmiş regionları döndürüyor.

        let hittingRegions = regions.filter { region in
            let hitRect = region.insetBy(dx: -20, dy: -20)
            return hitRect.contains(point)
        }

        if let bestRegion = hittingRegions.max(by: { $0.width * $0.height < $1.width * $1.height }) {
            // İkinci geçiş: seçilen kümeye yakın duran komşu kümeleri de kat.
            // Panelli figürlerde ilk kümeleme bazen figürün yalnız bir bölümünü
            // yakalar; kullanıcının dokunduğu bütünün geri kalanı bitişik ayrı
            // kümelerde kalır — burada tek bounding box'ta birleştirilir.
            let pageWidth = page.bounds(for: .mediaBox).width
            let mergeThreshold = max(30, pageWidth * 0.04)
            var merged = bestRegion
            var didGrow = true
            while didGrow {
                didGrow = false
                let expanded = merged.insetBy(dx: -mergeThreshold, dy: -mergeThreshold)
                for region in regions where region != merged && expanded.intersects(region) {
                    let candidate = merged.union(region)
                    if candidate != merged {
                        merged = candidate
                        didGrow = true
                    }
                }
            }
            logInfo("PDFImageService", "Vision görsel bulundu")
            return merged
        }

        // 5. Heuristic Fallback (Vision da bulamazsa)
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

    // MARK: - Content Stream Detection

    /// Sayfaya gerçekten yerleştirilmiş raster görsellerin sınırlarından,
    /// dokunulan noktayı içeren figürü bulur. Bir figür birden çok
    /// XObject'ten oluşabilir (paneller, katmanlı şeritler) — yakın parçalar
    /// önce kümelenir, karar bütün figüre verilir.
    private func detectImageFromContentStream(at point: CGPoint, in page: PDFPage) -> CGRect? {
        let pageBounds = page.bounds(for: .mediaBox)
        let rects = PDFImageXObjectLocator.shared.imageRects(on: page)
            .map { $0.intersection(pageBounds) }
            .filter { !$0.isEmpty && $0.width >= 12 && $0.height >= 12 }
        guard !rects.isEmpty else { return nil }

        // Tam sayfa kaplayan arka plan görselleri kümelemeye sokulmaz;
        // yoksa sayfadaki her figür arka planla tek dev kümede birleşirdi.
        let pageArea = pageBounds.width * pageBounds.height
        let figureRects = rects.filter { ($0.width * $0.height) <= pageArea * 0.85 }
        let backgroundRects = rects.filter { ($0.width * $0.height) > pageArea * 0.85 }

        let mergeThreshold = max(24, pageBounds.width * 0.03)
        let clusters = PDFImageVisionHelper.clusterRects(figureRects, proximityThreshold: mergeThreshold)

        // Noktayı içeren EN KÜÇÜK küme: iç içe adaylarda kullanıcının
        // kastettiği spesifik figürdür.
        let hits = clusters.filter { $0.insetBy(dx: -16, dy: -16).contains(point) }
        if let best = hits.min(by: { $0.width * $0.height < $1.width * $1.height }) {
            return best
        }

        // Figür bulunamadıysa ve nokta bir arka plan görselinin (taranmış
        // sayfa vb.) içindeyse onu döndür.
        return backgroundRects
            .filter { $0.contains(point) }
            .min { $0.width * $0.height < $1.width * $1.height }
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

    private func detectPotentialImageRegion(at point: CGPoint, in page: PDFPage, radius: CGFloat = 120) -> CGRect? {
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
