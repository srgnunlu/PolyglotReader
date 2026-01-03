import Foundation
import PDFKit
import UIKit

// MARK: - PDF Service
class PDFService {
    static let shared = PDFService()
    
    private init() {}
    
    // MARK: - Load PDF
    
    func loadPDF(from url: URL) -> PDFDocument? {
        return PDFDocument(url: url)
    }
    
    func loadPDF(from data: Data) -> PDFDocument? {
        return PDFDocument(data: data)
    }
    
    // MARK: - Text Extraction
    
    func extractText(from document: PDFDocument) -> String {
        var fullText = ""
        
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            if let pageText = page.string {
                fullText += "--- Sayfa \(pageIndex + 1) ---\n"
                fullText += pageText
                fullText += "\n\n"
            }
        }
        
        return fullText
    }
    
    func extractText(from page: PDFPage) -> String {
        return page.string ?? ""
    }
    
    // MARK: - Page Rendering
    
    func renderPageAsImage(page: PDFPage, scale: CGFloat = 2.0) -> UIImage? {
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
    
    func renderPagesAsImages(document: PDFDocument, maxPages: Int = 20, scale: CGFloat = 1.5) -> [Data] {
        var images: [Data] = []
        let pageCount = min(document.pageCount, maxPages)
        
        for pageIndex in 0..<pageCount {
            guard let page = document.page(at: pageIndex),
                  let image = renderPageAsImage(page: page, scale: scale),
                  let jpegData = image.jpegData(compressionQuality: 0.7) else {
                continue
            }
            images.append(jpegData)
        }
        
        return images
    }
    
    // MARK: - Thumbnail Generation
    
    /// Thumbnail boyutu artırıldı - başlık kısmı daha net görünsün
    func generateThumbnail(for document: PDFDocument, size: CGSize = CGSize(width: 300, height: 400)) -> UIImage? {
        guard let firstPage = document.page(at: 0) else { return nil }
        return firstPage.thumbnail(of: size, for: .mediaBox)
    }
    
    func generateThumbnailData(for document: PDFDocument) -> Data? {
        guard let thumbnail = generateThumbnail(for: document) else { return nil }
        // Kalite artırıldı - daha net görüntü
        return thumbnail.jpegData(compressionQuality: 0.8)
    }
    
    // MARK: - Search
    
    func search(query: String, in document: PDFDocument) -> [PDFSearchResult] {
        var results: [PDFSearchResult] = []
        
        // CRITICAL: findString() crash yapabilir - try-catch ile koru
        guard let selections = try? document.findString(query, withOptions: .caseInsensitive) else {
            logWarning("PDFService", "Arama başarısız", details: "Query: \(query.prefix(50))")
            return []
        }
        
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            
            for selection in selections {
                if selection.pages.contains(page) {
                    results.append(PDFSearchResult(
                        pageIndex: pageIndex,
                        selection: selection
                    ))
                }
            }
        }
        
        return results
    }
}

// MARK: - Search Result
struct PDFSearchResult {
    let pageIndex: Int
    let selection: PDFSelection
    
    var pageNumber: Int {
        pageIndex + 1
    }
}

// MARK: - Professional Magnifier View (Büyüteç)
import SwiftUI

/// Profesyonel büyüteç görünümü - metin seçimi sırasında parmak altındaki içeriği gösterir
class MagnifierView: UIView {
    
    // MARK: - Configuration
    private let diameter: CGFloat = 100
    private let zoomFactor: CGFloat = 1.6
    private let verticalOffset: CGFloat = -60 // Parmağın üstünde göster
    
    // MARK: - State
    private weak var targetPDFView: PDFView?
    private var focusPage: PDFPage?
    private var focusPointInPage: CGPoint = .zero
    private var activeSelection: PDFSelection?
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: diameter, height: diameter))
        configureAppearance()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }
    
    private func configureAppearance() {
        backgroundColor = .white
        layer.cornerRadius = diameter / 2
        layer.masksToBounds = true
        layer.borderWidth = 3
        layer.borderColor = UIColor.systemBlue.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.shadowRadius = 8
        layer.shadowOpacity = 0.3
        isHidden = true
        isUserInteractionEnabled = false
    }
    
    // MARK: - Public API
    
    /// Büyüteci belirtilen konumda göster ve içeriği güncelle
    func show(at viewPoint: CGPoint, pagePoint: CGPoint, page: PDFPage, selection: PDFSelection?, in pdfView: PDFView) {
        self.targetPDFView = pdfView
        self.focusPage = page
        self.focusPointInPage = pagePoint
        self.activeSelection = selection
        
        // Ekran sınırları içinde kalmasını sağla
        var adjustedCenter = CGPoint(x: viewPoint.x, y: viewPoint.y + verticalOffset)
        
        if let superview = superview {
            let halfWidth = diameter / 2
            let halfHeight = diameter / 2
            adjustedCenter.x = max(halfWidth, min(superview.bounds.width - halfWidth, adjustedCenter.x))
            adjustedCenter.y = max(halfHeight, min(superview.bounds.height - halfHeight, adjustedCenter.y))
        }
        
        self.center = adjustedCenter
        self.isHidden = false
        self.setNeedsDisplay()
    }
    
    /// Büyüteci gizle ve state'i temizle
    func dismiss() {
        isHidden = true
        focusPage = nil
        activeSelection = nil
        targetPDFView = nil
    }
    
    // MARK: - Rendering
    
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(),
              let page = focusPage else { return }
        
        // Arka plan
        UIColor.white.setFill()
        ctx.fill(rect)
        
        ctx.saveGState()
        
        // Merkez noktayı hesapla
        let centerX = rect.width / 2
        let centerY = rect.height / 2
        
        // PDF koordinat sistemi dönüşümü
        ctx.translateBy(x: centerX, y: centerY)
        ctx.scaleBy(x: zoomFactor, y: zoomFactor)
        ctx.scaleBy(x: 1.0, y: -1.0) // PDF Y-ekseni ters
        ctx.translateBy(x: -focusPointInPage.x, y: -focusPointInPage.y)
        
        // Sayfayı çiz
        page.draw(with: .mediaBox, to: ctx)
        
        // Seçimi vurgula (varsa)
        if let selection = activeSelection {
            UIColor.systemBlue.withAlphaComponent(0.35).setFill()
            for lineSelection in selection.selectionsByLine() {
                let lineBounds = lineSelection.bounds(for: page)
                if !lineBounds.isNull && !lineBounds.isInfinite {
                    ctx.fill(lineBounds)
                }
            }
        }
        
        ctx.restoreGState()
    }
}

// MARK: - Selection Overlay View (Highlight & Handles)

class SelectionOverlay: UIView {
    weak var pdfView: PDFView?
    var selection: PDFSelection?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    
    func update(selection: PDFSelection?, pdfView: PDFView) {
        self.selection = selection
        self.pdfView = pdfView
        
        // Ensure overlay covers the pdfView
        self.frame = pdfView.bounds
        
        setNeedsDisplay()
    }
    
    override func draw(_ rect: CGRect) {
        guard let selection = selection, let pdfView = pdfView else { return }
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        let selectionsByLine = selection.selectionsByLine()
        
        context.saveGState()
        
        // 1. Draw Highlights
        UIColor.systemBlue.withAlphaComponent(0.3).setFill()
        for line in selectionsByLine {
             guard let page = line.pages.first else { continue }
             let pdfRect = line.bounds(for: page)
             let viewRect = pdfView.convert(pdfRect, from: page)
             
             // Make sure we draw within bounds
             if !viewRect.isNull && !viewRect.isInfinite {
                 context.fill(viewRect)
             }
        }
        
        // 2. Draw Handles Setup
        UIColor.systemBlue.setStroke()
        UIColor.systemBlue.setFill()
        let handleRadius: CGFloat = 5.0
        let lineWidth: CGFloat = 2.0
        
        // Start Handle (Top-Left of first line)
        if let first = selectionsByLine.first, let page = first.pages.first {
            let pdfRect = first.bounds(for: page)
            let viewRect = pdfView.convert(pdfRect, from: page)
            
            if !viewRect.isNull && !viewRect.isInfinite {
                let startPoint = CGPoint(x: viewRect.minX, y: viewRect.minY)
                let endPoint = CGPoint(x: viewRect.minX, y: viewRect.maxY)
                
                // Line
                let path = UIBezierPath()
                path.move(to: startPoint)
                path.addLine(to: endPoint)
                path.lineWidth = lineWidth
                path.lineCapStyle = .round
                path.stroke()
                
                // Circle (Top)
                let circleRect = CGRect(x: startPoint.x - handleRadius, y: startPoint.y - handleRadius * 2, width: handleRadius * 2, height: handleRadius * 2)
                let circlePath = UIBezierPath(ovalIn: circleRect)
                circlePath.fill()
            }
        }
        
        // End Handle (Bottom-Right of last line)
        if let last = selectionsByLine.last, let page = last.pages.first {
            let pdfRect = last.bounds(for: page)
            let viewRect = pdfView.convert(pdfRect, from: page)
            
            if !viewRect.isNull && !viewRect.isInfinite {
                let startPoint = CGPoint(x: viewRect.maxX, y: viewRect.minY)
                let endPoint = CGPoint(x: viewRect.maxX, y: viewRect.maxY)
                
                // Line
                let path = UIBezierPath()
                path.move(to: startPoint)
                path.addLine(to: endPoint)
                path.lineWidth = lineWidth
                path.lineCapStyle = .round
                path.stroke()
                
                // Circle (Bottom)
                let circleRect = CGRect(x: endPoint.x - handleRadius, y: endPoint.y, width: handleRadius * 2, height: handleRadius * 2)
                let circlePath = UIBezierPath(ovalIn: circleRect)
                circlePath.fill()
            }
        }
        
        context.restoreGState()
    }
}


// MARK: - Custom PDFView (Native menüyü engeller, native büyüteç/seçim korunur)

class CustomPDFView: PDFView {
    
    // MARK: - Properties
    var isQuickTranslationMode = false
    var selectionOverlay: SelectionOverlay?
    
    // Touch tracking - dokunma durumu
    var isTouching = false
    var onTouchStateChanged: ((Bool) -> Void)?
    
    // Image selection callback - görsel seçim callback'i
    var onImageSelection: ((PDFImageInfo) -> Void)?
    
    // MARK: - Selection State (Tek kaynak)
    private var _managedSelection: PDFSelection?
    var managedSelection: PDFSelection? {
        get { _managedSelection }
        set {
            _managedSelection = newValue
            super.currentSelection = newValue
            selectionOverlay?.update(selection: newValue, pdfView: self)
        }
    }
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupComponents()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupComponents()
    }
    
    private func setupComponents() {
        // Selection Overlay oluştur (opsiyonel görsel)
        selectionOverlay = SelectionOverlay(frame: bounds)
        if let overlay = selectionOverlay {
            addSubview(overlay)
        }
        
        // Monitoring gesture ekle
        let monitoring = TouchMonitoringGesture(target: self, action: #selector(handleMonitoringGesture(_:)))
        monitoring.delegate = self
        monitoring.cancelsTouchesInView = false
        monitoring.delaysTouchesBegan = false
        monitoring.delaysTouchesEnded = false
        addGestureRecognizer(monitoring)
    }
    
    // MARK: - Monitoring Gesture Handler
    @objc private func handleMonitoringGesture(_ gesture: UIGestureRecognizer) {
        if gesture.state == .began {
            isTouching = true
            onTouchStateChanged?(true)
        } else if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            isTouching = false
            onTouchStateChanged?(false)
        }
    }
    
    // MARK: - UIGestureRecognizerDelegate
    override func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    // MARK: - Layout
    
    override func layoutSubviews() {
        super.layoutSubviews()
        selectionOverlay?.frame = bounds
        selectionOverlay?.setNeedsDisplay()
    }
    
    // MARK: - Touch Tracking
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouching = true
        onTouchStateChanged?(true)
        super.touchesBegan(touches, with: event)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        // Parmak kaldırıldığında hemen bildir - gecikme yok
        isTouching = false
        onTouchStateChanged?(false)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        // İptal durumunda da hemen bildir
        isTouching = false
        onTouchStateChanged?(false)
    }
    
    // MARK: - Menu Suppression
    
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return false // Tüm context menu aksiyonlarını engelle
    }
    
    @available(iOS 16.0, *)
    override func buildMenu(with builder: any UIMenuBuilder) {
        builder.remove(menu: .lookup)
        builder.remove(menu: .standardEdit)
        builder.remove(menu: .share)
        builder.remove(menu: .learn)
        super.buildMenu(with: builder)
    }
    
    override func becomeFirstResponder() -> Bool {
        // Menu'yü hemen gizle (Legacy iOS için)
        if #available(iOS 16.0, *) {
            // iOS 16+'da action'lar engellendiği için menü açılmamalı
        } else {
            DispatchQueue.main.async {
                UIMenuController.shared.hideMenu()
            }
        }
        return super.becomeFirstResponder()
    }
    
    // MARK: - Selection Control
    
    func clearManagedSelection() {
        managedSelection = nil
        clearSelection()
    }
    
    // MARK: - Image Region Capture
    
    /// PDF'in belirli bir bölgesini görsel olarak yakalar
    /// - Parameters:
    ///   - point: View koordinatlarında tıklanan nokta
    ///   - captureSize: Yakalanacak alanın boyutu (piksel)
    /// - Returns: PDFImageInfo veya nil
    func captureRegion(at point: CGPoint, captureSize: CGSize = CGSize(width: 400, height: 400)) -> PDFImageInfo? {
        // View koordinatını PDF sayfasına çevir
        guard let page = page(for: point, nearest: true) else {
            logWarning("CustomPDFView", "Görsel yakalamak için sayfa bulunamadı")
            return nil
        }
        
        guard let document = document else { return nil }
        
        let pdfPoint = convert(point, to: page)
        let pageIndex = document.index(for: page)
        
        // Önce sayfadaki annotation'ları kontrol et (görseller için)
        var captureRect: CGRect?
        
        // PDF Annotation'larını kontrol et
        for annotation in page.annotations {
            let annotBounds = annotation.bounds
            
            // Tıklanan nokta annotation içinde mi?
            if annotBounds.contains(pdfPoint) {
                // Bu bir görsel annotation olabilir
                if annotation.type == "Widget" || annotation.type == "Stamp" || annotation.type == nil {
                    captureRect = annotBounds
                    logInfo("CustomPDFView", "Annotation bulundu", details: "Tip: \(annotation.type ?? "nil"), Bounds: \(annotBounds)")
                    break
                }
            }
            
            // Yakınlık kontrolü - annotation'a yakın bir yere tıklandıysa
            let expandedBounds = annotBounds.insetBy(dx: -20, dy: -20)
            if expandedBounds.contains(pdfPoint) && (annotation.type == nil || annotation.type == "Widget" || annotation.type == "Stamp") {
                captureRect = annotBounds
                logInfo("CustomPDFView", "Yakın annotation bulundu", details: "Bounds: \(annotBounds)")
            }
        }
        
        // Eğer annotation bulunamadıysa, tıklanan noktayı merkez alarak daha geniş bir alan yakala
        if captureRect == nil {
            let scale = scaleFactor
            // Ekran boyutuna göre yakalama alanını hesapla
            let screenWidth = UIScreen.main.bounds.width
            let screenHeight = UIScreen.main.bounds.height
            
            // Ekranın yaklaşık 2/3'ünü kaplayan bir alan
            let desiredWidth = min(captureSize.width, screenWidth * 0.8) / scale
            let desiredHeight = min(captureSize.height, screenHeight * 0.6) / scale
            
            captureRect = CGRect(
                x: pdfPoint.x - desiredWidth / 2,
                y: pdfPoint.y - desiredHeight / 2,
                width: desiredWidth,
                height: desiredHeight
            )
        }
        
        guard var finalRect = captureRect else { return nil }
        
        // Sayfa sınırları içinde kal
        let pageBounds = page.bounds(for: .mediaBox)
        finalRect = finalRect.intersection(pageBounds)
        
        guard !finalRect.isEmpty else {
            logWarning("CustomPDFView", "Yakalama alanı sayfa dışında")
            return nil
        }
        
        // Minimum boyut kontrolü - çok küçük alanları büyüt
        let minDimension: CGFloat = 100
        if finalRect.width < minDimension || finalRect.height < minDimension {
            let scale = scaleFactor
            let expandSize = max(300 / scale, minDimension)
            finalRect = CGRect(
                x: pdfPoint.x - expandSize / 2,
                y: pdfPoint.y - expandSize / 2,
                width: expandSize,
                height: expandSize
            ).intersection(pageBounds)
        }
        
        // PDF bölgesini render et
        let renderScale: CGFloat = 2.5 // Yüksek kalite için
        let renderSize = CGSize(
            width: finalRect.width * renderScale,
            height: finalRect.height * renderScale
        )
        
        let renderer = UIGraphicsImageRenderer(size: renderSize)
        let image = renderer.image { context in
            context.cgContext.translateBy(x: 0, y: renderSize.height)
            context.cgContext.scaleBy(x: renderScale, y: -renderScale)
            context.cgContext.translateBy(x: -finalRect.origin.x, y: -finalRect.origin.y)
            
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        
        // Ekran koordinatlarını hesapla (popup konumu için)
        let viewRect = convert(finalRect, from: page)
        let screenRect = convert(viewRect, to: nil)
        
        logInfo("CustomPDFView", "Görsel yakalandı", details: "Sayfa: \(pageIndex + 1), Boyut: \(Int(renderSize.width))x\(Int(renderSize.height))")
        
        return PDFImageInfo(
            image: image,
            rect: finalRect,
            screenRect: screenRect,
            pageNumber: pageIndex + 1
        )
    }
    
    // MARK: - Capture Image From Detected Bounds
    
    /// Tespit edilen görsel bounds'ından yüksek kaliteli görsel yakalar
    /// - Parameters:
    ///   - bounds: PDF koordinatlarında görsel bounds'u
    ///   - page: Görselin bulunduğu sayfa
    /// - Returns: PDFImageInfo veya nil
    func captureImageFromBounds(_ bounds: CGRect, page: PDFPage) -> PDFImageInfo? {
        guard let document = document else { return nil }
        
        // Sayfa sınırları içinde kal
        let pageBounds = page.bounds(for: .mediaBox)
        var finalRect = bounds.intersection(pageBounds)
        
        guard !finalRect.isEmpty else {
            logWarning("CustomPDFView", "Görsel bounds sayfa dışında")
            return nil
        }
        
        // Minimum boyut kontrolü
        let minDimension: CGFloat = 50
        if finalRect.width < minDimension {
            let centerX = finalRect.midX
            finalRect.origin.x = centerX - minDimension / 2
            finalRect.size.width = minDimension
        }
        if finalRect.height < minDimension {
            let centerY = finalRect.midY
            finalRect.origin.y = centerY - minDimension / 2
            finalRect.size.height = minDimension
        }
        
        // Tekrar sayfa sınırlarına kırp
        finalRect = finalRect.intersection(pageBounds)
        
        guard !finalRect.isEmpty else { return nil }
        
        // Yüksek kalite render
        let renderScale: CGFloat = 3.0
        let renderSize = CGSize(
            width: finalRect.width * renderScale,
            height: finalRect.height * renderScale
        )
        
        let renderer = UIGraphicsImageRenderer(size: renderSize)
        let image = renderer.image { context in
            context.cgContext.translateBy(x: 0, y: renderSize.height)
            context.cgContext.scaleBy(x: renderScale, y: -renderScale)
            context.cgContext.translateBy(x: -finalRect.origin.x, y: -finalRect.origin.y)
            
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        
        // Ekran koordinatları
        let viewRect = convert(finalRect, from: page)
        let screenRect = convert(viewRect, to: nil)
        let pageIndex = document.index(for: page)
        
        logInfo("CustomPDFView", "Görsel bounds'tan yakalandı", details: "Sayfa: \(pageIndex + 1), Boyut: \(Int(renderSize.width))x\(Int(renderSize.height))")
        
        return PDFImageInfo(
            image: image,
            rect: finalRect,
            screenRect: screenRect,
            pageNumber: pageIndex + 1
        )
    }
}

// MARK: - Touch Monitoring Gesture
// Native gesture'lar touch eventlerini yutsa bile çalışır
class TouchMonitoringGesture: UIGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        // Süper hızlı yanıt için hemen state değiştir
        state = .began
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .changed
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .ended
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }
    
    override func reset() {
        super.reset()
        // Reset logic if needed
    }
}


// MARK: - PDFView Representable for SwiftUI

// MARK: - PDFView Extension
extension PDFView {
    var scrollView: UIScrollView? {
        return subviews.first(where: { $0 is UIScrollView }) as? UIScrollView
    }
}

struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument?
    @Binding var currentPage: Int
    var isQuickTranslationMode: Bool = false
    var bottomInset: CGFloat = 0
    var annotations: [Annotation] = []  // Vurgulama ve notlar
    var onSelection: ((String, CGRect, Int) -> Void)?
    var onImageSelection: ((PDFImageInfo) -> Void)?  // Görsel seçim callback'i
    var onRenderComplete: (() -> Void)?  // Render tamamlandığında çağrılır
    var onTap: (() -> Void)?  // Boş alana tıklandığında çağrılır (bar toggle için)
    var onAnnotationTap: ((Annotation) -> Void)?  // Annotation'a tıklandığında (not görüntüle)
    
    func makeUIView(context: Context) -> CustomPDFView {
        logInfo("PDFKitView", "makeUIView called")
        let pdfView = CustomPDFView()
        
        // BULANIKLIK ÇÖZÜMÜ: Başlangıçta gizle, render tamamlanınca göster
        pdfView.alpha = 0
        
        // Zoom ve Scale ayarları
        pdfView.autoScales = true
        pdfView.minScaleFactor = 0.5
        pdfView.maxScaleFactor = 4.0
        
        // Display ayarları
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.usePageViewController(false, withViewOptions: nil)
        pdfView.backgroundColor = .systemGray6
        pdfView.pageShadowsEnabled = true
        
        // Coordinator'a callback'i ver
        context.coordinator.onRenderComplete = onRenderComplete
        
        // Kullanıcı etkileşimi - pinch-to-zoom ve metin seçimi
        pdfView.isUserInteractionEnabled = true
        
        // Coordinator'a pdfView referansını ver
        context.coordinator.pdfView = pdfView
        
        // Tap gesture - seçimi temizlemek için
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.delegate = context.coordinator
        pdfView.addGestureRecognizer(tapGesture)
        
        // NATIVE SELECTION VE BÜYÜTEÇ - iOS'un kendi sistemi kullanılıyor
        // Debounce timer ile seçim stabilize olana kadar popup açılmayacak
        
        // Touch state değiştiğinde - parmak kaldırıldığında popup hemen açılsın
        let coordinator = context.coordinator
        pdfView.onTouchStateChanged = { [weak coordinator] isTouching in
            guard let coordinator = coordinator else { return }
            if !isTouching {
                // Parmak kaldırıldı - debounce timer'ı iptal et ve seçimi hemen raporla
                coordinator.handleTouchEnded()
            }
        }
        
        // Long-press gesture - görsel seçimi için
        let longPressGesture = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPressGesture.minimumPressDuration = 0.35 // Native text selection'dan (0.5s) daha hızlı
        longPressGesture.delegate = context.coordinator
        pdfView.addGestureRecognizer(longPressGesture)
        
        // Coordinator'a gesture referansını ver (gesture kontrolü için)
        context.coordinator.customLongPressGesture = longPressGesture
        
        // Add notification observer for page changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )
        
        // Add notification observer for scale changes
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scaleChanged(_:)),
            name: .PDFViewScaleChanged,
            object: pdfView
        )
        
        // Add notification observer for selection changes - menüyü gizlemek için
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.selectionChanged(_:)),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )
        
        return pdfView
    }
    
    func updateUIView(_ pdfView: CustomPDFView, context: Context) {
        // Coordinator'ın parent referansını güncelle (annotations vb. güncel kalsın)
        context.coordinator.parent = self

        // Mod değişikliğini ilet
        pdfView.isQuickTranslationMode = isQuickTranslationMode
        
        // Update content inset on internal scroll view
        if let scrollView = pdfView.scrollView {
            if scrollView.contentInset.bottom != bottomInset {
                scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
                scrollView.scrollIndicatorInsets = scrollView.contentInset
            }
        }
        
        if let newDocument = document {
            if pdfView.document !== newDocument {
                logInfo("PDFKitView", "Setting new document with \(newDocument.pageCount) pages")
                
                // PDF'i gizli tut - render tamamlanınca gösterilecek
                pdfView.alpha = 0
                
                // Document'ı set et
                pdfView.document = newDocument
                
                // İlk sayfaya git
                if let firstPage = newDocument.page(at: 0) {
                    pdfView.go(to: firstPage)
                }
                
                // Inset uygula
                if let scrollView = pdfView.scrollView {
                    scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: self.bottomInset, right: 0)
                    scrollView.scrollIndicatorInsets = scrollView.contentInset
                }
                
                // BULANIKLIK ÇÖZÜMÜ: Render tamamlanması için bekle, sonra fade-in yap
                // PDFKit'in CATiledLayer'ı yüksek kalite tile'ları yüklemesi için zaman tanı
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // Layout'u zorla
                    pdfView.layoutIfNeeded()
                    
                    // Biraz daha bekle - tile'ların render olması için
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        // Smooth fade-in animasyonu
                        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
                            pdfView.alpha = 1
                        } completion: { _ in
                            logDebug("PDFKitView", "PDF render tamamlandı, görünür yapıldı")
                            context.coordinator.onRenderComplete?()
                        }
                    }
                }
            }
        } else {
            if pdfView.document != nil {
                logWarning("PDFKitView", "Clearing document")
                pdfView.document = nil
            }
        }
        
        // Navigate to page if changed externally and document is ready
        if let currentDoc = pdfView.document,
           let page = currentDoc.page(at: currentPage - 1),
           pdfView.currentPage !== page {
            logDebug("PDFKitView", "Navigating to page \(currentPage)")
            pdfView.go(to: page)
        }
        
        // Annotation'ları PDF sayfalarına uygula
        if let doc = pdfView.document {
            // SAFE COPY & MANUAL LOOP STRATEGY:
            // CRITICAL: Force deep copy to separate from any potential corrupted backing storage
            // This is the key defense against EXC_BAD_ACCESS
            
            // 1. Explicitly copy the array to a local constant to trigger CoW and ensure immutability
            let localAnnotations = Array(annotations)
            var safeAnnotations: [Annotation] = []
            safeAnnotations.reserveCapacity(localAnnotations.count)
            
            // 2. Iterate using a manual loop instead of map for better control and safety
            for ann in localAnnotations {
                // 3. Defensive validity checks & String interpolation
                // Ensure strings are valid (force new string allocation)
                let safeColor = "\(ann.color)"
                let safeId = "\(ann.id)"
                let safeFileId = "\(ann.fileId)"
                
                // Optional string safety
                let safeText = ann.text == nil ? nil : "\(ann.text!)"
                let safeNote = ann.note == nil ? nil : "\(ann.note!)"
                
                // Basic validation
                if safeColor.isEmpty { continue }

                // 4. Construct safe annotation struct
                let safeAnn = Annotation(
                    id: safeId,
                    fileId: safeFileId,
                    pageNumber: ann.pageNumber,
                    type: ann.type,
                    color: safeColor,
                    rects: ann.rects,
                    text: safeText,
                    note: safeNote,
                    isAiGenerated: ann.isAiGenerated
                )
                safeAnnotations.append(safeAnn)
            }
            
            // Annotations'i senkron olarak uygula - async dispatch memory sorunlarina yol acabilir
            // Struct tipler icin weak self kullanilamaz
            self.applyAnnotations(to: doc, annotations: safeAnnotations, coordinator: context.coordinator)
        }
    }
    
    /// Annotation'ları PDF sayfalarına uygular (metin araması ile)
    /// PERFORMANS: Sadece annotation'lar değiştiğinde işlem yapar
    private func applyAnnotations(to document: PDFDocument, annotations: [Annotation], coordinator: Coordinator) {
        // PERFORMANS: Annotation hash'i hesapla ve değişiklik yoksa atla
        let currentHash = annotations.map { "\($0.id)|\($0.pageNumber)|\($0.text ?? "")" }.joined().hashValue
        
        if coordinator.lastAnnotationHash == currentHash {
            // Annotation'lar değişmedi, işlem yapma
            return
        }
        
        // Hash'i güncelle
        coordinator.lastAnnotationHash = currentHash
        
        // Önce mevcut custom annotation'ları temizle (PolyglotHighlight olanları)
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let existingAnnotations = page.annotations
            for annotation in existingAnnotations {
                // Sadece bizim eklediğimiz annotation'ları kaldır (key ile işaretli)
                if annotation.value(forAnnotationKey: .name) as? String == "PolyglotHighlight" {
                    page.removeAnnotation(annotation)
                }
            }
        }
        
        // Yeni annotation'ları ekle
        for annotation in annotations {
            guard annotation.pageNumber >= 1,
                  annotation.pageNumber <= document.pageCount,
                  let page = document.page(at: annotation.pageNumber - 1) else { continue }
            
            // Thread-safe: Color değerini loop öncesi kopyala
            let colorString = String(annotation.color) // Copy to avoid race condition
            let annotationId = String(annotation.id)
            let isAI = annotation.isAiGenerated
            let pageNum = annotation.pageNumber
            
            // Validate color string before use
            if colorString.isEmpty {
                logWarning("PDFKitView", "Empty color string for annotation", details: "ID: \(annotationId)")
            }
            
            // Rengi önceden parse et (loop içinde değil)
            // Use fallback if conversion fails
            let highlightColor: UIColor
            if let color = UIColor(hex: colorString) {
                highlightColor = color
            } else {
                // DO NOT LOG invalid string here to avoid allocation crashes
                highlightColor = UIColor.yellow
            }
            
            // V2: Koordinatlar varsa direkt kullan (metin araması yok!)
            if !annotation.rects.isEmpty {
                var highlightAdded = false
                
                // Rects'i de kopyala
                let rects = annotation.rects.map { rect in
                    CGRect(
                        x: rect.x,
                        y: rect.y,
                        width: rect.width,
                        height: rect.height
                    )
                }
                
                for rect in rects {
                    guard !rect.isNull && !rect.isInfinite && rect.width > 0 && rect.height > 0 else { continue }
                    
                    let highlight = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
                    highlight.color = highlightColor.withAlphaComponent(0.4)
                    
                    highlight.setValue("PolyglotHighlight", forAnnotationKey: .name)
                    highlight.userName = annotation.id
                    page.addAnnotation(highlight)
                    highlightAdded = true
                }
                
                if highlightAdded {
                    if annotation.isAiGenerated {
                        logDebug("PDFKitView", "AI highlight eklendi (koordinat)", details: "Sayfa: \(annotation.pageNumber)")
                    }
                    continue // Bu annotation işlendi, sonrakine geç
                }
            }
            
            // V1 Fallback: Koordinat yoksa metin araması yap (eski annotation'lar için)
            guard let searchText = annotation.text, !searchText.isEmpty else { continue }
            
            // AI annotation'lar için özel işleme - whitespace ve ligature düzelt
            var normalizedText = searchText
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Tırnak işaretleri düzeltmeleri - of"expected -> of "expected
            normalizedText = normalizedText
                .replacingOccurrences(of: "of\"", with: "of \"")
                .replacingOccurrences(of: "\"\"", with: "\" \"")
                .replacingOccurrences(of: ".....", with: "...")  // Fazla noktalar
                .replacingOccurrences(of: "....", with: "...")
                .replacingOccurrences(of: "…", with: "...")  // Unicode ellipsis
            
            // Apostrof düzeltmeleri - Cohen' s -> Cohen's
            normalizedText = normalizedText
                .replacingOccurrences(of: "' s", with: "'s")
                .replacingOccurrences(of: "' t", with: "'t")
                .replacingOccurrences(of: "' re", with: "'re")
                .replacingOccurrences(of: "' ve", with: "'ve")
                .replacingOccurrences(of: "' ll", with: "'ll")
                .replacingOccurrences(of: "n' t", with: "n't")
            
            // Ligature düzeltmeleri - PDF'lerde fi, fl, ff gibi karakterler birleşik
            // RAG extraction bunları ayırıyor, geri birleştir
            normalizedText = normalizedText
                .replacingOccurrences(of: "ﬁ", with: "fi")  // Unicode ligature
                .replacingOccurrences(of: "ﬂ", with: "fl")  // Unicode ligature
                .replacingOccurrences(of: "ﬀ", with: "ff")  // Unicode ligature
                .replacingOccurrences(of: "ﬃ", with: "ffi") // Unicode ligature
                .replacingOccurrences(of: "ﬄ", with: "ffl") // Unicode ligature
                // thenal -> the final (özel durum)
                .replacingOccurrences(of: "thenal", with: "the final")
                .replacingOccurrences(of: "thefinal", with: "the final")
                // Yaygın ayrılmış ligature'ler
                .replacingOccurrences(of: " fi", with: "fi")
                .replacingOccurrences(of: " fl", with: "fl")
                .replacingOccurrences(of: "fi ", with: "fi")
                .replacingOccurrences(of: "fl ", with: "fl")
                .replacingOccurrences(of: "de nition", with: "definition")
                .replacingOccurrences(of: "de ned", with: "defined")
                .replacingOccurrences(of: "de ne", with: "define")
                .replacingOccurrences(of: " nal", with: "nal")
                .replacingOccurrences(of: " rst", with: "rst")
                .replacingOccurrences(of: " nding", with: "nding")
                .replacingOccurrences(of: " ndings", with: "ndings")
                .replacingOccurrences(of: " eld", with: "eld")
                .replacingOccurrences(of: "  ", with: " ") // Clean up any double spaces created
            
            // Metni sayfada ara - case-insensitive
            // findString() crash yapabilir - try? ile koru
            var selections: [PDFSelection] = []
            if let foundSelections = try? document.findString(normalizedText, withOptions: .caseInsensitive) {
                selections = foundSelections
            }
            
            // Eğer bulunamadıysa, daha kısa bir parça ile dene (ilk 50 karakter)
            if selections.isEmpty && normalizedText.count > 50 {
                let shortText = String(normalizedText.prefix(50))
                if let shortSelections = try? document.findString(shortText, withOptions: .caseInsensitive) {
                    selections = shortSelections
                    if !selections.isEmpty {
                        logDebug("PDFKitView", "AI annotation kısa metin ile bulundu", details: "ID: \(annotation.id.prefix(8))")
                    }
                }
            }
            
            // Debug log - AI annotation'lar için
            if annotation.isAiGenerated && selections.isEmpty {
                logWarning("PDFKitView", "AI annotation metni bulunamadı", details: "Sayfa: \(annotation.pageNumber), Metin: \(normalizedText.prefix(60))...")
            }
            
            // İlgili sayfadaki sonucu bul
            for selection in selections {
                guard selection.pages.contains(page) else { continue }
                
                // Her satır için highlight oluştur
                for lineSelection in selection.selectionsByLine() {
                    let lineBounds = lineSelection.bounds(for: page)
                    
                    guard !lineBounds.isNull && !lineBounds.isInfinite else { continue }
                    
                    // Highlight annotation oluştur
                    let pdfAnnotation = PDFAnnotation(bounds: lineBounds, forType: .highlight, withProperties: nil)
                    
                    // Renk ayarla (önceden hesaplanmış highlightColor kullan)
                    pdfAnnotation.color = highlightColor.withAlphaComponent(0.4)
                    
                    // Annotation'ı tanımlamak için key ekle
                    pdfAnnotation.setValue("PolyglotHighlight", forAnnotationKey: .name)
                    pdfAnnotation.setValue(annotation.id, forAnnotationKey: .contents)
                    
                    page.addAnnotation(pdfAnnotation)
                }
                
                // AI annotation başarıyla eklendi
                if annotation.isAiGenerated {
                    logInfo("PDFKitView", "AI highlight eklendi", details: "Sayfa: \(annotation.pageNumber)")
                }
                
                // Not varsa not ikonu ekle (metin pozisyonuna göre sol veya sağ tarafa)
                if let note = annotation.note, !note.isEmpty {
                    let firstLineBounds = selection.bounds(for: page)

                    if !firstLineBounds.isNull && !firstLineBounds.isInfinite {
                        let pageBounds = page.bounds(for: .mediaBox)
                        let pageCenter = pageBounds.midX
                        let textCenter = firstLineBounds.midX

                        // Daha küçük ve profesyonel ikon boyutu
                        let noteIconSize: CGFloat = 16

                        // Metin sayfanın sol yarısındaysa ikonu sola, sağ yarısındaysa sağa koy
                        let iconX: CGFloat
                        if textCenter < pageCenter {
                            // Metin solda - ikonu metnin soluna koy
                            iconX = firstLineBounds.minX - noteIconSize - 4
                        } else {
                            // Metin sağda - ikonu metnin sağına koy
                            iconX = firstLineBounds.maxX + 4
                        }

                        let noteIconRect = CGRect(
                            x: iconX,
                            y: firstLineBounds.midY - noteIconSize / 2,
                            width: noteIconSize,
                            height: noteIconSize
                        )

                        let noteAnnotation = PDFAnnotation(bounds: noteIconRect, forType: .text, withProperties: nil)
                        noteAnnotation.contents = note
                        noteAnnotation.color = UIColor.systemOrange.withAlphaComponent(0.9)
                        noteAnnotation.setValue("PolyglotNote", forAnnotationKey: .name)
                        // Annotation ID'yi userName'de sakla (.contents not metni için kullanılıyor)
                        noteAnnotation.userName = annotation.id

                        page.addAnnotation(noteAnnotation)
                    }
                }
                
                // Sadece ilk eşleşmeyi kullan
                break
            }
        }
    }

    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PDFKitView
        weak var pdfView: PDFView?
        
        // Render tamamlandığında çağrılacak callback
        var onRenderComplete: (() -> Void)?
        
        // MARK: - Annotation Cache (Performans optimizasyonu)
        /// Son uygulanan annotation'ların hash'i - sadece değişiklik olduğunda güncelle
        var lastAnnotationHash: Int = 0
        
        // Debounce için son değerler
        private var lastSelectionText: String?
        private var lastPageIndex: Int?
        private var lastScaleFactor: CGFloat?
        
        // Seçim debounce sistemi - seçim stabilize olana kadar bekle
        private var selectionDebounceTimer: Timer?
        private let selectionDebounceDelay: TimeInterval = 1.0 // 1 saniye bekle
        
        // Seçim snapshot sistemi
        private var selectionSnapshot: SelectionSnapshot?
        
        // MARK: - Image Long-Press Handling
        /// Görsel long-press işlemi devam ederken true
        private var isHandlingImageLongPress = false
        
        /// Custom long-press gesture referansı
        weak var customLongPressGesture: UILongPressGestureRecognizer?
        
        struct SelectionSnapshot {
            let text: String
            let bounds: CGRect
            let pageIndex: Int
            let timestamp: Date
        }
        
        init(_ parent: PDFKitView) {
            self.parent = parent
        }
        
        deinit {
            selectionDebounceTimer?.invalidate()
        }
        
        // MARK: - Touch State Handler
        
        /// Parmak kaldırıldığında çağrılır - debounce beklemeden popup'ı hemen aç
        func handleTouchEnded() {
            // Debounce timer'ını iptal et - artık beklememize gerek yok
            selectionDebounceTimer?.invalidate()
            selectionDebounceTimer = nil
            
            // Geçerli bir seçim varsa hemen raporla (force: true ile debounce bypass)
            reportSelectionImmediately()
        }
        
        /// Seçimi hemen raporla - debounce kontrolü olmadan
        private func reportSelectionImmediately() {
            guard let customPdfView = pdfView as? CustomPDFView,
                  let selection = customPdfView.managedSelection ?? customPdfView.currentSelection,
                  var selectedText = selection.string,
                  !selectedText.isEmpty,
                  let page = selection.pages.first,
                  let document = customPdfView.document else { return }
            
            selectedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard selectedText.count >= 2 else { return }
            
            // lastSelectionText'i güncelle ama kontrol etme (force report)
            lastSelectionText = selectedText
            
            let pageIndex = document.index(for: page)
            
            var combinedBounds = CGRect.zero
            for selectedPage in selection.pages {
                let pageBounds = selection.bounds(for: selectedPage)
                if combinedBounds == .zero {
                    combinedBounds = pageBounds
                } else {
                    combinedBounds = combinedBounds.union(pageBounds)
                }
            }
            
            let viewBounds = customPdfView.convert(combinedBounds, from: page)
            let screenBounds = customPdfView.convert(viewBounds, to: nil)
            
            logDebug("PDFKitView", "Parmak kaldırıldı - seçim hemen raporlandı", details: "Karakter: \(selectedText.count)")
            
            DispatchQueue.main.async {
                self.parent.onSelection?(selectedText, screenBounds, pageIndex + 1)
            }
        }
        
        // MARK: - UIGestureRecognizerDelegate
        
        /// Gesture başlamadan önce koşullu kontrol
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // Görsel long-press işlemi devam ediyorsa diğer gesture'ları engelle
            if isHandlingImageLongPress {
                // Bizim custom long-press gesture'ımız hariç
                if gestureRecognizer !== customLongPressGesture {
                    return false
                }
            }
            
            // Custom Gesture için ÖN KONTROL: Metin varsa başlama bile!
            if gestureRecognizer === customLongPressGesture {
                guard let customPdfView = pdfView as? CustomPDFView else { return true }
                let location = gestureRecognizer.location(in: customPdfView)
                
                guard let page = customPdfView.page(for: location, nearest: true) else { return true }
                let pdfPoint = customPdfView.convert(location, to: page)
                
                var hasTextUnderFinger = false
                
                // En yakın kelimeyi bul (Geniş tolerans)
                if let selection = page.selectionForWord(at: pdfPoint) {
                    let selectionBounds = selection.bounds(for: page)
                    let hitTestBounds = selectionBounds.insetBy(dx: -25, dy: -25) 
                    
                    if hitTestBounds.contains(pdfPoint) {
                        if let text = selection.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            hasTextUnderFinger = true
                        }
                    }
                }
                
                // Yedek karakter kontrolü
                if !hasTextUnderFinger {
                    // 20x20 alan kontrolü
                    if let charSelection = page.selection(for: CGRect(x: pdfPoint.x - 10, y: pdfPoint.y - 10, width: 20, height: 20)) {
                         if let text = charSelection.string, text.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 {
                             hasTextUnderFinger = true
                         }
                    }
                }
                
                if hasTextUnderFinger {
                    // Metin var -> Native selection'a bırak, biz hiç başlamayalım
                    return false
                }
            }
            
            return true
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Görsel işlemi sırasında simultaneity'i engelle
            if isHandlingImageLongPress {
                return false
            }
            
            // Long-press bizim gesture'ımız ise ve diğer PDFView gesture'ı ise engelle
            if gestureRecognizer === customLongPressGesture {
                // Sadece scroll/zoom için izin ver
                if otherGestureRecognizer is UIPinchGestureRecognizer ||
                   otherGestureRecognizer is UIPanGestureRecognizer {
                    return true
                }
                return false
            }
            
            return true
        }
        
        // MARK: - Gesture Handlers
        
        /// Long-press gesture - görsel seçimi için (akıllı detection ile)
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let customPdfView = pdfView as? CustomPDFView else { return }
            
            switch gesture.state {
            case .began:
                let location = gesture.location(in: customPdfView)
                
                // Sayfa ve PDF koordinatlarını al
                guard let page = customPdfView.page(for: location, nearest: true) else { return }
                let pdfPoint = customPdfView.convert(location, to: page)
                
                // ADIM 0: Hızlı Ön Kontrol (Synchronous)
                
                var hasTextUnderFinger = false
                
                // En yakın kelimeyi bul
                // Margin'i artırdık (20pt) - Kullanıcı satır arasına veya kelime boşluğuna bassa bile metin algıla
                if let selection = page.selectionForWord(at: pdfPoint) {
                    let selectionBounds = selection.bounds(for: page)
                    let hitTestBounds = selectionBounds.insetBy(dx: -25, dy: -25) // Daha geniş tolerans
                    
                    if hitTestBounds.contains(pdfPoint) {
                        if let text = selection.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            hasTextUnderFinger = true
                        }
                    }
                }
                
                // Ayrıca, basitçe noktadaki karakteri de kontrol et (yedek)
                if !hasTextUnderFinger {
                    if let charSelection = page.selection(for: CGRect(x: pdfPoint.x - 10, y: pdfPoint.y - 10, width: 20, height: 20)) {
                         if let text = charSelection.string, text.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 {
                             hasTextUnderFinger = true
                         }
                    }
                }
                
                if hasTextUnderFinger {
                    // Metin var -> KESİNLİKLE native seçime bırak.
                    // Custom gesture'ı iptal et ki native uzun basma devreye girsin.
                    gesture.state = .cancelled
                    logInfo("PDFKitView", "Metin tespit edildi, görsel modu iptal ediliyor.")
                    return
                }
                
                // Metin yoksa görsel moduna geçebiliriz
                if !hasTextUnderFinger {
                    // Metin yok -> Görsel olma ihtimali yüksek
                    isHandlingImageLongPress = true
                    disableNativeSelectionGestures(in: customPdfView)
                    
                    // HEMEN Geri Bildirim Ver: "Tarama Başladı"
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    self.showScanningFeedback(at: pdfPoint, page: page, in: customPdfView)
                    
                    logInfo("PDFKitView", "Metin yok, görsel taraması başlatılıyor")
                }
                
                // ADIM 1: Vision destekli ASYNC görsel tespiti yap
                PDFImageDetector.shared.detectImage(at: pdfPoint, in: page) { [weak self] imageBounds in
                    guard let self = self else { return }
                    
                    DispatchQueue.main.async {
                        // Scanning feedback'i kaldır
                        self.removeScanningFeedback(in: customPdfView)
                        
                        // ADIM 2: Görsel bulundu mu?
                        if let bounds = imageBounds {
                            // GÖRSEL BULUNDU
                            logInfo("PDFKitView", "Vision görsel doğruladı")
                            
                            // Eğer en başta engellemediysek şimdi engelleyelim
                            if !self.isHandlingImageLongPress {
                                self.isHandlingImageLongPress = true
                                self.disableNativeSelectionGestures(in: customPdfView)
                            }
                            
                            // Selection'ı temizle
                            customPdfView.clearSelection()
                            customPdfView.managedSelection = nil
                            
                            // Visual Feedback (Highlight) - Başarılı
                            self.showImageSelectionHighlight(rect: bounds, page: page, in: customPdfView)
                            
                            // Görseli yakala
                            if let imageInfo = customPdfView.captureImageFromBounds(bounds, page: page) {
                                // Haptic feedback - Başarılı
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                
                                logInfo("PDFKitView", "Görsel seçildi (akıllı detection)", details: "Sayfa: \(imageInfo.pageNumber), Bounds: \(bounds)")
                                
                                // Callback'leri çağır
                                self.parent.onSelection?("", .zero, 0)
                                self.parent.onImageSelection?(imageInfo)
                                
                                // GESTURE RESET:
                                // Kullanıcı parmağını kaldırmadan popup'ın görünmesi için
                                // gesture'ı manuel olarak iptal ediyoruz.
                                // Bu, UI'ın "takılı kalmasını" engeller.
                                gesture.isEnabled = false
                                gesture.isEnabled = true
                                
                                self.isHandlingImageLongPress = false
                                self.enableNativeSelectionGestures(in: customPdfView)
                            } else {
                                self.isHandlingImageLongPress = false
                                self.enableNativeSelectionGestures(in: customPdfView)
                            }
                        } else {
                            // Görsel bulunamadı
                            logInfo("PDFKitView", "Vision görsel bulamadı")
                            
                            if self.isHandlingImageLongPress {
                                self.isHandlingImageLongPress = false
                                self.enableNativeSelectionGestures(in: customPdfView)
                            }
                        }
                    }
                }
                
            case .changed:
                break
                
            case .ended, .cancelled, .failed:
                if !isHandlingImageLongPress {
                    enableNativeSelectionGestures(in: customPdfView)
                }
                // Scanning feedback temizle (eğer hala duruyorsa)
                removeScanningFeedback(in: customPdfView)
                
            default:
                break
            }
        }
        
        // MARK: - Visual Feedback Helpers
        
        private var scanningFeedbackView: UIView?
        
        /// Tarama efekti (Pulse)
        private func showScanningFeedback(at point: CGPoint, page: PDFPage, in view: PDFView) {
            removeScanningFeedback(in: view)
            
            let viewPoint = view.convert(point, from: page)
            let size: CGFloat = 60
            let frame = CGRect(x: viewPoint.x - size/2, y: viewPoint.y - size/2, width: size, height: size)
            
            let feedbackView = UIView(frame: frame)
            feedbackView.backgroundColor = UIColor.gray.withAlphaComponent(0.2)
            feedbackView.layer.cornerRadius = size / 2
            feedbackView.isUserInteractionEnabled = false
            feedbackView.tag = 999 // Tag ile bulmak için
            
            view.addSubview(feedbackView)
            scanningFeedbackView = feedbackView
            
            // Pulse animasyonu
            UIView.animate(withDuration: 0.5, delay: 0, options: [.autoreverse, .repeat], animations: {
                feedbackView.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
                feedbackView.alpha = 0.1
            }, completion: nil)
        }
        
        private func removeScanningFeedback(in view: UIView) {
            scanningFeedbackView?.removeFromSuperview()
            scanningFeedbackView = nil
            // Yedek temizlik
            view.subviews.first(where: { $0.tag == 999 })?.removeFromSuperview()
        }
        
        /// Görsel seçildiğinde geçici bir highlight efekti göster
        private func showImageSelectionHighlight(rect: CGRect, page: PDFPage, in view: PDFView) {
            let viewRect = view.convert(rect, from: page)
            
            let highlightView = UIView(frame: viewRect)
            highlightView.backgroundColor = UIColor.systemIndigo.withAlphaComponent(0.3)
            highlightView.layer.borderColor = UIColor.systemIndigo.withAlphaComponent(0.8).cgColor
            highlightView.layer.borderWidth = 2.0
            highlightView.layer.cornerRadius = 4
            highlightView.isUserInteractionEnabled = false
            view.addSubview(highlightView)
            
            // Animasyonla kaybolsun
            UIView.animate(withDuration: 0.3, delay: 0.5, options: .curveEaseOut) {
                highlightView.alpha = 0
            } completion: { _ in
                highlightView.removeFromSuperview()
            }
        }
        
        // MARK: - Native Gesture Control
        
        /// Native text selection gesture'larını geçici olarak devre dışı bırak
        private func disableNativeSelectionGestures(in view: UIView) {
            for gestureRecognizer in view.gestureRecognizers ?? [] {
                // Bizim custom long-press gesture'ımız hariç
                if gestureRecognizer !== customLongPressGesture {
                    // Long-press ve text selection ile ilgili gesture'ları devre dışı bırak
                    if gestureRecognizer is UILongPressGestureRecognizer {
                        gestureRecognizer.isEnabled = false
                    }
                }
            }
            // Alt view'larda da uygula
            for subview in view.subviews {
                disableNativeSelectionGestures(in: subview)
            }
        }
        
        /// Native text selection gesture'larını yeniden etkinleştir
        private func enableNativeSelectionGestures(in view: UIView) {
            for gestureRecognizer in view.gestureRecognizers ?? [] {
                gestureRecognizer.isEnabled = true
            }
            for subview in view.subviews {
                enableNativeSelectionGestures(in: subview)
            }
        }
        
        /// Tap gesture - seçim dışına tıklayınca seçimi temizle, not ikonuna tıklanınca notu göster
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let pdfView = pdfView else { return }

            let tapLocation = gesture.location(in: pdfView)

            // Önce not annotation'ı kontrolü yap
            if let page = pdfView.page(for: tapLocation, nearest: true) {
                let pdfPoint = pdfView.convert(tapLocation, to: page)

                logDebug("PDFKitView", "Tap detected", details: "PDF Point: \(pdfPoint), Annotations count: \(page.annotations.count)")

                // Sayfadaki annotation'ları kontrol et
                for pdfAnnotation in page.annotations {
                    let nameValue = pdfAnnotation.value(forAnnotationKey: .name) as? String

                    // Sadece bizim not annotation'larımızı kontrol et
                    if nameValue == "PolyglotNote" {
                        // Tıklama alanını genişlet (daha kolay tıklanabilir olsun)
                        let hitTestBounds = pdfAnnotation.bounds.insetBy(dx: -15, dy: -15)

                        logDebug("PDFKitView", "Found PolyglotNote", details: "Bounds: \(pdfAnnotation.bounds), HitTest: \(hitTestBounds), Contains: \(hitTestBounds.contains(pdfPoint))")

                        if hitTestBounds.contains(pdfPoint) {
                            // Not annotation'ına tıklandı - userName'den ID'yi al
                            if let annotationId = pdfAnnotation.userName {

                                logDebug("PDFKitView", "Note tapped", details: "ID from userName: \(annotationId)")

                                // Parent annotation'ı bul
                                let matchingAnnotation = parent.annotations.first { $0.id == annotationId }
                                if let annotation = matchingAnnotation {
                                    logDebug("PDFKitView", "Not ikonuna tıklandı", details: "ID: \(annotationId)")

                                    DispatchQueue.main.async {
                                        self.parent.onAnnotationTap?(annotation)
                                    }
                                    return
                                } else {
                                    logWarning("PDFKitView", "Matching annotation not found", details: "ID: \(annotationId), Available: \(parent.annotations.map { $0.id })")
                                }
                            } else {
                                logWarning("PDFKitView", "userName is nil for note annotation")
                            }
                        }
                    }
                }
            }

            // Mevcut bir seçim var mı kontrol et
            if let currentSelection = pdfView.currentSelection,
               let selectedText = currentSelection.string,
               !selectedText.isEmpty,
               let page = currentSelection.pages.first {

                let selectionBounds = currentSelection.bounds(for: page)
                let viewBounds = pdfView.convert(selectionBounds, from: page)
                let expandedBounds = viewBounds.insetBy(dx: -40, dy: -40)

                // Seçim dışına tıklama
                if !expandedBounds.contains(tapLocation) {
                    pdfView.clearSelection()
                    lastSelectionText = nil

                    DispatchQueue.main.async {
                        self.parent.onSelection?("", .zero, 0)
                    }
                    logDebug("PDFKitView", "Seçim temizlendi - dış alana tıklandı")

                    // Bar toggle için onTap callback'i çağır
                    DispatchQueue.main.async {
                        self.parent.onTap?()
                    }
                }
            } else {
                // Seçim yok - bar toggle için onTap callback'i çağır
                DispatchQueue.main.async {
                    self.parent.onTap?()
                }
            }
        }
        
        /// Seçimi birden fazla deneme ile yakala - daha güvenilir
        private func captureSelectionWithRetry(attempts: Int, delay: TimeInterval) {
            guard attempts > 0 else { return }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                
                // Seçim var mı kontrol et (managedSelection kullan)
                if let customPdfView = self.pdfView as? CustomPDFView,
                   let selection = customPdfView.managedSelection,
                   let text = selection.string,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Seçim bulundu, raporla
                    self.checkAndReportSelection()
                } else if attempts > 1 {
                    // Seçim henüz hazır değil, tekrar dene
                    self.captureSelectionWithRetry(attempts: attempts - 1, delay: 0.1)
                }
            }
        }
        
        private func checkAndReportSelection() {
            guard let customPdfView = pdfView as? CustomPDFView,
                  let selection = customPdfView.managedSelection ?? customPdfView.currentSelection,
                  var selectedText = selection.string,
                  !selectedText.isEmpty,
                  let page = selection.pages.first,
                  let document = customPdfView.document else { return }
            
            // Metni temizle - başındaki ve sonundaki boşlukları kaldır
            selectedText = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Çok kısa seçimleri yoksay (genellikle yanlış seçim)
            guard selectedText.count >= 2 else { return }
            
            // Debounce: Aynı metin için tekrar tetikleme
            guard lastSelectionText != selectedText else { return }
            lastSelectionText = selectedText
            
            let pageIndex = document.index(for: page)
            
            // Tüm seçili sayfalar için bounds'u birleştir (çok satırlı seçim için)
            var combinedBounds = CGRect.zero
            for selectedPage in selection.pages {
                let pageBounds = selection.bounds(for: selectedPage)
                if combinedBounds == .zero {
                    combinedBounds = pageBounds
                } else {
                    combinedBounds = combinedBounds.union(pageBounds)
                }
            }
            
            // PDF koordinatlarını view koordinatlarına çevir
            let viewBounds = customPdfView.convert(combinedBounds, from: page)
            let screenBounds = customPdfView.convert(viewBounds, to: nil)
            
            logDebug("PDFKitView", "Metin seçimi tamamlandı", details: "Sayfa: \(pageIndex + 1), Karakter: \(selectedText.count), Metin: \(selectedText.prefix(50))...")
            
            DispatchQueue.main.async {
                self.parent.onSelection?(selectedText, screenBounds, pageIndex + 1)
            }
        }
        
        // MARK: - Page Changed
        
        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let document = pdfView.document else { return }
            
            let pageIndex = document.index(for: currentPage)
            
            // Debounce: Aynı sayfa için tekrar tetikleme
            guard lastPageIndex != pageIndex else { return }
            lastPageIndex = pageIndex
            
            // Sayfa değiştiğinde selection'ı temizle
            lastSelectionText = nil
            
            // logDebug("PDFKitView", "Sayfa değişti: \(pageIndex + 1)")
            
            DispatchQueue.main.async {
                self.parent.currentPage = pageIndex + 1
            }
        }
        
        // MARK: - Scale Changed
        
        @objc func scaleChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView else { return }
            
            let currentScale = pdfView.scaleFactor
            
            // Debounce: Aynı scale için tekrar tetikleme
            guard lastScaleFactor != currentScale else { return }
            lastScaleFactor = currentScale
            
            // logDebug("PDFKitView", "Zoom değişti: \(Int(currentScale * 100))%")
        }
        
        // MARK: - Selection Changed - Seçim değişti
        
        @objc func selectionChanged(_ notification: Notification) {
            // iOS native menüsünü gizle
            if #available(iOS 16.0, *) {
                // iOS 16+'da UIEditMenuInteraction otomatik yönetilir veya buildMenu ile engellenir
                // UIMenuController kullanmaya gerek yok
            } else {
                DispatchQueue.main.async {
                    UIMenuController.shared.hideMenu()
                }
            }
            
            // iOS 16+ için edit menu interaction'larını da temizle
            if #available(iOS 16.0, *) {
                if let pdfView = notification.object as? PDFView {
                    self.removeEditMenuInteractions(from: pdfView)
                }
            }
            
            // Mevcut timer'ı iptal et - yeni seçim değişikliği geldi
            selectionDebounceTimer?.invalidate()
            
            // Seçim boşsa timer başlatma
            guard let pdfView = pdfView,
                  let selection = pdfView.currentSelection,
                  let text = selection.string,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            
            // Yeni debounce timer başlat
            // Seçim 0.5 saniye değişmezse popup açılacak
            selectionDebounceTimer = Timer.scheduledTimer(withTimeInterval: selectionDebounceDelay, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.checkAndReportSelection()
                }
            }
        }
        
        @available(iOS 16.0, *)
        private func removeEditMenuInteractions(from view: UIView) {
            for interaction in view.interactions {
                if interaction is UIEditMenuInteraction {
                    view.removeInteraction(interaction)
                }
            }
            for subview in view.subviews {
                removeEditMenuInteractions(from: subview)
            }
        }
    }
}

// MARK: - UIColor Hex Extension
// MARK: - UIColor Hex Extension
extension UIColor {
    convenience init?(hex: String) {
        // Defensive check: empty or too long (hex codes are short)
        // This prevents trying to process corrupted strings with huge length metadata
        guard !hex.isEmpty, hex.count < 10 else { return nil }
        
        // Use a safer manual parsing approach avoiding String APIs that might trigger allocation issues
        var cString: String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if (cString.hasPrefix("#")) {
            cString.remove(at: cString.startIndex)
        }

        if ((cString.count) != 6) {
            return nil
        }

        var rgbValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)

        self.init(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: CGFloat(1.0)
        )
    }
}
