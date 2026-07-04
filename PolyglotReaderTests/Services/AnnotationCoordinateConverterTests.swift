import XCTest
import PDFKit
@testable import PolyglotReader

/// Unit tests for AnnotationCoordinateConverter — the canonical annotation
/// coordinate math shared (by convention) with the web app.
///
/// Canonical format: percentages 0-100 of the displayed page (cropBox with
/// page rotation applied), top-left origin. Legacy format: raw PDFKit
/// page-space points, distinguished by the "all values <= 100" heuristic.
final class AnnotationCoordinateConverterTests: XCTestCase {
    /// cropBox deliberately offset from a typical Letter mediaBox (0,0,612,792)
    /// to catch math that ignores the cropBox origin.
    private let offsetCropBox = CGRect(x: 20, y: 30, width: 500, height: 700)

    /// A text-line-like selection rect in PDF page space (bottom-left origin).
    private let sampleRect = CGRect(x: 100, y: 200, width: 150, height: 20)

    private let accuracy: CGFloat = 0.0001

    private func makeConverter(rotation: Int) -> AnnotationCoordinateConverter {
        guard let converter = AnnotationCoordinateConverter(cropBox: offsetCropBox, rotation: rotation) else {
            XCTFail("Converter should initialize for valid cropBox")
            fatalError("unreachable")
        }
        return converter
    }

    private func assertRectsEqual(_ lhs: CGRect, _ rhs: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.minX, rhs.minX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.minY, rhs.minY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.width, rhs.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.height, rhs.height, accuracy: accuracy, file: file, line: line)
    }

    // MARK: - Round trips (points -> canonical -> points)

    func testRoundTripAtAllRotations() throws {
        for rotation in [0, 90, 180, 270] {
            let converter = makeConverter(rotation: rotation)
            let canonical = try XCTUnwrap(converter.toCanonicalPercent(pageSpaceRect: sampleRect))

            // Canonical values must fit the percentage heuristic
            XCTAssertTrue(AnnotationCoordinateConverter.isCanonicalPercent(canonical), "rotation \(rotation)")

            let restored = try XCTUnwrap(converter.toPageSpace(canonicalPercent: canonical))
            assertRectsEqual(restored, sampleRect)
        }
    }

    func testRoundTripWithZeroOriginCropBox() throws {
        let cropBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let converter = try XCTUnwrap(AnnotationCoordinateConverter(cropBox: cropBox, rotation: 0))
        let canonical = try XCTUnwrap(converter.toCanonicalPercent(pageSpaceRect: sampleRect))
        let restored = try XCTUnwrap(converter.toPageSpace(canonicalPercent: canonical))
        assertRectsEqual(restored, sampleRect)
    }

    // MARK: - Known values (must match pdf.js viewport semantics)

    func testCanonicalValuesRotation0() throws {
        let converter = makeConverter(rotation: 0)
        let canonical = try XCTUnwrap(converter.toCanonicalPercent(pageSpaceRect: sampleRect))

        // u = 100-20 = 80, v = 200-30 = 170 (cropBox-relative)
        XCTAssertEqual(canonical.minX, 80.0 / 500.0 * 100, accuracy: accuracy)
        // Top-left origin: y% = (cbH - v - h) / cbH = (700-170-20)/700
        XCTAssertEqual(canonical.minY, 510.0 / 700.0 * 100, accuracy: accuracy)
        XCTAssertEqual(canonical.width, 150.0 / 500.0 * 100, accuracy: accuracy)
        XCTAssertEqual(canonical.height, 20.0 / 700.0 * 100, accuracy: accuracy)
    }

    func testCanonicalValuesRotation90() throws {
        let converter = makeConverter(rotation: 90)
        // Displayed page is cropBox rotated: 700 wide x 500 tall
        XCTAssertEqual(converter.displayedSize, CGSize(width: 700, height: 500))

        let canonical = try XCTUnwrap(converter.toCanonicalPercent(pageSpaceRect: sampleRect))
        // pdf.js rotation-90 mapping: dispX = v, dispY = u (u=80, v=170)
        XCTAssertEqual(canonical.minX, 170.0 / 700.0 * 100, accuracy: accuracy)
        XCTAssertEqual(canonical.minY, 80.0 / 500.0 * 100, accuracy: accuracy)
        XCTAssertEqual(canonical.width, 20.0 / 700.0 * 100, accuracy: accuracy)
        XCTAssertEqual(canonical.height, 150.0 / 500.0 * 100, accuracy: accuracy)
    }

    func testWebPercentageRectMapsToExpectedPageSpace() throws {
        // A rect the web app would have written: 10% from left, 20% from top
        let cropBox = CGRect(x: 0, y: 0, width: 600, height: 800)
        let converter = try XCTUnwrap(AnnotationCoordinateConverter(cropBox: cropBox, rotation: 0))
        let webRect = CGRect(x: 10, y: 20, width: 30, height: 5)

        let pageRect = try XCTUnwrap(converter.toPageSpace(canonicalPercent: webRect))
        // x = 60pt; y (bottom-left) = 800 - 25% of 800 = 600pt
        assertRectsEqual(pageRect, CGRect(x: 60, y: 600, width: 180, height: 40))
    }

    // MARK: - Clamping and degenerate input

    func testRectOutsideCropBoxIsClampedToPage() throws {
        let converter = makeConverter(rotation: 0)
        // Extends 30pt left of the cropBox's left edge (x < 20)
        let overhanging = CGRect(x: -10, y: 200, width: 150, height: 20)

        let canonical = try XCTUnwrap(converter.toCanonicalPercent(pageSpaceRect: overhanging))
        XCTAssertGreaterThanOrEqual(canonical.minX, 0)
        XCTAssertLessThanOrEqual(canonical.maxX, 100)
        XCTAssertTrue(AnnotationCoordinateConverter.isCanonicalPercent(canonical))
    }

    func testRectEntirelyOutsideCropBoxReturnsNil() {
        let converter = makeConverter(rotation: 0)
        let outside = CGRect(x: -300, y: 200, width: 100, height: 20)
        XCTAssertNil(converter.toCanonicalPercent(pageSpaceRect: outside))
    }

    func testDegenerateInputsReturnNil() {
        XCTAssertNil(AnnotationCoordinateConverter(cropBox: .zero, rotation: 0))

        let converter = makeConverter(rotation: 0)
        XCTAssertNil(converter.toCanonicalPercent(pageSpaceRect: .zero))
        XCTAssertNil(converter.toPageSpace(canonicalPercent: .zero))
        XCTAssertNil(converter.toCanonicalPercent(pageSpaceRect: .infinite))
    }

    func testRotationNormalization() throws {
        let negative = try XCTUnwrap(AnnotationCoordinateConverter(cropBox: offsetCropBox, rotation: -90))
        XCTAssertEqual(negative.rotation, 270)

        let wrapped = try XCTUnwrap(AnnotationCoordinateConverter(cropBox: offsetCropBox, rotation: 450))
        XCTAssertEqual(wrapped.rotation, 90)
    }

    // MARK: - Legacy heuristic boundary

    func testLegacyHeuristicBoundary() {
        // All values exactly 100 -> still treated as canonical percentage
        XCTAssertTrue(AnnotationCoordinateConverter.isCanonicalPercent(
            CGRect(x: 100, y: 100, width: 100, height: 100)
        ))
        // Any single value above 100 -> legacy point rect
        XCTAssertFalse(AnnotationCoordinateConverter.isCanonicalPercent(
            CGRect(x: 100.5, y: 10, width: 10, height: 10)
        ))
        XCTAssertFalse(AnnotationCoordinateConverter.isCanonicalPercent(
            CGRect(x: 10, y: 10, width: 150, height: 10)
        ))
    }

    // MARK: - PDFPage-backed initialization

    func testConverterFromBlankPDFPage() throws {
        // Blank PDFPage lets us exercise init(page:) without a fixture PDF
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        page.setBounds(offsetCropBox, for: .cropBox)
        page.rotation = 90

        let converter = try XCTUnwrap(AnnotationCoordinateConverter(page: page))
        XCTAssertEqual(converter.rotation, 90)
        assertRectsEqual(converter.cropBox, offsetCropBox)

        let canonical = try XCTUnwrap(converter.toCanonicalPercent(pageSpaceRect: sampleRect))
        let restored = try XCTUnwrap(converter.toPageSpace(canonicalPercent: canonical))
        assertRectsEqual(restored, sampleRect)
    }
}
