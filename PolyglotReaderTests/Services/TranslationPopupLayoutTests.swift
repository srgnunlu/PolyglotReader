import XCTest
@testable import PolyglotReader

/// Unit tests for the pure popup positioning math (flip + clamp behavior).
final class TranslationPopupLayoutTests: XCTestCase {
    private let container = CGRect(x: 0, y: 0, width: 400, height: 800)
    private let popupSize = CGSize(width: 300, height: 200)

    // MARK: - Width

    func testPopupWidthPortrait() {
        XCTAssertEqual(TranslationPopupLayout.popupWidth(for: CGSize(width: 390, height: 844)), 340)
        XCTAssertEqual(TranslationPopupLayout.popupWidth(for: CGSize(width: 320, height: 568)), 280)
    }

    func testPopupWidthLandscape() {
        // accuracy: 700 * 0.7 is 489.999... in binary floating point
        XCTAssertEqual(TranslationPopupLayout.popupWidth(for: CGSize(width: 700, height: 400)), 490, accuracy: 0.001)
        XCTAssertEqual(TranslationPopupLayout.popupWidth(for: CGSize(width: 1200, height: 800)), 600, accuracy: 0.001)
    }

    // MARK: - Base Position

    func testPositionsBelowSelectionWhenThereIsRoom() {
        let selection = CGRect(x: 100, y: 100, width: 200, height: 20)
        let position = TranslationPopupLayout.basePosition(
            selectionRect: selection,
            popupSize: popupSize,
            container: container
        )

        // maxY(120) + gap(16) + halfHeight(100) = 236
        XCTAssertEqual(position.y, 236)
        XCTAssertEqual(position.x, 200)
    }

    func testFlipsAboveSelectionNearBottomEdge() {
        let selection = CGRect(x: 100, y: 700, width: 200, height: 20)
        let position = TranslationPopupLayout.basePosition(
            selectionRect: selection,
            popupSize: popupSize,
            container: container
        )

        // Below would overflow (836 + 108 > 800) → minY(700) - gap(16) - halfHeight(100) = 584
        XCTAssertEqual(position.y, 584)
    }

    func testClampsHorizontallyNearLeadingEdge() {
        let selection = CGRect(x: 0, y: 100, width: 20, height: 20)
        let position = TranslationPopupLayout.basePosition(
            selectionRect: selection,
            popupSize: popupSize,
            container: container
        )

        // midX(10) clamped to halfWidth(150) + padding(8) = 158
        XCTAssertEqual(position.x, 158)
    }

    func testStaysFullyInsideContainerEvenForOffscreenSelection() {
        let selection = CGRect(x: 380, y: 790, width: 40, height: 30)
        let position = TranslationPopupLayout.basePosition(
            selectionRect: selection,
            popupSize: popupSize,
            container: container
        )

        XCTAssertGreaterThanOrEqual(position.x - popupSize.width / 2, container.minX)
        XCTAssertLessThanOrEqual(position.x + popupSize.width / 2, container.maxX)
        XCTAssertGreaterThanOrEqual(position.y - popupSize.height / 2, container.minY)
        XCTAssertLessThanOrEqual(position.y + popupSize.height / 2, container.maxY)
    }

    // MARK: - Drag Clamping

    func testClampedOffsetKeepsPopupInsideContainer() {
        let base = CGPoint(x: 200, y: 400)
        let clamped = TranslationPopupLayout.clampedOffset(
            CGSize(width: 500, height: -500),
            base: base,
            popupSize: popupSize,
            container: container
        )

        // Center x range: [158, 242], y range: [108, 692]
        XCTAssertEqual(clamped.width, 42)
        XCTAssertEqual(clamped.height, -292)
    }

    func testClampedOffsetLeavesInBoundsDragUntouched() {
        let base = CGPoint(x: 200, y: 400)
        let clamped = TranslationPopupLayout.clampedOffset(
            CGSize(width: 30, height: 50),
            base: base,
            popupSize: popupSize,
            container: container
        )

        XCTAssertEqual(clamped.width, 30)
        XCTAssertEqual(clamped.height, 50)
    }

    func testOversizedPopupIsCenteredInsteadOfOscillating() {
        let small = CGRect(x: 0, y: 0, width: 200, height: 200)
        let position = TranslationPopupLayout.clamp(
            CGPoint(x: 500, y: 500),
            popupSize: CGSize(width: 400, height: 400),
            container: small
        )

        XCTAssertEqual(position.x, 100)
        XCTAssertEqual(position.y, 100)
    }

    // MARK: - Layout Context

    func testLayoutContextScaledSizeUsesLegacyDoubleScaling() {
        let context = TranslationPopupLayoutContext(
            containerSize: CGSize(width: 400, height: 800),
            selectionRect: CGRect(x: 100, y: 100, width: 100, height: 20),
            scale: 2.0
        )

        // Portrait content height 180 * scale(2) = 360; (28 + 360) * 2 = 776
        XCTAssertEqual(context.contentMaxHeight, 360)
        XCTAssertEqual(context.scaledSize.height, 776)
        XCTAssertEqual(context.scaledSize.width, 340 * 2)
    }

    func testLayoutContextRescaledPreservesInputs() {
        let context = TranslationPopupLayoutContext(
            containerSize: CGSize(width: 400, height: 800),
            selectionRect: CGRect(x: 100, y: 100, width: 100, height: 20),
            scale: 1.0
        )
        let rescaled = context.rescaled(to: 1.5)

        XCTAssertEqual(rescaled.scale, 1.5)
        XCTAssertEqual(rescaled.containerSize, context.containerSize)
        XCTAssertEqual(rescaled.selectionRect, context.selectionRect)
    }
}
