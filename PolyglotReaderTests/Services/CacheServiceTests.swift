import XCTest
@testable import PolyglotReader

/// Unit tests for CacheService
final class CacheServiceTests: XCTestCase {
    
    var sut: CacheService!
    
    override func setUp() {
        super.setUp()
        sut = CacheService.shared
        sut.clearAllCaches()
    }
    
    override func tearDown() {
        sut.clearAllCaches()
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Thumbnail Cache Tests
    
    func testSetAndGetThumbnail() {
        // Given
        let fileId = "test_file_123"
        let thumbnailData = "Test thumbnail data".data(using: .utf8)!
        
        // When
        sut.setThumbnail(thumbnailData, forFileId: fileId)
        let retrieved = sut.getThumbnail(forFileId: fileId)
        
        // Then
        XCTAssertEqual(retrieved, thumbnailData)
    }
    
    func testGetNonExistentThumbnailReturnsNil() {
        // Given
        let fileId = "non_existent_file"
        
        // When
        let retrieved = sut.getThumbnail(forFileId: fileId)
        
        // Then
        XCTAssertNil(retrieved)
    }
    
    func testRemoveThumbnail() {
        // Given
        let fileId = "file_to_remove"
        let thumbnailData = "Test data".data(using: .utf8)!
        sut.setThumbnail(thumbnailData, forFileId: fileId)
        
        // When
        sut.removeThumbnail(forFileId: fileId)
        
        // Then
        XCTAssertNil(sut.getThumbnail(forFileId: fileId))
    }
    
    // MARK: - Image Cache Tests
    
    func testSetAndGetImage() {
        // Given
        let key = "image_key"
        let image = createTestImage()
        
        // When
        sut.setImage(image, forKey: key)
        let retrieved = sut.getImage(forKey: key)
        
        // Then
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.size, image.size)
    }
    
    func testGetNonExistentImageReturnsNil() {
        // Given
        let key = "non_existent_image"
        
        // When
        let retrieved = sut.getImage(forKey: key)
        
        // Then
        XCTAssertNil(retrieved)
    }
    
    func testRemoveImage() {
        // Given
        let key = "image_to_remove"
        let image = createTestImage()
        sut.setImage(image, forKey: key)
        
        // When
        sut.removeImage(forKey: key)
        
        // Then
        XCTAssertNil(sut.getImage(forKey: key))
    }
    
    // MARK: - PDF Page Cache Tests
    
    func testSetAndGetPDFPage() {
        // Given
        let fileId = "pdf_file_123"
        let pageNumber = 5
        let scale: CGFloat = 1.5
        let pageImage = createTestImage()
        
        // When
        sut.setPDFPage(pageImage, fileId: fileId, pageNumber: pageNumber, scale: scale)
        let retrieved = sut.getPDFPage(fileId: fileId, pageNumber: pageNumber, scale: scale)
        
        // Then
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.size, pageImage.size)
    }
    
    func testGetPDFPageWithDifferentScaleReturnsNil() {
        // Given
        let fileId = "pdf_file_123"
        let pageNumber = 5
        let pageImage = createTestImage()
        sut.setPDFPage(pageImage, fileId: fileId, pageNumber: pageNumber, scale: 1.0)
        
        // When - Request with different scale
        let retrieved = sut.getPDFPage(fileId: fileId, pageNumber: pageNumber, scale: 2.0)
        
        // Then
        XCTAssertNil(retrieved)
    }
    
    // MARK: - Clear Cache Tests
    
    func testClearAllCaches() {
        // Given
        let fileId = "test_file"
        let imageKey = "test_image"
        sut.setThumbnail("data".data(using: .utf8)!, forFileId: fileId)
        sut.setImage(createTestImage(), forKey: imageKey)
        sut.setPDFPage(createTestImage(), fileId: fileId, pageNumber: 1, scale: 1.0)
        
        // When
        sut.clearAllCaches()
        
        // Then
        XCTAssertNil(sut.getThumbnail(forFileId: fileId))
        XCTAssertNil(sut.getImage(forKey: imageKey))
        XCTAssertNil(sut.getPDFPage(fileId: fileId, pageNumber: 1, scale: 1.0))
    }
    
    func testClearPDFPageCache() {
        // Given
        let fileId = "test_file"
        let imageKey = "test_image"
        sut.setThumbnail("data".data(using: .utf8)!, forFileId: fileId)
        sut.setImage(createTestImage(), forKey: imageKey)
        sut.setPDFPage(createTestImage(), fileId: fileId, pageNumber: 1, scale: 1.0)
        
        // When
        sut.clearPDFPageCache()
        
        // Then - Only PDF pages should be cleared
        XCTAssertNotNil(sut.getThumbnail(forFileId: fileId))
        XCTAssertNotNil(sut.getImage(forKey: imageKey))
        XCTAssertNil(sut.getPDFPage(fileId: fileId, pageNumber: 1, scale: 1.0))
    }
    
    // MARK: - Stats Tests
    
    func testGetStatsReturnsValidStats() {
        // When
        let stats = sut.getStats()
        
        // Then
        XCTAssertGreaterThan(stats.thumbnailCountLimit, 0)
        XCTAssertGreaterThan(stats.thumbnailCostLimit, 0)
        XCTAssertGreaterThan(stats.pdfPageCountLimit, 0)
        XCTAssertGreaterThan(stats.imageCountLimit, 0)
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentAccessDoesntCrash() {
        // Given
        let expectation = expectation(description: "Concurrent access completes")
        let iterations = 50
        let group = DispatchGroup()
        
        // When - Access cache from multiple threads
        for i in 0..<iterations {
            group.enter()
            DispatchQueue.global().async {
                let image = self.createTestImage()
                self.sut.setImage(image, forKey: "concurrent_\(i)")
                _ = self.sut.getImage(forKey: "concurrent_\(i)")
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            expectation.fulfill()
        }
        
        // Then
        waitForExpectations(timeout: 5.0)
        // Test passes if no crash occurred
    }
    
    // MARK: - Helper Methods
    
    private func createTestImage() -> UIImage {
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        UIColor.blue.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
    }
}
