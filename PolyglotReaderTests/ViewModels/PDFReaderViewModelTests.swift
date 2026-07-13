import XCTest
import Combine
@testable import PolyglotReader

/// Unit tests for PDFReaderViewModel
@MainActor
final class PDFReaderViewModelTests: XCTestCase {
    
    var sut: PDFReaderViewModel!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        let metadata = TestDataFactory.makePDFMetadata()
        sut = PDFReaderViewModel(file: metadata)
        cancellables = []
    }
    
    override func tearDown() async throws {
        cancellables.removeAll()
        sut = nil
        try await super.tearDown()
    }
    
    // MARK: - Initial State Tests
    
    func testInitialDocumentIsNil() {
        // Then
        XCTAssertNil(sut.document)
    }
    
    func testInitialPageIsOne() {
        // Then
        XCTAssertEqual(sut.currentPage, 1)
    }
    
    func testInitialTotalPagesIsZero() {
        // Then
        XCTAssertEqual(sut.totalPages, 0)
    }
    
    func testInitialScaleIsOne() {
        // Then
        XCTAssertEqual(sut.scale, 1.0)
    }
    
    func testInitialLoadingIsFalse() {
        // Then
        XCTAssertFalse(sut.isLoading)
    }
    
    func testInitialChatReadyIsFalse() {
        // Then
        XCTAssertFalse(sut.isChatReady)
    }
    
    func testInitialAnnotationsIsEmpty() {
        // Then
        XCTAssertTrue(sut.annotations.isEmpty)
    }

    func testReaderDismissGestureIsDisabledWhileAnySelectionPopupIsVisible() {
        XCTAssertTrue(sut.allowsEdgeSwipeDismiss)

        sut.showQuickTranslation = true
        XCTAssertFalse(sut.allowsEdgeSwipeDismiss)

        sut.showQuickTranslation = false
        sut.showImagePopup = true
        XCTAssertFalse(sut.allowsEdgeSwipeDismiss)

        sut.showImagePopup = false
        sut.showTranslationPopup = true
        XCTAssertFalse(sut.allowsEdgeSwipeDismiss)
    }
    
    // MARK: - Page Navigation Tests
    
    func testGoToPageSetsCurrentPage() {
        // Given
        sut.totalPages = 10
        
        // When
        sut.goToPage(5)
        
        // Then
        XCTAssertEqual(sut.currentPage, 5)
    }
    
    func testGoToPageIgnoresOutOfBounds() {
        // Given
        sut.totalPages = 10
        sut.currentPage = 3  // Set initial page
        
        // When - Try to go beyond bounds
        sut.goToPage(15)
        
        // Then - Should stay at current page (out of bounds is ignored)
        XCTAssertEqual(sut.currentPage, 3)
    }
    
    func testGoToPageIgnoresZeroOrNegative() {
        // Given
        sut.totalPages = 10
        sut.currentPage = 5
        
        // When - Try to go below 1
        sut.goToPage(0)
        
        // Then - Should stay at current page (invalid is ignored)
        XCTAssertEqual(sut.currentPage, 5)
    }
    
    func testNextPageIncrementsCurrentPage() {
        // Given
        sut.totalPages = 10
        sut.currentPage = 5
        
        // When
        sut.nextPage()
        
        // Then
        XCTAssertEqual(sut.currentPage, 6)
    }
    
    func testNextPageDoesNotExceedTotal() {
        // Given
        sut.totalPages = 10
        sut.currentPage = 10
        
        // When
        sut.nextPage()
        
        // Then
        XCTAssertEqual(sut.currentPage, 10)
    }
    
    func testPreviousPageDecrementsCurrentPage() {
        // Given
        sut.totalPages = 10
        sut.currentPage = 5
        
        // When
        sut.previousPage()
        
        // Then
        XCTAssertEqual(sut.currentPage, 4)
    }
    
    func testPreviousPageDoesNotGoBelowOne() {
        // Given
        sut.totalPages = 10
        sut.currentPage = 1
        
        // When
        sut.previousPage()
        
        // Then
        XCTAssertEqual(sut.currentPage, 1)
    }

    // MARK: - Reading Progress Tests

    func testRestoreReadingProgressAppliesSavedPositionBeforeRendering() async {
        // Given
        let progressService = ReadingProgressServiceSpy()
        progressService.progressToReturn = ReadingProgress(
            id: UUID(),
            userId: UUID().uuidString,
            fileId: sut.fileMetadata.id,
            page: 7,
            offsetX: 18,
            offsetY: 240,
            zoomScale: 1.4,
            updatedAt: Date()
        )
        sut = PDFReaderViewModel(
            file: sut.fileMetadata,
            readingProgressService: progressService
        )

        // When
        await sut.restoreReadingProgress(totalPages: 12)

        // Then
        XCTAssertEqual(sut.currentPage, 7)
        XCTAssertEqual(sut.initialScrollPosition, CGPoint(x: 18, y: 240))
        XCTAssertEqual(sut.scale, 1.4, accuracy: 0.001)
    }

    func testRestoreReadingProgressClampsStalePageToDocumentBounds() async {
        // Given
        let progressService = ReadingProgressServiceSpy()
        progressService.progressToReturn = ReadingProgress(
            id: UUID(),
            userId: UUID().uuidString,
            fileId: sut.fileMetadata.id,
            page: 99,
            offsetX: 0,
            offsetY: 0,
            zoomScale: 1,
            updatedAt: Date()
        )
        sut = PDFReaderViewModel(
            file: sut.fileMetadata,
            readingProgressService: progressService
        )

        // When
        await sut.restoreReadingProgress(totalPages: 10)

        // Then
        XCTAssertEqual(sut.currentPage, 10)
    }

    func testRestoreReadingProgressKeepsDefaultsWhenLoadingFails() async {
        // Given
        let progressService = ReadingProgressServiceSpy()
        progressService.getError = ReadingProgressTestError.unavailable
        sut = PDFReaderViewModel(
            file: sut.fileMetadata,
            readingProgressService: progressService
        )

        // When
        await sut.restoreReadingProgress(totalPages: 10)

        // Then
        XCTAssertEqual(sut.currentPage, 1)
        XCTAssertNil(sut.initialScrollPosition)
        XCTAssertEqual(sut.scale, 1)
    }

    func testFlushReadingProgressImmediatelyPersistsLatestPendingPosition() async {
        // Given
        let progressService = ReadingProgressServiceSpy()
        sut = PDFReaderViewModel(
            file: sut.fileMetadata,
            readingProgressService: progressService
        )
        sut.updateReadingProgress(page: 3, point: CGPoint(x: 4, y: 80), scale: 1.1)
        sut.updateReadingProgress(page: 8, point: CGPoint(x: 12, y: 320), scale: 1.6)

        // When
        await sut.flushReadingProgress()

        // Then
        XCTAssertEqual(progressService.savedPositions.count, 1)
        XCTAssertEqual(progressService.savedPositions.first?.page, 8)
        XCTAssertEqual(progressService.savedPositions.first?.point, CGPoint(x: 12, y: 320))
        XCTAssertEqual(progressService.savedPositions.first?.scale ?? 0, 1.6, accuracy: 0.001)
    }

    func testFlushReadingProgressDoesNotSaveSamePendingPositionTwice() async {
        // Given
        let progressService = ReadingProgressServiceSpy()
        sut = PDFReaderViewModel(
            file: sut.fileMetadata,
            readingProgressService: progressService
        )
        sut.updateReadingProgress(page: 5, point: .zero, scale: 1.2)

        // When
        await sut.flushReadingProgress()
        await sut.flushReadingProgress()

        // Then
        XCTAssertEqual(progressService.savedPositions.count, 1)
    }

    func testFlushReadingProgressRetriesPendingPositionAfterSaveFailure() async {
        // Given
        let progressService = ReadingProgressServiceSpy()
        progressService.remainingSaveFailures = 1
        sut = PDFReaderViewModel(
            file: sut.fileMetadata,
            readingProgressService: progressService
        )
        sut.updateReadingProgress(page: 4, point: CGPoint(x: 2, y: 90), scale: 1.3)

        // When
        await sut.flushReadingProgress()
        await sut.flushReadingProgress()

        // Then
        XCTAssertEqual(progressService.saveAttempts, 2)
        XCTAssertEqual(progressService.savedPositions.first?.page, 4)
    }

    func testUpdateReadingProgressIgnoresInvalidScale() async {
        // Given
        let progressService = ReadingProgressServiceSpy()
        sut = PDFReaderViewModel(
            file: sut.fileMetadata,
            readingProgressService: progressService
        )

        // When
        sut.updateReadingProgress(page: 2, point: .zero, scale: 0)
        await sut.flushReadingProgress()

        // Then
        XCTAssertEqual(progressService.saveAttempts, 0)
    }
    
    // MARK: - Annotation Tests
    
    func testAddAnnotationIncreasesCount() {
        // Given
        let annotation = TestDataFactory.makeAnnotation(fileId: sut.fileMetadata.id)
        let initialCount = sut.annotations.count
        
        // When
        sut.annotations.append(annotation)
        
        // Then
        XCTAssertEqual(sut.annotations.count, initialCount + 1)
    }
    
    func testRemoveAnnotationDecreasesCount() {
        // Given
        let annotation = TestDataFactory.makeAnnotation(fileId: sut.fileMetadata.id)
        sut.annotations.append(annotation)
        let countAfterAdd = sut.annotations.count
        
        // When
        sut.annotations.removeAll { $0.id == annotation.id }
        
        // Then
        XCTAssertEqual(sut.annotations.count, countAfterAdd - 1)
    }
    
    // MARK: - Search Tests
    
    func testSearchQueryStartsEmpty() {
        // Then
        XCTAssertTrue(sut.searchQuery.isEmpty)
    }
    
    func testSearchResultsStartEmpty() {
        // Then
        XCTAssertTrue(sut.searchResults.isEmpty)
    }
    
    // MARK: - Offline State Tests
    
    func testOfflineStateIsPublished() {
        // Given
        var offlineStates: [Bool] = []
        
        sut.$isOffline
            .sink { isOffline in
                offlineStates.append(isOffline)
            }
            .store(in: &cancellables)
        
        // Then - Should have received initial state
        XCTAssertFalse(offlineStates.isEmpty)
    }
    
    // MARK: - Current Page Text Tests
    
    func testCurrentPageTextIsNilWithoutDocument() {
        // Given - No document loaded
        
        // Then
        XCTAssertNil(sut.currentPageText)
    }
    
    // MARK: - Memory Leak Tests
    
    func testPDFReaderViewModelDoesNotLeakMemory() async {
        // Given
        var viewModel: PDFReaderViewModel? = PDFReaderViewModel(
            file: TestDataFactory.makePDFMetadata()
        )
        weak var weakViewModel = viewModel
        
        // When
        viewModel = nil
        
        // Allow time for cleanup
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Then
        XCTAssertNil(weakViewModel, "PDFReaderViewModel should be deallocated")
    }
    
    // MARK: - File Metadata Tests
    
    func testFileMetadataIsPreserved() {
        // Given
        let metadata = TestDataFactory.makePDFMetadata(name: "Custom.pdf")
        let viewModel = PDFReaderViewModel(file: metadata)
        
        // Then
        XCTAssertEqual(viewModel.fileMetadata.name, "Custom.pdf")
    }
}

@MainActor
private final class ReadingProgressServiceSpy: ReadingProgressServicing {
    struct SavedPosition {
        let fileId: String
        let page: Int
        let point: CGPoint
        let scale: Double
    }

    var progressToReturn: ReadingProgress?
    var getError: Error?
    var remainingSaveFailures = 0
    private(set) var saveAttempts = 0
    private(set) var savedPositions: [SavedPosition] = []

    func getReadingProgress(fileId: String) async throws -> ReadingProgress? {
        if let getError {
            throw getError
        }
        return progressToReturn
    }

    func saveReadingProgress(
        fileId: String,
        page: Int,
        offsetX: Double,
        offsetY: Double,
        scale: Double
    ) async throws {
        saveAttempts += 1
        if remainingSaveFailures > 0 {
            remainingSaveFailures -= 1
            throw ReadingProgressTestError.unavailable
        }

        savedPositions.append(
            SavedPosition(
                fileId: fileId,
                page: page,
                point: CGPoint(x: offsetX, y: offsetY),
                scale: scale
            )
        )
    }
}

private enum ReadingProgressTestError: Error {
    case unavailable
}
