import UIKit
import PDFKit

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
    override func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    // MARK: - Layout
    override func layoutSubviews() {
        super.layoutSubviews()
        selectionOverlay?.frame = bounds
        selectionOverlay?.setNeedsDisplay()
        removeEditMenuInteractionsIfNeeded()
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
        false // Tüm context menu aksiyonlarını engelle
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
        if #unavailable(iOS 16.0) {
            DispatchQueue.main.async {
                UIMenuController.shared.hideMenu()
            }
        }
        return super.becomeFirstResponder()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        removeEditMenuInteractionsIfNeeded()
    }

    override func addInteraction(_ interaction: UIInteraction) {
        if #available(iOS 16.0, *), interaction is UIEditMenuInteraction {
            return
        }
        super.addInteraction(interaction)
    }

    // MARK: - Selection Control
    func clearManagedSelection() {
        managedSelection = nil
        clearSelection()
    }

    private func removeEditMenuInteractionsIfNeeded() {
        guard #available(iOS 16.0, *),
              window?.windowScene != nil else { return }
        removeEditMenuInteractions(from: self)
    }

    @available(iOS 16.0, *)
    private func removeEditMenuInteractions(from view: UIView) {
        for interaction in view.interactions where interaction is UIEditMenuInteraction {
            view.removeInteraction(interaction)
        }
        for subview in view.subviews {
            removeEditMenuInteractions(from: subview)
        }
    }

    // MARK: - Image Region Capture

    /// PDF'in belirli bir bölgesini görsel olarak yakalar
    /// PDF'in belirli bir bölgesini görsel olarak yakalar
    func captureRegion(at point: CGPoint, captureSize: CGSize = CGSize(width: 400, height: 400)) -> PDFImageInfo? {
        guard let page = page(for: point, nearest: true),
              let document = document else { return nil }

        let pdfPoint = convert(point, to: page)
        let pageIndex = document.index(for: page)

        // 1. Annotation kontrolü
        var captureRect = findAnnotationBoundForCapture(at: pdfPoint, page: page)

        // 2. Fallback: Boş alan seçimi
        if captureRect == nil {
            captureRect = calculateFallbackCaptureRect(at: pdfPoint, captureSize: captureSize)
        }

        guard var finalRect = captureRect else { return nil }

        // 3. Rect validasyonu ve düzeltmesi
        let pageBounds = page.bounds(for: .mediaBox)
        finalRect = finalRect.intersection(pageBounds)

        if finalRect.isEmpty { return nil }

        finalRect = adjustRectSizeIfNeeded(finalRect, at: pdfPoint, pageBounds: pageBounds)

        // 4. Render
        let renderScale: CGFloat = 2.5
        let renderSize = CGSize(width: finalRect.width * renderScale, height: finalRect.height * renderScale)

        let renderer = UIGraphicsImageRenderer(size: renderSize)
        let image = renderer.image { context in
            context.cgContext.translateBy(x: 0, y: renderSize.height)
            context.cgContext.scaleBy(x: renderScale, y: -renderScale)
            context.cgContext.translateBy(x: -finalRect.origin.x, y: -finalRect.origin.y)
            page.draw(with: .mediaBox, to: context.cgContext)
        }

        let viewRect = convert(finalRect, from: page)
        let screenRect = convert(viewRect, to: nil)

        return PDFImageInfo(image: image, rect: finalRect, screenRect: screenRect, pageNumber: pageIndex + 1)
    }

    private func findAnnotationBoundForCapture(at pdfPoint: CGPoint, page: PDFPage) -> CGRect? {
        for annotation in page.annotations {
            let annotBounds = annotation.bounds
            if annotBounds.contains(pdfPoint) {
                if annotation.type == "Widget" || annotation.type == "Stamp" || annotation.type == nil {
                    return annotBounds
                }
            }
            let expandedBounds = annotBounds.insetBy(dx: -20, dy: -20)
            if expandedBounds.contains(pdfPoint),
               annotation.type == nil || annotation.type == "Widget" || annotation.type == "Stamp" {
                return annotBounds
            }
        }
        return nil
    }

    private func calculateFallbackCaptureRect(at pdfPoint: CGPoint, captureSize: CGSize) -> CGRect {
        let scale = scaleFactor
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height

        let desiredWidth = min(captureSize.width, screenWidth * 0.8) / scale
        let desiredHeight = min(captureSize.height, screenHeight * 0.6) / scale

        return CGRect(
            x: pdfPoint.x - desiredWidth / 2,
            y: pdfPoint.y - desiredHeight / 2,
            width: desiredWidth,
            height: desiredHeight
        )
    }

    private func adjustRectSizeIfNeeded(_ rect: CGRect, at pdfPoint: CGPoint, pageBounds: CGRect) -> CGRect {
        let minDimension: CGFloat = 100
        if rect.width < minDimension || rect.height < minDimension {
            let scale = scaleFactor
            let expandSize = max(300 / scale, minDimension)
            return CGRect(
                x: pdfPoint.x - expandSize / 2,
                y: pdfPoint.y - expandSize / 2,
                width: expandSize,
                height: expandSize
            ).intersection(pageBounds)
        }
        return rect
    }

    // MARK: - Capture Image From Detected Bounds
    func captureImageFromBounds(_ bounds: CGRect, page: PDFPage) -> PDFImageInfo? {
        guard let document = document else { return nil }

        let pageBounds = page.bounds(for: .mediaBox)
        var finalRect = bounds.intersection(pageBounds)

        guard !finalRect.isEmpty else { return nil }

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

        finalRect = finalRect.intersection(pageBounds)
        guard !finalRect.isEmpty else { return nil }

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

        let viewRect = convert(finalRect, from: page)
        let screenRect = convert(viewRect, to: nil)
        let pageIndex = document.index(for: page)

        return PDFImageInfo(
            image: image,
            rect: finalRect,
            screenRect: screenRect,
            pageNumber: pageIndex + 1
        )
    }
}

// MARK: - Touch Monitoring Gesture
class TouchMonitoringGesture: UIGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
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
}
