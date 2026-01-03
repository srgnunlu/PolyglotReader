import Foundation
import PDFKit
import UIKit
import Vision
import Combine

// MARK: - PDF Image Extractor
/// PDF'deki tüm görselleri tarayan ve metadata oluşturan servis
@MainActor
class PDFImageExtractor: ObservableObject {
    static let shared = PDFImageExtractor()
    
    @Published var isExtracting = false
    @Published var extractionProgress: Float = 0
    
    private init() {
        logInfo("PDFImageExtractor", "Servis başlatıldı")
    }
    
    // MARK: - Extract All Images from PDF
    
    /// PDF'deki tüm görselleri tespit eder ve metadata listesi döndürür
    /// - Parameters:
    ///   - document: PDF dokümanı
    ///   - fileId: Dosya ID'si
    /// - Returns: Tespit edilen görsellerin metadata listesi
    func extractAllImages(from document: PDFDocument, fileId: UUID) async -> [PDFImageMetadata] {
        isExtracting = true
        extractionProgress = 0
        defer { 
            isExtracting = false 
            extractionProgress = 1
        }
        
        var allImages: [PDFImageMetadata] = []
        let pageCount = document.pageCount
        
        logInfo("PDFImageExtractor", "Görsel taraması başlıyor", details: "\(pageCount) sayfa")
        
        for pageIndex in 0..<pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            
            let pageNumber = pageIndex + 1
            let pageImages = await extractImagesFromPage(page, pageNumber: pageNumber, fileId: fileId)
            allImages.append(contentsOf: pageImages)
            
            // İlerlemeyi güncelle
            extractionProgress = Float(pageIndex + 1) / Float(pageCount)
            
            // UI'ın güncellenmesine izin ver
            if pageIndex % 5 == 0 {
                try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
        }
        
        logInfo("PDFImageExtractor", "Görsel taraması tamamlandı", details: "\(allImages.count) görsel bulundu")
        return allImages
    }
    
    // MARK: - Extract Images from Single Page
    
    /// Tek bir sayfadaki görselleri tespit eder
    func extractImagesFromPage(_ page: PDFPage, pageNumber: Int, fileId: UUID) async -> [PDFImageMetadata] {
        var images: [PDFImageMetadata] = []
        
        // 1. Vision ile dikdörtgen tespiti
        let detectedRects = await detectImageRectsWithVision(in: page)
        
        // 2. Tespit edilen her dikdörtgen için metadata oluştur
        for (index, rect) in detectedRects.enumerated() {
            // Thumbnail oluştur (küçük boyutlu)
            let thumbnail = renderRegionAsThumbnail(rect: rect, in: page, maxSize: 150)
            let thumbnailBase64 = thumbnail?.jpegData(compressionQuality: 0.6)?.base64EncodedString()
            
            let metadata = PDFImageMetadata(
                fileId: fileId,
                pageNumber: pageNumber,
                imageIndex: index,
                bounds: ImageBounds(rect: rect),
                thumbnailBase64: thumbnailBase64
            )
            
            images.append(metadata)
        }
        
        if !images.isEmpty {
            logDebug("PDFImageExtractor", "Sayfa \(pageNumber)", details: "\(images.count) görsel tespit edildi")
        }
        
        return images
    }
    
    // MARK: - Vision-Based Detection
    
    private func detectImageRectsWithVision(in page: PDFPage) async -> [CGRect] {
        // MainActor'dan çıkıp arka planda çalıştır
        let scale: CGFloat = 1.5
        guard let pageImage = renderPageAsImage(page: page, scale: scale),
              let cgImage = pageImage.cgImage else {
            return []
        }
        
        // Sayfa bounds'unu önceden al
        let pageBounds = page.bounds(for: .mediaBox)
        
        // Vision işlemini detached task'ta çalıştır
        return await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return [CGRect]() }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            
            var detectedRects: [CGRect] = []
            
            let request = VNDetectRectanglesRequest { request, error in
                guard error == nil,
                      let results = request.results as? [VNRectangleObservation] else {
                    return
                }
                
                for observation in results {
                    let rect = observation.boundingBox
                    let pdfRect = CGRect(
                        x: rect.origin.x * pageBounds.width,
                        y: rect.origin.y * pageBounds.height,
                        width: rect.size.width * pageBounds.width,
                        height: rect.size.height * pageBounds.height
                    )
                    
                    // Minimum boyut filtresi (40pt x 40pt)
                    guard pdfRect.width > 40 && pdfRect.height > 40 else { continue }
                    
                    // Çok büyük dikdörtgenleri atla (sayfa boyutunun %90'ından büyük)
                    let maxArea = pageBounds.width * pageBounds.height * 0.9
                    guard pdfRect.width * pdfRect.height < maxArea else { continue }
                    
                    detectedRects.append(pdfRect)
                }
            }
            
            // Detection ayarları
            request.minimumConfidence = 0.4
            request.minimumAspectRatio = 0.1
            request.quadratureTolerance = 20
            request.minimumSize = 0.05
            request.maximumObservations = 20
            
            do {
                try handler.perform([request])
            } catch {
                return []
            }
            
            // Birbirine çok yakın dikdörtgenleri birleştir
            return await self.mergeOverlappingRectsAsync(detectedRects)
        }.value
    }
    
    /// Thread-safe merge işlemi
    private nonisolated func mergeOverlappingRectsAsync(_ rects: [CGRect]) async -> [CGRect] {
        guard !rects.isEmpty else { return [] }
        
        var merged = rects
        var changed = true
        
        while changed {
            changed = false
            var newMerged: [CGRect] = []
            var skip: Set<Int> = []
            
            for i in 0..<merged.count {
                if skip.contains(i) { continue }
                
                var current = merged[i]
                
                for j in (i+1)..<merged.count {
                    if skip.contains(j) { continue }
                    
                    let expanded = current.insetBy(dx: -20, dy: -20)
                    if expanded.intersects(merged[j]) {
                        current = current.union(merged[j])
                        skip.insert(j)
                        changed = true
                    }
                }
                
                newMerged.append(current)
            }
            
            merged = newMerged
        }
        
        return merged
    }
    
    // MARK: - Helper Methods
    
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
    
    /// Belirli bir bölgeyi thumbnail olarak render et
    func renderRegionAsThumbnail(rect: CGRect, in page: PDFPage, maxSize: CGFloat) -> UIImage? {
        let scale: CGFloat = 2.0
        let renderSize = CGSize(
            width: rect.width * scale,
            height: rect.height * scale
        )
        
        // Boyutu sınırla
        let aspectRatio = renderSize.width / renderSize.height
        var finalSize = renderSize
        
        if renderSize.width > maxSize || renderSize.height > maxSize {
            if aspectRatio > 1 {
                finalSize = CGSize(width: maxSize, height: maxSize / aspectRatio)
            } else {
                finalSize = CGSize(width: maxSize * aspectRatio, height: maxSize)
            }
        }
        
        let scaleX = finalSize.width / rect.width
        let scaleY = finalSize.height / rect.height
        
        let renderer = UIGraphicsImageRenderer(size: finalSize)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: finalSize))
            
            context.cgContext.translateBy(x: -rect.origin.x * scaleX, y: finalSize.height + rect.origin.y * scaleY)
            context.cgContext.scaleBy(x: scaleX, y: -scaleY)
            
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }
    
    /// Tam boyutlu görsel render et (AI analizi için)
    func renderRegionFullSize(rect: CGRect, in page: PDFPage) -> UIImage? {
        let scale: CGFloat = 2.0
        let renderSize = CGSize(
            width: rect.width * scale,
            height: rect.height * scale
        )
        
        let renderer = UIGraphicsImageRenderer(size: renderSize)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: renderSize))
            
            context.cgContext.translateBy(x: -rect.origin.x * scale, y: renderSize.height + rect.origin.y * scale)
            context.cgContext.scaleBy(x: scale, y: -scale)
            
            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }
    
    private func isRegionPredominantlyText(rect: CGRect, in page: PDFPage) -> Bool {
        guard let selection = page.selection(for: rect) else { return false }
        let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // Eğer 50 karakterden fazla metin varsa, muhtemelen metin bloğudur
        return text.count > 50
    }
    
    private func mergeOverlappingRects(_ rects: [CGRect]) -> [CGRect] {
        guard !rects.isEmpty else { return [] }
        
        var merged = rects
        var changed = true
        
        while changed {
            changed = false
            var newMerged: [CGRect] = []
            var skip: Set<Int> = []
            
            for i in 0..<merged.count {
                if skip.contains(i) { continue }
                
                var current = merged[i]
                
                for j in (i+1)..<merged.count {
                    if skip.contains(j) { continue }
                    
                    let expanded = current.insetBy(dx: -20, dy: -20)
                    if expanded.intersects(merged[j]) {
                        current = current.union(merged[j])
                        skip.insert(j)
                        changed = true
                    }
                }
                
                newMerged.append(current)
            }
            
            merged = newMerged
        }
        
        return merged
    }
    
    // MARK: - Get Images for Page
    
    /// Belirli bir sayfadaki görselleri getir (cache veya yeniden tespit)
    func getImagesForPage(
        _ page: PDFPage,
        pageNumber: Int,
        fileId: UUID,
        cachedImages: [PDFImageMetadata]
    ) async -> [PDFImageMetadata] {
        // Önce cache'e bak
        let cached = cachedImages.filter { $0.pageNumber == pageNumber }
        if !cached.isEmpty {
            return cached
        }
        
        // Cache'de yoksa tespit et
        return await extractImagesFromPage(page, pageNumber: pageNumber, fileId: fileId)
    }
}

