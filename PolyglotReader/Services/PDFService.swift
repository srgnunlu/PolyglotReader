import Foundation
import PDFKit
import UIKit

// MARK: - PDF Service
class PDFService {
    static let shared = PDFService()

    private let textExtractor = PDFTextExtractor()
    private let pageRenderer = PDFPageRenderer()
    private let metadataService = PDFMetadataService()
    private let maxPDFSizeBytes = 80 * 1024 * 1024
    // Annotation handler is mostly used by PDFKitView, but we can expose if needed

    private init() {}

    // MARK: - Load PDF

    func loadPDF(from url: URL) throws -> PDFDocument {
        if url.isFileURL,
           let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
           fileSize > maxPDFSizeBytes {
            throw AppError.pdf(reason: .tooLarge)
        }

        guard let document = PDFDocument(url: url) else {
            throw AppError.pdf(reason: .corrupted)
        }

        if document.isEncrypted {
            throw AppError.pdf(reason: .encrypted)
        }

        guard document.pageCount > 0 else {
            throw AppError.pdf(reason: .empty)
        }

        return document
    }

    func loadPDF(from data: Data) throws -> PDFDocument {
        guard !data.isEmpty else {
            throw AppError.pdf(reason: .empty)
        }

        let memoryThreshold = Int(ProcessInfo.processInfo.physicalMemory / 5)
        if data.count > memoryThreshold {
            throw AppError.pdf(reason: .memoryLimit)
        }

        if data.count > maxPDFSizeBytes {
            throw AppError.pdf(reason: .tooLarge)
        }

        guard let document = PDFDocument(data: data) else {
            throw AppError.pdf(reason: .corrupted)
        }

        if document.isEncrypted {
            throw AppError.pdf(reason: .encrypted)
        }

        guard document.pageCount > 0 else {
            throw AppError.pdf(reason: .empty)
        }

        return document
    }

    // MARK: - Text Extraction

    func extractText(from document: PDFDocument) -> String {
        textExtractor.extractText(from: document)
    }

    func extractText(from page: PDFPage) -> String {
        textExtractor.extractText(from: page)
    }

    // MARK: - Page Rendering

    func renderPageAsImage(page: PDFPage, scale: CGFloat = 2.0) throws -> UIImage {
        let pageRect = page.bounds(for: .mediaBox)
        let pixelCount = (pageRect.width * scale) * (pageRect.height * scale)
        if pixelCount > 50_000_000 {
            throw AppError.pdf(reason: .memoryLimit)
        }

        guard let image = pageRenderer.renderPageAsImage(page: page, scale: scale) else {
            throw AppError.pdf(reason: .renderFailed)
        }
        return image
    }

    func renderPagesAsImages(document: PDFDocument, maxPages: Int = 20, scale: CGFloat = 1.5) throws -> [Data] {
        let images = pageRenderer.renderPagesAsImages(document: document, maxPages: maxPages, scale: scale)
        guard !images.isEmpty else {
            throw AppError.pdf(reason: .renderFailed)
        }
        return images
    }

    // MARK: - Thumbnail Generation

    func generateThumbnail(
        for document: PDFDocument,
        size: CGSize = CGSize(width: 300, height: 400)
    ) throws -> UIImage {
        guard let thumbnail = pageRenderer.generateThumbnail(for: document, size: size) else {
            throw AppError.pdf(reason: .renderFailed)
        }
        return thumbnail
    }

    func generateThumbnailData(for document: PDFDocument) throws -> Data {
        guard let data = pageRenderer.generateThumbnailData(for: document) else {
            throw AppError.pdf(reason: .renderFailed)
        }
        return data
    }

    // MARK: - Search

    func search(query: String, in document: PDFDocument) throws -> [PDFSearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        if document.isEncrypted {
            throw AppError.pdf(reason: .encrypted)
        }

        return textExtractor.search(query: query, in: document)
    }

    // MARK: - Metadata

    func getPageCount(for document: PDFDocument) -> Int {
        metadataService.getPageCount(for: document)
    }

    func getMetadata(for document: PDFDocument) -> [AnyHashable: Any]? {
        metadataService.getDocumentInfo(for: document)
    }
}
