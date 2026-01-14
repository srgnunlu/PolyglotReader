import Foundation
import PDFKit
import UIKit
@testable import PolyglotReader

/// Mock implementation of PDFService for testing
final class MockPDFService {
    
    // MARK: - Mock Configuration
    
    var mockDocument: PDFDocument?
    var mockText: String = "Sample PDF text content for testing purposes."
    var mockThumbnail: UIImage?
    var mockError: AppError?
    
    // MARK: - Call Tracking
    
    var callCount: [String: Int] = [:]
    
    // MARK: - Load PDF Methods
    
    func loadPDF(from url: URL) throws -> PDFDocument {
        recordCall("loadPDFFromURL")
        
        if let error = mockError {
            throw error
        }
        
        if let doc = mockDocument {
            return doc
        }
        
        // Try to create a document from the URL
        if let doc = PDFDocument(url: url) {
            return doc
        }
        
        throw AppError.pdf(reason: .corrupted)
    }
    
    func loadPDF(from data: Data) throws -> PDFDocument {
        recordCall("loadPDFFromData")
        
        if let error = mockError {
            throw error
        }
        
        if let doc = mockDocument {
            return doc
        }
        
        guard !data.isEmpty else {
            throw AppError.pdf(reason: .empty)
        }
        
        // Try to create a document from data
        if let doc = PDFDocument(data: data) {
            return doc
        }
        
        throw AppError.pdf(reason: .corrupted)
    }
    
    // MARK: - Text Extraction
    
    func extractText(from document: PDFDocument) -> String {
        recordCall("extractTextFromDocument")
        return mockText
    }
    
    func extractText(from page: PDFPage) -> String {
        recordCall("extractTextFromPage")
        return page.string ?? mockText
    }
    
    // MARK: - Page Rendering
    
    func renderPageAsImage(page: PDFPage, scale: CGFloat = 2.0) throws -> UIImage {
        recordCall("renderPageAsImage")
        
        if let error = mockError {
            throw error
        }
        
        // Create a simple placeholder image
        let size = CGSize(width: 100, height: 150)
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        
        UIColor.lightGray.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        
        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            throw AppError.pdf(reason: .renderFailed)
        }
        
        return image
    }
    
    func renderPagesAsImages(document: PDFDocument, maxPages: Int = 20, scale: CGFloat = 1.5) throws -> [Data] {
        recordCall("renderPagesAsImages")
        
        if let error = mockError {
            throw error
        }
        
        var images: [Data] = []
        let pageCount = min(document.pageCount, maxPages)
        
        for i in 0..<pageCount {
            guard let page = document.page(at: i),
                  let imageData = try? renderPageAsImage(page: page, scale: scale).pngData() else {
                continue
            }
            images.append(imageData)
        }
        
        return images
    }
    
    // MARK: - Thumbnail Generation
    
    func generateThumbnail(for document: PDFDocument, size: CGSize = CGSize(width: 300, height: 400)) throws -> UIImage {
        recordCall("generateThumbnail")
        
        if let error = mockError {
            throw error
        }
        
        if let thumbnail = mockThumbnail {
            return thumbnail
        }
        
        // Generate a placeholder thumbnail
        UIGraphicsBeginImageContextWithOptions(size, false, 2.0)
        defer { UIGraphicsEndImageContext() }
        
        UIColor.white.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        
        UIColor.gray.setStroke()
        let path = UIBezierPath(rect: CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 10))
        path.stroke()
        
        guard let image = UIGraphicsGetImageFromCurrentImageContext() else {
            throw AppError.pdf(reason: .renderFailed)
        }
        
        return image
    }
    
    func generateThumbnailData(for document: PDFDocument) throws -> Data {
        recordCall("generateThumbnailData")
        
        let thumbnail = try generateThumbnail(for: document)
        guard let data = thumbnail.jpegData(compressionQuality: 0.7) else {
            throw AppError.pdf(reason: .renderFailed)
        }
        return data
    }
    
    // MARK: - Search
    
    func search(query: String, in document: PDFDocument) throws -> [PDFSearchResult] {
        recordCall("search")
        
        if let error = mockError {
            throw error
        }
        
        guard !query.isEmpty else {
            return []
        }
        
        // Return mock search results
        return [
            PDFSearchResult(pageNumber: 1, text: "Found: \(query)")
        ]
    }
    
    // MARK: - Metadata
    
    func getPageCount(for document: PDFDocument) -> Int {
        recordCall("getPageCount")
        return document.pageCount
    }
    
    func getMetadata(for document: PDFDocument) -> [AnyHashable: Any]? {
        recordCall("getMetadata")
        return document.documentAttributes
    }
    
    // MARK: - Helper Methods
    
    func reset() {
        mockDocument = nil
        mockText = "Sample PDF text content for testing purposes."
        mockThumbnail = nil
        mockError = nil
        callCount.removeAll()
    }
    
    private func recordCall(_ method: String) {
        callCount[method, default: 0] += 1
    }
}

// MARK: - Mock Search Result (minimal implementation)

struct PDFSearchResult {
    let pageNumber: Int
    let text: String
}
