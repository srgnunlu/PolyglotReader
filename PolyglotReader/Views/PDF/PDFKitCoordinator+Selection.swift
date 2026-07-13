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

    /// Restores the exact pre-selection scroll offset in the current run-loop.
    /// Deferring this work lets PDFKit commit one frame at its erroneous target
    /// page, which presents as a visible last-page flash before snapping back.
    func restoreSelectionAnchorPosition(in view: CustomPDFView) {
        guard let anchorPage = view.selectionAnchorPage else { return }
        UIView.performWithoutAnimation {
            if let contentOffset = view.selectionAnchorContentOffset,
               let scrollView = view.scrollView {
                scrollView.layer.removeAllAnimations()
                scrollView.setContentOffset(contentOffset, animated: false)
                scrollView.layoutIfNeeded()
            } else {
                view.go(to: anchorPage)
            }
            view.layoutIfNeeded()
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
