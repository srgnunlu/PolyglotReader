import Foundation
import PDFKit

class PDFMetadataService {
    func getPageCount(for document: PDFDocument) -> Int {
        document.pageCount
    }

    func getDocumentInfo(for document: PDFDocument) -> [AnyHashable: Any]? {
        document.documentAttributes
    }

    func getTitle(for document: PDFDocument) -> String? {
        document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
    }

    func getAuthor(for document: PDFDocument) -> String? {
        document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String
    }
}
