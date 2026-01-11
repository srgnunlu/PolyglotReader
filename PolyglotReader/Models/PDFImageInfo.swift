import Foundation
import UIKit

// MARK: - PDF Image Info
/// PDF'den seçilen görsel bölge bilgisi
struct PDFImageInfo {
    let image: UIImage           // Yakalanan görsel
    let rect: CGRect             // PDF sayfa koordinatları
    let screenRect: CGRect       // Ekran koordinatları (popup konumu için)
    let pageNumber: Int          // Sayfa numarası
    let capturedAt: Date         // Yakalama zamanı

    init(image: UIImage, rect: CGRect, screenRect: CGRect, pageNumber: Int) {
        self.image = image
        self.rect = rect
        self.screenRect = screenRect
        self.pageNumber = pageNumber
        self.capturedAt = Date()
    }

    /// Görseli JPEG olarak döndür (AI için)
    var jpegData: Data? {
        image.jpegData(compressionQuality: 0.85)
    }

    /// Görseli PNG olarak döndür (panoya kopyalama için)
    var pngData: Data? {
        image.pngData()
    }
}
