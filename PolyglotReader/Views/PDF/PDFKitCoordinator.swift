import UIKit
import PDFKit
import SwiftUI

class PDFKitCoordinator: NSObject, UIGestureRecognizerDelegate {
    var parent: PDFKitView
    weak var pdfView: PDFView?

    // Render tamamlandığında çağrılacak callback
    var onRenderComplete: (() -> Void)?

    // MARK: - Handlers
    private let annotationHandler = PDFAnnotationHandler()

    // MARK: - Annotation Cache
    /// Son uygulanan annotation'ların hash'i
    var lastAnnotationHash: Int = 0

    // Debounce state
    var lastSelectionText: String?
    var lastPageIndex: Int?
    var lastSelectionTextForReport: String? // Duplicate check
    var lastScaleFactor: CGFloat?

    var selectionDebounceTimer: Timer?
    let selectionDebounceDelay: TimeInterval = 1.0

    // MARK: - Image Long-Press Handling
    var isHandlingImageLongPress = false
    weak var customLongPressGesture: UILongPressGestureRecognizer?

    // Scanning Feedback
    private var scanningFeedbackView: UIView?
    
    // Restoration State
    var hasRestoredInitialPosition = false

    // MARK: - Page Sync / Progress Throttle
    /// Set when a scroll-driven page-change notification updates the binding, so the
    /// next `updateUIView` pass skips programmatic navigation. Without this, fast
    /// scrolling races the binding update and PDFKit gets yanked back a page.
    var suppressNextPageSync = false

    /// Throttle reading-progress writes: scrolling fires `scrollViewDidScroll` on
    /// every tick, which otherwise produces a Supabase write storm.
    private var lastProgressReport: Date = .distantPast
    private let progressReportInterval: TimeInterval = 0.75

    init(_ parent: PDFKitView) {
        self.parent = parent
    }

    deinit {
        selectionDebounceTimer?.invalidate()
    }

    // MARK: - Annotation Handling

    func applyAnnotationUpdate(to document: PDFDocument, annotations: [Annotation]) {
        // Use Handler
        if let newHash = annotationHandler.applyAnnotations(
            to: document,
            annotations: annotations,
            lastHash: lastAnnotationHash
        ) {
            lastAnnotationHash = newHash
        }
    }

    // MARK: - Touch State Handler

    func handleTouchEnded() {
        selectionDebounceTimer?.invalidate()
        selectionDebounceTimer = nil
        reportSelectionImmediately()
    }

    func reportSelectionImmediately() {
        guard let customPdfView = pdfView as? CustomPDFView,
              let selection = customPdfView.managedSelection ?? customPdfView.currentSelection,
              let page = selection.pages.first,
              let document = customPdfView.document else { return }

        // Rebuild the reported text in reading order (multi-column + hyphen-aware)
        // instead of the raw `selection.string`. Rects below are untouched.
        let selectedText = readingOrderText(for: selection, on: page)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedText.count >= 2 else { return }

        lastSelectionTextForReport = selectedText

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

        // Calculate PDF rects for each line (for annotation positioning)
        var pdfRects: [CGRect] = []
        for lineSelection in selection.selectionsByLine() {
            let lineBounds = lineSelection.bounds(for: page)
            if !lineBounds.isNull && !lineBounds.isInfinite && lineBounds.width > 0 && lineBounds.height > 0 {
                pdfRects.append(lineBounds)
            }
        }

        DispatchQueue.main.async {
            self.parent.onSelection?(selectedText, screenBounds, pageIndex + 1, pdfRects)
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if isHandlingImageLongPress {
            if gestureRecognizer !== customLongPressGesture {
                return false
            }
        }

        if gestureRecognizer === customLongPressGesture {
            guard let customPdfView = pdfView as? CustomPDFView else { return true }
            let location = gestureRecognizer.location(in: customPdfView)

            guard let page = customPdfView.page(for: location, nearest: true) else { return true }
            let pdfPoint = customPdfView.convert(location, to: page)

            // Check for text under finger
            if checkForText(at: pdfPoint, page: page) {
                return false // Text present -> let native selection handle
            }
        }

        return true
    }

    private func checkForText(at pdfPoint: CGPoint, page: PDFPage) -> Bool {
        if let selection = page.selectionForWord(at: pdfPoint) {
            let selectionBounds = selection.bounds(for: page)
            let hitTestBounds = selectionBounds.insetBy(dx: -25, dy: -25)

            if hitTestBounds.contains(pdfPoint) {
                if let text = selection.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return true
                }
            }
        }

        // Backup char check
        if let charSelection = page.selection(
            for: CGRect(
                x: pdfPoint.x - 10,
                y: pdfPoint.y - 10,
                width: 20,
                height: 20
            )
        ) {
            if let text = charSelection.string,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
        }

        return false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if isHandlingImageLongPress { return false }

        if gestureRecognizer === customLongPressGesture {
            if otherGestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIPanGestureRecognizer {
                return true
            }
            return false
        }
        return true
    }

    // MARK: - Gesture Handlers

    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let customPdfView = pdfView as? CustomPDFView else { return }

        switch gesture.state {
        case .began:
            let location = gesture.location(in: customPdfView)
            guard let page = customPdfView.page(for: location, nearest: true) else { return }
            let pdfPoint = customPdfView.convert(location, to: page)

            if checkForText(at: pdfPoint, page: page) {
                gesture.state = .cancelled
                return
            }

            // Start Image Detection
            isHandlingImageLongPress = true
            disableNativeSelectionGestures(in: customPdfView)

            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showScanningFeedback(at: pdfPoint, page: page, in: customPdfView)

            Task {
                let imageBounds = await PDFImageService.shared.detectImage(at: pdfPoint, in: page)
                await MainActor.run {
                    self.handleImageDetectionResult(imageBounds, at: pdfPoint, in: page, customPdfView: customPdfView)
                }
            }

        case .changed:
            break

        case .ended, .cancelled, .failed:
            if !isHandlingImageLongPress {
                enableNativeSelectionGestures(in: customPdfView)
            }
            removeScanningFeedback(in: customPdfView)

        default:
            break
        }
    }

    private func handleImageDetectionResult(
        _ bounds: CGRect?,
        at point: CGPoint,
        in page: PDFPage,
        customPdfView: CustomPDFView
    ) {
        self.removeScanningFeedback(in: customPdfView)

        if let bounds = bounds {
            // Found Image
            if !self.isHandlingImageLongPress {
                self.isHandlingImageLongPress = true
                self.disableNativeSelectionGestures(in: customPdfView)
            }

            customPdfView.clearManagedSelection()
            self.showImageSelectionHighlight(rect: bounds, page: page, in: customPdfView)

            if let imageInfo = customPdfView.captureImageFromBounds(bounds, page: page) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()

                self.parent.onSelection?("", CGRect.zero, 0, [])
                self.parent.onImageSelection?(imageInfo)

                // Reset gesture to avoid repeat triggers
                // gesture.isEnabled = false // Not accessible here directly unless passed
                // gesture.isEnabled = true

                self.isHandlingImageLongPress = false
                self.enableNativeSelectionGestures(in: customPdfView)
            } else {
                self.isHandlingImageLongPress = false
                self.enableNativeSelectionGestures(in: customPdfView)
            }
        } else {
            // Not Found
            if self.isHandlingImageLongPress {
                self.isHandlingImageLongPress = false
                self.enableNativeSelectionGestures(in: customPdfView)
            }
        }
    }

    // MARK: - Visual Feedback Helpers

    private func showScanningFeedback(at point: CGPoint, page: PDFPage, in view: PDFView) {
        removeScanningFeedback(in: view)

        let viewPoint = view.convert(point, from: page)
        let size: CGFloat = 60
        let frame = CGRect(x: viewPoint.x - size / 2, y: viewPoint.y - size / 2, width: size, height: size)

        let feedbackView = UIView(frame: frame)
        feedbackView.backgroundColor = UIColor.gray.withAlphaComponent(0.2)
        feedbackView.layer.cornerRadius = size / 2
        feedbackView.isUserInteractionEnabled = false
        feedbackView.tag = 999

        view.addSubview(feedbackView)
        scanningFeedbackView = feedbackView

        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            options: [.autoreverse, .repeat],
            animations: {
                feedbackView.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
                feedbackView.alpha = 0.1
            },
            completion: nil
        )
    }

    private func removeScanningFeedback(in view: UIView) {
        scanningFeedbackView?.removeFromSuperview()
        scanningFeedbackView = nil
        view.subviews.first { $0.tag == 999 }?.removeFromSuperview()
    }

    private func showImageSelectionHighlight(rect: CGRect, page: PDFPage, in view: PDFView) {
        let viewRect = view.convert(rect, from: page)
        let highlightView = UIView(frame: viewRect)
        highlightView.backgroundColor = UIColor.systemIndigo.withAlphaComponent(0.22)
        highlightView.layer.borderColor = UIColor.systemIndigo.cgColor
        highlightView.layer.borderWidth = 2.5
        highlightView.layer.cornerRadius = 6
        highlightView.isUserInteractionEnabled = false
        view.addSubview(highlightView)

        // Pop-in: hafif büyük başlayıp figürün üstüne otur — tespit edilen
        // sınırlar solmadan önce net biçimde görülsün.
        highlightView.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
        highlightView.alpha = 0
        UIView.animate(
            withDuration: 0.25,
            delay: 0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.5
        ) {
            highlightView.transform = .identity
            highlightView.alpha = 1
        } completion: { _ in
            UIView.animate(withDuration: 0.35, delay: 0.9, options: .curveEaseOut) {
                highlightView.alpha = 0
            } completion: { _ in
                highlightView.removeFromSuperview()
            }
        }
    }

    // MARK: - Native Gesture Control

    private func disableNativeSelectionGestures(in view: UIView) {
        for gesture in view.gestureRecognizers ?? [] where gesture !== customLongPressGesture {
            if gesture is UILongPressGestureRecognizer {
                gesture.isEnabled = false
            }
        }
        for subview in view.subviews {
            disableNativeSelectionGestures(in: subview)
        }
    }

    private func enableNativeSelectionGestures(in view: UIView) {
        for gesture in view.gestureRecognizers ?? [] {
            gesture.isEnabled = true
        }
        for subview in view.subviews {
            enableNativeSelectionGestures(in: subview)
        }
    }

    // MARK: - Focus Mode (iki parmak çift dokunuş)

    @objc func handleTwoFingerDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        DispatchQueue.main.async {
            self.parent.onTwoFingerDoubleTap?()
        }
    }

    // MARK: - Tap Handler

    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let pdfView = pdfView else { return }
        let tapLocation = gesture.location(in: pdfView)
        // Dokunuşun dikey konumu (0-1) — bar toggle bölge mantığına taşınır.
        let tapYFraction = tapLocation.y / max(pdfView.bounds.height, 1)

        // Note Icon Check
        if let page = pdfView.page(for: tapLocation, nearest: true) {
            let pdfPoint = pdfView.convert(tapLocation, to: page)

            for pdfAnnotation in page.annotations
            where pdfAnnotation.value(forAnnotationKey: .name) as? String == "PolyglotNote" {
                let hitTestBounds = pdfAnnotation.bounds.insetBy(dx: -15, dy: -15)
                if hitTestBounds.contains(pdfPoint) {
                    if let annotationId = pdfAnnotation.userName {
                        if let annotation = parent.annotations.first(where: { $0.id == annotationId }) {
                            DispatchQueue.main.async {
                                self.parent.onAnnotationTap?(annotation)
                            }
                            return
                        }
                    }
                }
            }
        }

        // Clear Selection Check
        if let currentSelection = pdfView.currentSelection,
           let page = currentSelection.pages.first {
            let userRect = currentSelection.bounds(for: page)
            let viewBounds = pdfView.convert(userRect, from: page)
            let expandedBounds = viewBounds.insetBy(dx: -40, dy: -40)

            if !expandedBounds.contains(tapLocation) {
                pdfView.clearSelection()
                lastSelectionTextForReport = nil

                DispatchQueue.main.async {
                    self.parent.onSelection?("", CGRect.zero, 0, [])
                    self.parent.onTap?(tapYFraction)
                }
            }
        } else {
            DispatchQueue.main.async {
                self.parent.onTap?(tapYFraction)
            }
        }
    }
}

// MARK: - UIScrollViewDelegate
extension PDFKitCoordinator: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        reportProgressThrottled()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        reportProgressThrottled()
    }

    // Scroll/zoom durduğunda son konumu mutlaka yaz (throttle'ı atlayarak),
    // böylece kullanıcının bıraktığı yer kaybolmaz.
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        emitProgress()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { emitProgress() }
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        emitProgress()
    }

    /// Time-throttled progress emit for the continuous scroll/zoom stream.
    private func reportProgressThrottled() {
        let now = Date()
        guard now.timeIntervalSince(lastProgressReport) >= progressReportInterval else { return }
        emitProgress()
    }

    /// `currentDestination` is the robust "current reading position" on PDFView.
    private func emitProgress() {
        lastProgressReport = Date()
        guard let pdfView = pdfView, let document = pdfView.document else { return }

        if let destination = pdfView.currentDestination,
           let page = destination.page {
            let point = destination.point
            let pageIndex = document.index(for: page)
            let scale = pdfView.scaleFactor
            parent.onProgressChange?(pageIndex + 1, point, scale)
        }
    }
}
