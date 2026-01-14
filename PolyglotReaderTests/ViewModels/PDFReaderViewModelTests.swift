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
