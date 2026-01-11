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
}
