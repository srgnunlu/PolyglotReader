import CoreGraphics
import PDFKit

/// Converts annotation rectangles between PDFKit page space and the canonical
/// cross-platform storage format shared with the web app.
///
/// Canonical format (what web has always written and both platforms read):
/// - Percentages 0-100 of the page as DISPLAYED
/// - Top-left origin
/// - "Displayed page" = the cropBox with the page /Rotate entry applied.
///   This is exactly what pdf.js `getViewport({ scale: 1 })` produces on web,
///   so a percentage means the same physical spot on both platforms.
///
/// Legacy format (old iOS annotations): raw PDFKit page-space points,
/// bottom-left origin. Values are typically > 100, which is how read paths
/// tell the two formats apart (see `isCanonicalPercent`).
struct AnnotationCoordinateConverter {
    /// Crop box in PDF user space (bottom-left origin, unrotated).
    let cropBox: CGRect
    /// Page rotation normalized to 0, 90, 180 or 270 degrees.
    let rotation: Int

    /// Fails on degenerate/non-finite crop boxes so callers can fall back
    /// instead of producing NaN percentages.
    init?(cropBox: CGRect, rotation: Int) {
        guard cropBox.width > 0, cropBox.height > 0,
              cropBox.origin.x.isFinite, cropBox.origin.y.isFinite,
              cropBox.width.isFinite, cropBox.height.isFinite else { return nil }
        self.cropBox = cropBox
        // Normalize to [0, 360) and snap to a multiple of 90 (PDF spec requires
        // /Rotate to be a multiple of 90; snap defensively for malformed files).
        let normalized = ((rotation % 360) + 360) % 360
        self.rotation = (normalized / 90) * 90
    }

    init?(page: PDFPage) {
        self.init(cropBox: page.bounds(for: .cropBox), rotation: page.rotation)
    }

    /// Heuristic shared with the web read path (AnnotationLayer.tsx): rects
    /// whose values all fit in 0-100 are canonical percentages; anything
    /// larger is a legacy iOS point rect. Kept for backward compatibility.
    static func isCanonicalPercent(_ rect: CGRect) -> Bool {
        rect.origin.x <= 100 && rect.origin.y <= 100 && rect.width <= 100 && rect.height <= 100
    }

    /// Size of the page as displayed (pdf.js viewport size at scale 1):
    /// cropBox dimensions, swapped for 90/270 rotation.
    var displayedSize: CGSize {
        rotation == 90 || rotation == 270
            ? CGSize(width: cropBox.height, height: cropBox.width)
            : CGSize(width: cropBox.width, height: cropBox.height)
    }

    // MARK: - Page space -> Canonical

    /// Converts a PDFKit page-space rect (bottom-left origin, PDF user space)
    /// into canonical percentages of the displayed page (top-left origin).
    /// Returns nil for degenerate rects or rects entirely outside the cropBox.
    func toCanonicalPercent(pageSpaceRect rect: CGRect) -> CGRect? {
        guard isUsable(rect) else { return nil }

        // Work relative to the cropBox: distances from its left and bottom
        // edges (both still bottom-left oriented PDF user space).
        let fromLeft = rect.minX - cropBox.minX
        let fromBottom = rect.minY - cropBox.minY
        let cbW = cropBox.width
        let cbH = cropBox.height

        // Map into the displayed (rotated, top-left origin) frame. Derived
        // from the pdf.js PageViewport transform so web and iOS agree.
        let displayed: CGRect
        switch rotation {
        case 90:
            displayed = CGRect(x: fromBottom, y: fromLeft, width: rect.height, height: rect.width)
        case 180:
            displayed = CGRect(
                x: cbW - fromLeft - rect.width,
                y: fromBottom,
                width: rect.width,
                height: rect.height
            )
        case 270:
            displayed = CGRect(
                x: cbH - fromBottom - rect.height,
                y: cbW - fromLeft - rect.width,
                width: rect.height,
                height: rect.width
            )
        default: // 0
            displayed = CGRect(
                x: fromLeft,
                y: cbH - fromBottom - rect.height,
                width: rect.width,
                height: rect.height
            )
        }

        let size = displayedSize
        let percent = CGRect(
            x: displayed.minX / size.width * 100,
            y: displayed.minY / size.height * 100,
            width: displayed.width / size.width * 100,
            height: displayed.height / size.height * 100
        )
        return clampToPage(percent)
    }

    // MARK: - Canonical -> Page space

    /// Inverts `toCanonicalPercent`: canonical percentages (top-left origin,
    /// displayed page) back to PDFKit page-space points (bottom-left origin).
    func toPageSpace(canonicalPercent rect: CGRect) -> CGRect? {
        guard isUsable(rect) else { return nil }

        let size = displayedSize
        let dispX = rect.minX / 100 * size.width
        let dispY = rect.minY / 100 * size.height
        let dispW = rect.width / 100 * size.width
        let dispH = rect.height / 100 * size.height
        let cbW = cropBox.width
        let cbH = cropBox.height

        // Undo the rotation mapping used in toCanonicalPercent.
        let fromLeft: CGFloat, fromBottom: CGFloat, pdfW: CGFloat, pdfH: CGFloat
        switch rotation {
        case 90:
            fromBottom = dispX; pdfH = dispW
            fromLeft = dispY; pdfW = dispH
        case 180:
            fromLeft = cbW - dispX - dispW; pdfW = dispW
            fromBottom = dispY; pdfH = dispH
        case 270:
            fromBottom = cbH - dispX - dispW; pdfH = dispW
            fromLeft = cbW - dispY - dispH; pdfW = dispH
        default: // 0
            fromLeft = dispX; pdfW = dispW
            fromBottom = cbH - dispY - dispH; pdfH = dispH
        }

        return CGRect(
            x: fromLeft + cropBox.minX,
            y: fromBottom + cropBox.minY,
            width: pdfW,
            height: pdfH
        )
    }

    // MARK: - Helpers

    private func isUsable(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.width > 0 && rect.height > 0
    }

    /// Clamps percentages to the visible page (0-100). Content outside the
    /// cropBox is not displayed anyway, and clamping guarantees the <=100
    /// heuristic can never misclassify a canonical rect as legacy points.
    private func clampToPage(_ rect: CGRect) -> CGRect? {
        let minX = min(max(rect.minX, 0), 100)
        let minY = min(max(rect.minY, 0), 100)
        let maxX = min(max(rect.maxX, 0), 100)
        let maxY = min(max(rect.maxY, 0), 100)
        guard maxX > minX, maxY > minY else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

extension AnnotationCoordinateConverter {
    /// Converts PDFKit selection rects into canonical `AnnotationRect`s for
    /// storage. Returns nil when the page or its cropBox is unavailable so
    /// callers can fall back to the legacy point format.
    static func canonicalAnnotationRects(from pageSpaceRects: [CGRect], page: PDFPage?) -> [AnnotationRect]? {
        guard let page, let converter = AnnotationCoordinateConverter(page: page) else { return nil }
        let canonical = pageSpaceRects.compactMap { converter.toCanonicalPercent(pageSpaceRect: $0) }
        guard !canonical.isEmpty else { return nil }
        return canonical.map { AnnotationRect(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height) }
    }
}
