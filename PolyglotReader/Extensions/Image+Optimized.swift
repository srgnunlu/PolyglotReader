import UIKit
import ImageIO

// MARK: - Optimized Image Loading
/// Extension for memory-efficient image loading and thumbnail generation.
extension UIImage {

    // MARK: - Downsampling

    /// Downsample an image at a URL to the target size.
    /// Uses ImageIO for memory-efficient loading without decoding full image.
    /// - Parameters:
    ///   - url: File URL of the image
    ///   - targetSize: Target size for the downsampled image
    /// - Returns: Downsampled UIImage or nil if loading fails
    static func downsample(at url: URL, to targetSize: CGSize) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, imageSourceOptions) else {
            return nil
        }
        return downsample(from: imageSource, to: targetSize)
    }

    /// Downsample image data to the target size.
    /// - Parameters:
    ///   - data: Image data
    ///   - targetSize: Target size for the downsampled image
    /// - Returns: Downsampled UIImage or nil if loading fails
    static func downsample(from data: Data, to targetSize: CGSize) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            return nil
        }
        return downsample(from: imageSource, to: targetSize)
    }

    /// Internal method to downsample from an image source
    private static func downsample(from imageSource: CGImageSource, to targetSize: CGSize) -> UIImage? {
        let maxDimensionInPixels = max(targetSize.width, targetSize.height) * UIScreen.main.scale

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels
        ]

        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            downsampleOptions as CFDictionary
        ) else {
            return nil
        }

        return UIImage(cgImage: downsampledImage)
    }

    // MARK: - Background Thumbnail Generation

    /// Generate thumbnail on background thread.
    /// - Parameters:
    ///   - data: Image data
    ///   - size: Target thumbnail size
    ///   - completion: Completion handler with the generated thumbnail
    static func generateThumbnail(
        from data: Data,
        size: CGSize,
        completion: @escaping (UIImage?) -> Void
    ) {
        Task.detached(priority: .utility) {
            let thumbnail = downsample(from: data, to: size)
            await MainActor.run {
                completion(thumbnail)
            }
        }
    }

    /// Async version of thumbnail generation
    static func generateThumbnail(from data: Data, size: CGSize) async -> UIImage? {
        await Task.detached(priority: .utility) {
            downsample(from: data, to: size)
        }.value
    }

    // MARK: - Memory-Efficient Resize

    /// Resize image to target size with optimal memory usage.
    /// - Parameter targetSize: Target size
    /// - Returns: Resized image
    func resized(to targetSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // Use logical pixels

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    /// Resize image maintaining aspect ratio to fit within max dimension.
    /// - Parameter maxDimension: Maximum width or height
    /// - Returns: Resized image fitting within the dimension
    func resizedToFit(maxDimension: CGFloat) -> UIImage {
        let aspectRatio = size.width / size.height

        let targetSize: CGSize
        if size.width > size.height {
            targetSize = CGSize(
                width: min(maxDimension, size.width),
                height: min(maxDimension, size.width) / aspectRatio
            )
        } else {
            targetSize = CGSize(
                width: min(maxDimension, size.height) * aspectRatio,
                height: min(maxDimension, size.height)
            )
        }

        return resized(to: targetSize)
    }

    // MARK: - Image Size Estimation

    /// Estimate memory footprint of the image in bytes
    var estimatedMemoryFootprint: Int {
        guard let cgImage = self.cgImage else {
            return Int(size.width * size.height * 4 * scale)
        }
        return cgImage.bytesPerRow * cgImage.height
    }

    /// Check if image is too large for efficient rendering
    var isLargeImage: Bool {
        estimatedMemoryFootprint > 10 * 1024 * 1024 // 10MB threshold
    }
}

// MARK: - Optimized AsyncImage Loading

/// Wrapper for loading images with caching support
struct OptimizedImageLoader {

    /// Load and cache image from URL
    static func loadImage(
        from url: URL,
        targetSize: CGSize,
        cacheKey: String
    ) async -> UIImage? {
        // Check cache first
        if let cached = CacheService.shared.getImage(forKey: cacheKey) {
            return cached
        }

        // Load and downsample
        let image = UIImage.downsample(at: url, to: targetSize)

        // Cache the result
        if let image = image {
            CacheService.shared.setImage(image, forKey: cacheKey)
        }

        return image
    }

    /// Load and cache image from data
    static func loadImage(
        from data: Data,
        targetSize: CGSize,
        cacheKey: String
    ) async -> UIImage? {
        // Check cache first
        if let cached = CacheService.shared.getImage(forKey: cacheKey) {
            return cached
        }

        // Load and downsample on background thread
        let image = await Task.detached(priority: .utility) {
            UIImage.downsample(from: data, to: targetSize)
        }.value

        // Cache the result
        if let image = image {
            CacheService.shared.setImage(image, forKey: cacheKey)
        }

        return image
    }
}
