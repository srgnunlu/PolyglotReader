import PDFKit
import UIKit
import XCTest
@testable import PolyglotReader

@MainActor
final class PDFSelectionResolverTests: XCTestCase {
    func testSelectionIsLimitedToTheTouchedPage() throws {
        let document = try makeDocument(pages: [
            ["First page"],
            ["Target table row", "Target table value"],
            ["Last page"]
        ])
        let targetPage = try XCTUnwrap(document.page(at: 1))
        let lastPage = try XCTUnwrap(document.page(at: 2))
        let targetSelection = try wholePageSelection(on: targetPage)
        let lastSelection = try wholePageSelection(on: lastPage)
        let crossPageSelection = PDFSelection(document: document)
        crossPageSelection.add([targetSelection, lastSelection])

        let resolved = try XCTUnwrap(
            PDFSelectionResolver.selection(on: targetPage, from: crossPageSelection)
        )

        XCTAssertEqual(resolved.pages.count, 1)
        XCTAssertTrue(resolved.pages.first === targetPage)
        XCTAssertTrue(resolved.string?.contains("Target table row") == true)
        XCTAssertFalse(resolved.string?.contains("Last page") == true)
    }

    func testSelectionKeepsPDFKitSourceOrderAndLineBreaks() throws {
        let document = try makeDocument(pages: [["Reference first line", "Reference second line"]])
        let page = try XCTUnwrap(document.page(at: 0))
        let sourceSelection = try wholePageSelection(on: page)

        let resolved = try XCTUnwrap(
            PDFSelectionResolver.selection(on: page, from: sourceSelection)
        )

        XCTAssertEqual(resolved.string, sourceSelection.string)
    }

    func testSelectionUsesTouchedWordWhenNativeSelectionReportsOnlyALaterPage() throws {
        let document = try makeDocument(pages: [
            ["First page"],
            ["Touched table word"],
            ["Incorrect last-page word"]
        ])
        let targetPage = try XCTUnwrap(document.page(at: 1))
        let lastPage = try XCTUnwrap(document.page(at: 2))
        let targetSelection = try wholePageSelection(on: targetPage)
        let targetLine = try XCTUnwrap(targetSelection.selectionsByLine().first)
        let touchPoint = CGPoint(
            x: targetLine.bounds(for: targetPage).midX,
            y: targetLine.bounds(for: targetPage).midY
        )
        let incorrectSelection = try wholePageSelection(on: lastPage)

        let resolved = try XCTUnwrap(
            PDFSelectionResolver.selection(
                on: targetPage,
                from: incorrectSelection,
                anchorPoint: touchPoint,
                currentPoint: touchPoint
            )
        )

        let resolvedText = try XCTUnwrap(resolved.string)
        XCTAssertTrue(resolved.pages.first === targetPage)
        XCTAssertTrue(targetSelection.string?.contains(resolvedText) == true)
        XCTAssertFalse(resolved.string?.contains("Incorrect") == true)
    }

    func testPageJumpAwayFromTouchAnchorIsBlockedWhileSelecting() {
        XCTAssertFalse(
            PDFSelectionInteractionPolicy.allowsPageChange(
                to: 99,
                anchorPageIndex: 1,
                shouldProtectSelection: true
            )
        )
    }

    func testNormalPageScrollIsAllowedWithoutCrossPageSelection() {
        XCTAssertTrue(
            PDFSelectionInteractionPolicy.allowsPageChange(
                to: 99,
                anchorPageIndex: 1,
                shouldProtectSelection: false
            )
        )
    }

    private func makeDocument(pages: [[String]]) throws -> PDFDocument {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = renderer.pdfData { context in
            for lines in pages {
                context.beginPage()
                for (index, line) in lines.enumerated() {
                    (line as NSString).draw(
                        at: CGPoint(x: 48, y: 72 + CGFloat(index) * 28),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 18)]
                    )
                }
            }
        }
        return try XCTUnwrap(PDFDocument(data: data))
    }

    private func wholePageSelection(on page: PDFPage) throws -> PDFSelection {
        try XCTUnwrap(page.selection(for: page.bounds(for: .mediaBox)))
    }
}
