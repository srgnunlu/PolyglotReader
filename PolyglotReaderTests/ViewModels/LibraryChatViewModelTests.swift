import XCTest
@testable import PolyglotReader

@MainActor
final class LibraryChatViewModelTests: XCTestCase {
    func testWhitespaceOnlyMessageIsIgnored() async {
        let sut = LibraryChatViewModel(documents: [])

        await sut.sendMessage("  \n\t  ")

        XCTAssertTrue(sut.messages.isEmpty)
        XCTAssertFalse(sut.isLoading)
    }

    func testCancelActiveStreamImmediatelyRestoresIdleState() {
        let sut = LibraryChatViewModel(documents: [])
        sut.isLoading = true

        sut.cancelActiveStream()

        XCTAssertFalse(sut.isLoading)
    }
}
