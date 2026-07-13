import PDFKit

// MARK: - Page-local Selection Resolution

/// Keeps a native PDFKit selection on the page where the interaction began.
/// Some tagged/table PDFs report a noncontiguous selection that stretches to a
/// later page; rebuilding it from that page's line selections prevents PDFView
/// from scrolling the reader to the end of the document.
@MainActor
enum PDFSelectionResolver {
    static func selection(
        on page: PDFPage,
        from source: PDFSelection,
        anchorPoint: CGPoint? = nil,
        currentPoint: CGPoint? = nil
    ) -> PDFSelection? {
        guard let document = page.document else { return nil }
        let targetPageIndex = document.index(for: page)

        if source.pages.count == 1,
           source.pages.first.map({ document.index(for: $0) == targetPageIndex }) == true {
            return source
        }

        let pageLines = source.selectionsByLine().filter { line in
            line.pages.contains { document.index(for: $0) == targetPageIndex }
                && isValid(line.bounds(for: page))
        }

        if !pageLines.isEmpty {
            let resolved = PDFSelection(document: document)
            resolved.add(pageLines)
            if hasText(resolved) {
                return resolved
            }
        }

        let pageBounds = source.bounds(for: page)
        if isValid(pageBounds),
           let fallback = page.selection(for: pageBounds),
           hasText(fallback) {
            return fallback
        }

        return touchSelection(on: page, anchorPoint: anchorPoint, currentPoint: currentPoint)
    }

    private static func touchSelection(
        on page: PDFPage,
        anchorPoint: CGPoint?,
        currentPoint: CGPoint?
    ) -> PDFSelection? {
        guard let anchorPoint else { return nil }

        if let currentPoint,
           hypot(currentPoint.x - anchorPoint.x, currentPoint.y - anchorPoint.y) > 4,
           let rangeSelection = page.selection(from: anchorPoint, to: currentPoint),
           hasText(rangeSelection) {
            return rangeSelection
        }

        if let wordSelection = page.selectionForWord(at: anchorPoint), hasText(wordSelection) {
            return wordSelection
        }

        let touchRect = CGRect(x: anchorPoint.x - 12, y: anchorPoint.y - 12, width: 24, height: 24)
        guard let nearbySelection = page.selection(for: touchRect), hasText(nearbySelection) else { return nil }
        return nearbySelection
    }

    private static func isValid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.width > 0 && rect.height > 0
    }

    private static func hasText(_ selection: PDFSelection) -> Bool {
        guard let text = selection.string else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Pure decision used by the PDFView notification bridge and regression tests.
nonisolated enum PDFSelectionInteractionPolicy {
    static func allowsPageChange(
        to pageIndex: Int,
        anchorPageIndex: Int?,
        shouldProtectSelection: Bool
    ) -> Bool {
        guard shouldProtectSelection, let anchorPageIndex else { return true }
        return pageIndex == anchorPageIndex
    }
}
