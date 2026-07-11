import UIKit

// MARK: - Thumbnail Image Provider
/// Kart görünümleri her body hesaplamasında `UIImage(data:)` ile JPEG decode
/// ediyordu — scroll sırasında görünür her hücre için tekrar tekrar. Bu helper,
/// decode edilmiş (GPU'ya hazır) görüntüyü CacheService üzerinden paylaşır;
/// scroll'da yeniden decode maliyeti sıfırlanır.
enum ThumbnailImageProvider {
    /// Returns a display-ready decoded image for the file's thumbnail data.
    /// The cache key includes the data length so a regenerated (higher-res)
    /// thumbnail never serves a stale decoded image.
    static func image(for fileId: String, data: Data?) -> UIImage? {
        guard let data else { return nil }

        let key = "decoded_thumb_\(fileId)_\(data.count)"
        if let cached = CacheService.shared.getImage(forKey: key) {
            return cached
        }

        guard let image = UIImage(data: data) else { return nil }
        // Force-decode off the lazy path so scrolling never pays for it.
        let decoded = image.preparingForDisplay() ?? image
        CacheService.shared.setImage(decoded, forKey: key)
        return decoded
    }
}
