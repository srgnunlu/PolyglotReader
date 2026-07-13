import XCTest
@testable import PolyglotReader

/// Unit tests for the pure reading-order assembly used by scanned-page OCR.
final class PDFOCRServiceTests: XCTestCase {

    // MARK: - Hyphen Merge

    func testMergeJoinsHyphenatedLowercaseBreak() {
        let result = OCRTextAssembler.mergeLines(["prog-", "ram çalışıyor"])
        XCTAssertEqual(result, "program çalışıyor")
    }

    func testMergeKeepsHyphenWhenNextLineStartsUppercase() {
        // "COVID-" + "19" style: not a word wrap, keep as separate lines.
        let result = OCRTextAssembler.mergeLines(["Kuzey-", "Güney ekseni"])
        XCTAssertEqual(result, "Kuzey-\nGüney ekseni")
    }

    func testMergeIgnoresDashThatIsNotWordHyphen() {
        // A standalone dash (e.g. bullet) must not swallow the next line.
        let result = OCRTextAssembler.mergeLines(["-", "madde"])
        XCTAssertEqual(result, "-\nmadde")
    }

    func testMergeSkipsEmptyLines() {
        let result = OCRTextAssembler.mergeLines(["birinci", "   ", "ikinci"])
        XCTAssertEqual(result, "birinci\nikinci")
    }

    // MARK: - Column Ordering

    func testAssembleOrdersTwoColumnsLeftToRightTopToBottom() {
        // Left column at x≈0.25, right column at x≈0.75. Provided out of order.
        let lines = [
            OCRTextLine(text: "sag-ust", midX: 0.75, top: 0.90),
            OCRTextLine(text: "sol-ust", midX: 0.25, top: 0.90),
            OCRTextLine(text: "sol-alt", midX: 0.25, top: 0.40),
            OCRTextLine(text: "sag-alt", midX: 0.75, top: 0.40)
        ]
        let result = OCRTextAssembler.assemble(lines)
        XCTAssertEqual(result, "sol-ust\nsol-alt\nsag-ust\nsag-alt")
    }

    func testAssembleSingleColumnStaysTopToBottom() {
        let lines = [
            OCRTextLine(text: "ucuncu", midX: 0.5, top: 0.2),
            OCRTextLine(text: "birinci", midX: 0.5, top: 0.9),
            OCRTextLine(text: "ikinci", midX: 0.5, top: 0.55)
        ]
        let result = OCRTextAssembler.assemble(lines)
        XCTAssertEqual(result, "birinci\nikinci\nucuncu")
    }

    func testClusterGroupsNearbyXIntoOneColumn() {
        // Ragged left edges within the same column (0.20 vs 0.28) stay together.
        let lines = [
            OCRTextLine(text: "a", midX: 0.20, top: 0.9),
            OCRTextLine(text: "b", midX: 0.28, top: 0.8)
        ]
        let columns = OCRTextAssembler.clusterIntoColumns(lines)
        XCTAssertEqual(columns.count, 1)
    }

    func testClusterSplitsDistinctColumns() {
        let lines = [
            OCRTextLine(text: "a", midX: 0.20, top: 0.9),
            OCRTextLine(text: "b", midX: 0.80, top: 0.9)
        ]
        let columns = OCRTextAssembler.clusterIntoColumns(lines)
        XCTAssertEqual(columns.count, 2)
    }

    func testAssembleEmptyReturnsEmpty() {
        XCTAssertEqual(OCRTextAssembler.assemble([]), "")
    }
}
