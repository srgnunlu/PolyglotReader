import PDFKit

// MARK: - Page-local Selection Protection

extension PDFKitCoordinator {
    /// Resolves an anomalous cross-page native selection back onto the page
    /// where the touch began. Assigning the page-local selection also removes
    /// PDFKit's highlight from unrelated pages.
    func resolvedSelection(in view: CustomPDFView) -> PDFSelection? {
        let source = view.managedSelection ?? view.currentSelection
        guard let source else { return nil }
        guard let anchorPage = view.selectionAnchorPage,
              let document = view.document,
              let anchorPageIndex = view.selectionAnchorPageIndex,
              let resolved = resolvedSelection(
                  source,
                  on: anchorPage,
                  anchorPageIndex: anchorPageIndex,
                  document: document,
                  view: view
              ) else {
            return source
        }

        if !isApplyingResolvedSelection {
            isApplyingResolvedSelection = true
            view.managedSelection = resolved
            isApplyingResolvedSelection = false
        }
        armSelectionPageProtection(at: anchorPageIndex)
        restoreSelectionAnchorPosition(in: view)
        return resolved
    }

    private func resolvedSelection(
        _ source: PDFSelection,
        on anchorPage: PDFPage,
        anchorPageIndex: Int,
        document: PDFDocument,
        view: CustomPDFView
    ) -> PDFSelection? {
        let includesAnchor = source.pages.contains { document.index(for: $0) == anchorPageIndex }
        guard source.pages.count > 1 || !includesAnchor else { return nil }
        return PDFSelectionResolver.selection(
            on: anchorPage,
            from: source,
            anchorPoint: view.selectionAnchorPoint,
            currentPoint: view.selectionCurrentPoint
        )
    }

    /// Restores the exact pre-selection scroll offset rather than merely going
    /// to the page top, so protecting against a bad table range is visually
    /// stable for the reader.
    func restoreSelectionAnchorPosition(in view: CustomPDFView) {
        guard let anchorPage = view.selectionAnchorPage else { return }
        let contentOffset = view.selectionAnchorContentOffset

        DispatchQueue.main.async {
            if let contentOffset, let scrollView = view.scrollView {
                scrollView.setContentOffset(contentOffset, animated: false)
            } else {
                view.go(to: anchorPage)
            }
        }
    }

    func clearSelectionPageProtection() {
        selectionProtectionTimer?.invalidate()
        selectionProtectionTimer = nil
        protectedSelectionPageIndex = nil
    }

    func clearNativeSelection(in view: PDFView) {
        if let customPDFView = view as? CustomPDFView {
            customPDFView.clearManagedSelection()
        } else {
            view.clearSelection()
        }
        clearSelectionPageProtection()
    }

    private func armSelectionPageProtection(at pageIndex: Int?) {
        guard let pageIndex else { return }
        protectedSelectionPageIndex = pageIndex
        selectionProtectionTimer?.invalidate()
        selectionProtectionTimer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: false) { [weak self] _ in
            self?.protectedSelectionPageIndex = nil
        }
    }
}
