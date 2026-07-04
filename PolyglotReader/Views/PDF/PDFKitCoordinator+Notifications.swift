import UIKit
import PDFKit

extension PDFKitCoordinator {
    // MARK: - Notification Handlers

    @objc func pageChanged(_ notification: Notification) {
        guard let pdfView = notification.object as? PDFView,
              let currentPage = pdfView.currentPage,
              let document = pdfView.document else { return }

        let pageIndex = document.index(for: currentPage)
        if lastPageIndex == pageIndex { return }
        lastPageIndex = pageIndex

        lastSelectionTextForReport = nil

        DispatchQueue.main.async {
            // Mark this binding change as scroll-originated so syncCurrentPage
            // doesn't navigate back to a stale page during fast scrolling.
            self.suppressNextPageSync = true
            self.parent.currentPage = pageIndex + 1
        }
    }

    @objc func scaleChanged(_ notification: Notification) {
        guard let pdfView = notification.object as? PDFView else { return }
        let currentScale = pdfView.scaleFactor
        if lastScaleFactor == currentScale { return }
        lastScaleFactor = currentScale
    }

    @objc func selectionChanged(_ notification: Notification) {
        guard let view = notification.object as? PDFView else { return }

        if #available(iOS 16.0, *) {
            if view.window?.windowScene != nil {
                removeEditMenuInteractions(from: view)
            }
        } else {
            if view.window != nil {
                DispatchQueue.main.async {
                    UIMenuController.shared.hideMenu()
                }
            }
        }

        selectionDebounceTimer?.invalidate()

        guard let selection = view.currentSelection,
              let text = selection.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        selectionDebounceTimer = Timer.scheduledTimer(
            withTimeInterval: selectionDebounceDelay,
            repeats: false
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.reportSelectionImmediately()
            }
        }
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

    // MARK: - Reading-Order Selection Text

    /// Rebuilds selection text in reading order from per-line selections.
    /// Raw `selection.string` on multi-column academic PDFs yields wrong-order
    /// text and passes hyphenated line breaks through; this clusters lines into
    /// columns (left-to-right) and orders them top-to-bottom with hyphen merge.
    /// Falls back to the raw string if per-line data is missing or the rebuild
    /// comes out empty, so behavior never regresses on single-column text.
    func readingOrderText(for selection: PDFSelection, on page: PDFPage) -> String {
        let raw = selection.string ?? ""
        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else { return raw }

        let lines: [OCRTextLine] = selection.selectionsByLine().compactMap { lineSelection in
            guard let text = lineSelection.string, !text.isEmpty else { return nil }
            let bounds = lineSelection.bounds(for: page)
            guard !bounds.isNull, !bounds.isInfinite else { return nil }
            // Normalize to 0...1; PDF y-origin is bottom-left so higher midY = higher on page.
            let midX = Double((bounds.midX - pageBounds.minX) / pageBounds.width)
            let top = Double((bounds.midY - pageBounds.minY) / pageBounds.height)
            return OCRTextLine(text: text, midX: midX, top: top)
        }

        guard !lines.isEmpty else { return raw }
        let assembled = OCRTextAssembler.assemble(lines)
        return assembled.isEmpty ? raw : assembled
    }
}
