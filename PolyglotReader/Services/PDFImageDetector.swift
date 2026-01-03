import Foundation
import PDFKit
import UIKit
import Vision

// MARK: - PDF Image Detector

/// PDF sayfasındaki görsel bölgelerini tespit eden servis
/// Vision framework ve Annotation-based yöntemleri birleştirir
class PDFImageDetector {
    
    static let shared = PDFImageDetector()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Verilen noktada bir görsel var mı kontrol eder (Async)
    /// - Parameters:
    ///   - point: PDF sayfası koordinatlarında nokta
    ///   - page: Kontrol edilecek sayfa
    ///   - completion: Sonuç (Bounds) ile döner
    func detectImage(at point: CGPoint, in page: PDFPage, completion: @escaping (CGRect?) -> Void) {
        // 1. Önce hızlı annotation kontrolü
        if let annotationBounds = detectAnnotationImage(at: point, in: page) {
            logInfo("PDFImageDetector", "Annotation-based görsel bulundu")
            completion(annotationBounds)
            return
        }
        
        // 2. Vision ile sayfa analizi yap
        detectImageWithVision(at: point, in: page) { visionBounds in
            if let bounds = visionBounds {
                logInfo("PDFImageDetector", "Vision-based görsel bulundu")
                completion(bounds)
            } else {
                // 3. Son çare: Heuristic kontrolü
                // Metin olmayan bir alandaysa ve etrafında metin yoksa
                let heuristicBounds = self.detectPotentialImageRegion(at: point, in: page)
                if let bounds = heuristicBounds {
                    logInfo("PDFImageDetector", "Heuristic görsel bölgesi bulundu")
                    completion(bounds)
                } else {
                    completion(nil)
                }
            }
        }
    }
    
    // MARK: - Vision-Based Detection
    
    private func detectImageWithVision(at point: CGPoint, in page: PDFPage, completion: @escaping (CGRect?) -> Void) {
        // Sayfayı yüksek çözünürlükte render et
        let scale: CGFloat = 2.0
        guard let pageImage = renderPageAsImage(page: page, scale: scale) else {
            completion(nil)
            return
        }
        
        guard let cgImage = pageImage.cgImage else {
            completion(nil)
            return
        }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
        
        let request = VNDetectRectanglesRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                logError("PDFImageDetector", "Vision hatası", error: error)
                completion(nil)
                return
            }
            
            guard let results = request.results as? [VNRectangleObservation] else {
                completion(nil)
                return
            }
            
            // PDF koordinatlarına çevir
            let pageBounds = page.bounds(for: .mediaBox)
            
            // 1. Tüm geçerli dikdörtgenleri topla
            var candidateRects: [CGRect] = []
            
            for observation in results {
                let rect = observation.boundingBox
                let pdfRect = CGRect(
                    x: rect.origin.x * pageBounds.width,
                    y: rect.origin.y * pageBounds.height,
                    width: rect.size.width * pageBounds.width,
                    height: rect.size.height * pageBounds.height
                )
                
                // Çok küçük gürültüleri ele (10pt altı)
                if pdfRect.width > 20 && pdfRect.height > 20 {
                    // TEXT FILTER:
                    // Eğer bu bölge yoğun metin içeriyorsa, görsel değildir.
                    if self.isRegionPredominantlyText(rect: pdfRect, in: page) {
                        continue
                    }
                    
                    candidateRects.append(pdfRect)
                }
            }
            
            // 2. KÜMELEME (CLUSTERING) - Connected Components Logic
            // Sayfadaki tüm dikdörtgenleri analiz et ve birbirine yakın olanları grupla.
            // Bu, tabloların hücrelerini veya diyagramların parçalarını "tek bir obje" olarak algılamayı sağlar.
            
            var components: [Int: [CGRect]] = [:] // Component ID -> Rects
            var parent: [Int] = Array(0..<candidateRects.count) // Union-Find yapısı
            
            func find(_ i: Int) -> Int {
                if parent[i] == i { return i }
                parent[i] = find(parent[i])
                return parent[i]
            }
            
            func union(_ i: Int, _ j: Int) {
                let rootI = find(i)
                let rootJ = find(j)
                if rootI != rootJ {
                    parent[rootI] = rootJ
                }
            }
            
            // Çakışan veya yakın olanları birleştir
            // O(N^2) ama N (dikdörtgen sayısı) genelde küçüktür (<50)
            let proximityThreshold: CGFloat = 30.0 // 30pt yakınlık toleransı
            
            for i in 0..<candidateRects.count {
                for j in (i+1)..<candidateRects.count {
                    let rect1 = candidateRects[i]
                    let rect2 = candidateRects[j]
                    
                    let expandedRect1 = rect1.insetBy(dx: -proximityThreshold, dy: -proximityThreshold)
                    
                    if expandedRect1.intersects(rect2) {
                        union(i, j)
                    }
                }
            }
            
            // Grupları oluştur
            var clusters: [Int: CGRect] = [:] // Root ID -> Bounding Box
            
            for i in 0..<candidateRects.count {
                let root = find(i)
                let rect = candidateRects[i]
                
                if let existing = clusters[root] {
                    clusters[root] = existing.union(rect)
                } else {
                    clusters[root] = rect
                }
            }
            
            // 3. Tıklanan noktayı içeren EN UYGUN kümeyi bul
            var bestCluster: CGRect?
            var minDistanceToCenter: CGFloat = CGFloat.greatestFiniteMagnitude
            
            // Hit-test ve seçim
            // Önce direkt içinde olduklarımıza bak
            var hittingClusters: [CGRect] = []
            
            for (_, clusterRect) in clusters {
                // Tıklama toleransı (parmak kalınlığı için)
                let hitRect = clusterRect.insetBy(dx: -20, dy: -20)
                
                if hitRect.contains(point) {
                    hittingClusters.append(clusterRect)
                }
            }
            
            if !hittingClusters.isEmpty {
                // Birden fazla küme içindeysek, alanı en büyük olanı değil,
                // EN KAPSAMLI olanı (yani muhtemelen tabloyu) seç.
                // Genellikle en büyük alanlı olan doğrudur (hücre yerine tüm tablo).
                // Sıralama: Alanı büyükten küçüğe
                hittingClusters.sort { ($0.width * $0.height) > ($1.width * $1.height) }
                bestCluster = hittingClusters.first
            } else {
                // Hiçbir kümenin içinde değilsek, en yakındakini bul (belirli bir mesafedeyse)
                let maxDistance: CGFloat = 80.0
                
                for (_, clusterRect) in clusters {
                    let center = CGPoint(x: clusterRect.midX, y: clusterRect.midY)
                    let dist = hypot(center.x - point.x, center.y - point.y)
                    
                    // Ya merkeze yakındır ya da kenara çok yakındır
                    let dx = max(clusterRect.minX - point.x, 0, point.x - clusterRect.maxX)
                    let dy = max(clusterRect.minY - point.y, 0, point.y - clusterRect.maxY)
                    let distanceToBorder = sqrt(dx*dx + dy*dy)
                    
                    if distanceToBorder < maxDistance {
                        if distanceToBorder < minDistanceToCenter {
                            minDistanceToCenter = distanceToBorder
                            bestCluster = clusterRect
                        }
                    }
                }
            }
            
            // 4. Sonuç
            completion(bestCluster)
        }
        
        // Daha agresif detection ayarları
        request.minimumConfidence = 0.3 // Daha düşük güven oranlı kenarları da al (tablo çizgileri için)
        request.minimumAspectRatio = 0.05 // İnce sütunları/satırları kaçırma
        request.quadratureTolerance = 25 // Biraz yamuk olsa bile kabul et
        request.minimumSize = 0.03 // Küçük detayları da gör
        request.maximumObservations = 0 // Limit yok (tümünü bul)
        
        // Arka planda çalıştır
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                logError("PDFImageDetector", "Handler çalıştırılamadı", error: error)
                completion(nil)
            }
        }
    }
    
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
    
    // MARK: - Annotation-Based Detection
    
    private func detectAnnotationImage(at point: CGPoint, in page: PDFPage) -> CGRect? {
        for annotation in page.annotations {
            let bounds = annotation.bounds
            
            // Tam bounds kontrolü
            if bounds.contains(point) {
                if isImageAnnotation(annotation) {
                    return bounds
                }
            }
            
            // Yakınlık kontrolü (20pt margin)
            let expandedBounds = bounds.insetBy(dx: -20, dy: -20)
            if expandedBounds.contains(point) && isImageAnnotation(annotation) {
                return bounds
            }
        }
        
        return nil
    }
    
    private func isImageAnnotation(_ annotation: PDFAnnotation) -> Bool {
        // Görsel olabilecek annotation tipleri
        let imageTypes: Set<String?> = [nil, "Widget", "Stamp", "Square", "Circle"]
        
        // Link annotation'larını hariç tut (genellikle metin üzerindedir)
        if annotation.type == "Link" { return false }
        if annotation.type == "Highlight" { return false }
        if annotation.type == "Underline" { return false }
        
        if let type = annotation.type, imageTypes.contains(type) {
            return true
        }
        
        // Nil type annotations da görsel olabilir
        if annotation.type == nil {
            return true
        }
        
        return false
    }
    
    // MARK: - Heuristic Detection
    
    /// Heuristic: Belirli bir alan etrafında metin yoksa görsel olabilir
    private func detectPotentialImageRegion(at point: CGPoint, in page: PDFPage, radius: CGFloat = 80) -> CGRect? {
        // Noktanın olduğu yerde metin var mı?
        if let selection = page.selectionForWord(at: point),
           let text = selection.string,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        
        // Etraf kontrolü
        let testPoints = [
            CGPoint(x: point.x - 30, y: point.y),
            CGPoint(x: point.x + 30, y: point.y),
            CGPoint(x: point.x, y: point.y - 30),
            CGPoint(x: point.x, y: point.y + 30)
        ]
        
        for testPoint in testPoints {
            if let selection = page.selectionForWord(at: testPoint),
               let text = selection.string,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Çok yakınında metin var, muhtemelen görsel değil boşluk
                return nil
            }
        }
        
        // Metin yok, potansiyel görsel bölgesi
        // Bölge boyutunu tahmin et (kare varsayımı)
        return CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    }
    
    // MARK: - Text Collision Helper
    
    private func isRegionPredominantlyText(rect: CGRect, in page: PDFPage) -> Bool {
        // Bölgedeki metni al
        guard let selection = page.selection(for: rect) else { return false }
        let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if text.isEmpty { return false }
        
        // Metin yoğunluğunu hesapla
        // Eğer bölge küçükse ve içinde çok karakter varsa -> Metin bloğudur
        // Eğer bölge büyükse ve içinde az karakter varsa -> Diyagram/Tablo olabilir
        
        // Basit kontrol: Eğer 30 karakterden fazla varsa ve
        // bu karakterler alanın büyük kısmına yayılmışsa, metindir.
        if text.count > 30 {
            return true
        }
        
        return false
    }
}

