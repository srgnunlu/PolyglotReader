import Foundation
import PDFKit
import Vision
import UIKit

// MARK: - PDF Image Vision Helper
/// Vision framework ile PDF üzerindeki görselleri tespit eden yardımcı sınıf
class PDFImageVisionHelper {
    static let shared = PDFImageVisionHelper()

    private init() {}

    // MARK: - Public API

    /// Sayfadaki tüm görsel adaylarını tespit eder (Async)
    func detectImageRegions(in page: PDFPage) async -> [CGRect] {
        // 1. Sayfayı render et
        guard let pageImage = renderPageAsImage(page: page, scale: 2.0),
              let cgImage = pageImage.cgImage else {
            return []
        }

        // 2. Vision isteği oluştur
        return await performVisionRequest(on: cgImage, page: page)
    }

    /// Sayfanın belirli bir bölgesini render eder
    func renderRegion(rect: CGRect, in page: PDFPage, scale: CGFloat = 2.0) -> UIImage? {
        let size = CGSize(
            width: rect.width * scale,
            height: rect.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // Koordinat dönüşümü: PDF (kare, sol-alt) -> Image (sol-üst)
            context.cgContext.translateBy(x: -rect.origin.x * scale, y: size.height + rect.origin.y * scale)
            context.cgContext.scaleBy(x: scale, y: -scale)

            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }

    // MARK: - Internal Logic

    private func renderPageAsImage(page: PDFPage, scale: CGFloat) -> UIImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let size = CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)

            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }

    private func performVisionRequest(on cgImage: CGImage, page: PDFPage) async -> [CGRect] {
        let pageBounds = page.bounds(for: .mediaBox)

        let candidateRects = await Task.detached(priority: .userInitiated) {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)

            var candidateRects: [CGRect] = []

            let request = VNDetectRectanglesRequest { request, error in
                guard error == nil, let results = request.results as? [VNRectangleObservation] else { return }

                for observation in results {
                    let rect = observation.boundingBox
                    let pdfRect = CGRect(
                        x: rect.origin.x * pageBounds.width,
                        y: rect.origin.y * pageBounds.height,
                        width: rect.size.width * pageBounds.width,
                        height: rect.size.height * pageBounds.height
                    )

                    candidateRects.append(pdfRect)
                }
            }

            // Agresif ayarlar
            request.minimumConfidence = 0.3
            request.minimumAspectRatio = 0.05
            request.quadratureTolerance = 25
            request.minimumSize = 0.03
            request.maximumObservations = 0

            do {
                try handler.perform([request])
            } catch {
                logWarning(
                    "PDFImageVisionHelper",
                    "Vision istegi basarisiz",
                    details: error.localizedDescription
                )
            }

            return candidateRects
        }.value

        let filteredRects = candidateRects.filter { Self.isValidImageRegion($0, in: page) }
        return Self.clusterRects(filteredRects)
    }

    private static func isValidImageRegion(_ rect: CGRect, in page: PDFPage) -> Bool {
        // Boyut kontrolü
        if rect.width < 20 || rect.height < 20 { return false }

        // Metin yoğunluğu kontrolü using helper
        if PDFTextExtractorHelper.isRegionPredominantlyText(rect: rect, in: page) {
            return false
        }

        return true
    }

    // Union-Find ile Kümeleme
    private static func clusterRects(_ rects: [CGRect]) -> [CGRect] {
        guard !rects.isEmpty else { return [] }

        var parent = Array(0..<rects.count)

        func find(_ i: Int) -> Int {
            if parent[i] == i { return i }
            parent[i] = find(parent[i])
            return parent[i]
        }

        func union(_ i: Int, _ otherIndex: Int) {
            let rootI = find(i)
            let rootOther = find(otherIndex)
            if rootI != rootOther {
                parent[rootI] = rootOther
            }
        }

        let proximityThreshold: CGFloat = 30.0

        for i in 0..<rects.count {
            for otherIndex in (i + 1)..<rects.count {
                let expanded = rects[i].insetBy(dx: -proximityThreshold, dy: -proximityThreshold)
                if expanded.intersects(rects[otherIndex]) {
                    union(i, otherIndex)
                }
            }
        }

        var clusters: [Int: CGRect] = [:]
        for i in 0..<rects.count {
            let root = find(i)
            if let existing = clusters[root] {
                clusters[root] = existing.union(rects[i])
            } else {
                clusters[root] = rects[i]
            }
        }

        return Array(clusters.values)
    }
}

// MARK: - Text Helper
// PDFTextExtractor'dan text kontrolünü buraya alabiliriz veya basit bir static func ekleyebiliriz
struct PDFTextExtractorHelper {
    static func isRegionPredominantlyText(rect: CGRect, in page: PDFPage) -> Bool {
        guard let selection = page.selection(for: rect) else { return false }
        let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.count > 50
    }
}
