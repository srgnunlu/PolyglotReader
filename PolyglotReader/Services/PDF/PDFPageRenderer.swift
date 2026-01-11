import Foundation
import PDFKit
import UIKit

class PDFPageRenderer {
    // MARK: - Page Rendering

    func renderPageAsImage(page: PDFPage, scale: CGFloat = 2.0) -> UIImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let size = CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)

            page.draw(with: .mediaBox, to: context.cgContext)
        }
    }

    func renderPagesAsImages(document: PDFDocument, maxPages: Int = 20, scale: CGFloat = 1.5) -> [Data] {
        var images: [Data] = []
        let pageCount = min(document.pageCount, maxPages)

        for pageIndex in 0..<pageCount {
            guard let page = document.page(at: pageIndex),
                  let image = renderPageAsImage(page: page, scale: scale),
                  let jpegData = image.jpegData(compressionQuality: 0.7) else {
                continue
            }
            images.append(jpegData)
        }

        return images
    }

    // MARK: - Thumbnail Generation

    /// Thumbnail boyutu artırıldı - başlık kısmı daha net görünsün
    func generateThumbnail(for document: PDFDocument, size: CGSize = CGSize(width: 300, height: 400)) -> UIImage? {
        guard let firstPage = document.page(at: 0) else { return nil }
        return firstPage.thumbnail(of: size, for: .mediaBox)
    }

    func generateThumbnailData(for document: PDFDocument) -> Data? {
        guard let thumbnail = generateThumbnail(for: document) else { return nil }
        // Kalite artırıldı - daha net görüntü
        return thumbnail.jpegData(compressionQuality: 0.8)
    }
}
