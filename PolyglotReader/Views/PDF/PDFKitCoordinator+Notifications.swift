import UIKit
import PDFKit

extension PDFKitCoordinator {
    // MARK: - Notification Handlers

    @objc func pageChanged(_ notification: Notification) {
        guard let pdfView = notification.object as? PDFView,
              let currentPage = pdfView.currentPage,
              let document = pdfView.document else { return }

        let pageIndex = document.index(for: currentPage)

        if let customPDFView = pdfView as? CustomPDFView {
            let selectionPages = customPDFView.currentSelection?.pages ?? []
            let protectedPageIndex = protectedSelectionPageIndex ?? customPDFView.selectionAnchorPageIndex
            let includesAnchor = protectedPageIndex.map { anchorIndex in
                selectionPages.contains { document.index(for: $0) == anchorIndex }
            } ?? true
            let hasAnomalousSelection = selectionPages.count > 1
                || (!selectionPages.isEmpty && !includesAnchor)
            let shouldProtectSelection = hasAnomalousSelection || protectedSelectionPageIndex != nil
            if !PDFSelectionInteractionPolicy.allowsPageChange(
                to: pageIndex,
                anchorPageIndex: protectedPageIndex,
                shouldProtectSelection: shouldProtectSelection
            ) {
                _ = resolvedSelection(in: customPDFView)
                restoreSelectionAnchorPosition(in: customPDFView)
                return
            }
        }

        if lastPageIndex == pageIndex { return }
        lastPageIndex = pageIndex

        lastSelectionTextForReport = nil
        emitProgress()

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

        if isApplyingResolvedSelection { return }

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

        let selection: PDFSelection?
        if let customPDFView = view as? CustomPDFView {
            selection = resolvedSelection(in: customPDFView)
        } else {
            selection = view.currentSelection
        }

        guard let selection,
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
}
