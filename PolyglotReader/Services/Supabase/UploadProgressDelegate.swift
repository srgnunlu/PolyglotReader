import Foundation

// MARK: - Upload Progress Delegate

/// URLSession delegate for tracking upload progress
final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let totalBytes: Int64
    private let progressHandler: ((Double) -> Void)?
    private var uploadedBytes: Int64 = 0
    private var lastProgress: Double = 0
    
    init(totalBytes: Int64, progressHandler: ((Double) -> Void)?) {
        self.totalBytes = totalBytes
        self.progressHandler = progressHandler
        super.init()
    }
    
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        uploadedBytes = totalBytesSent
        let expectedBytes = totalBytesExpectedToSend > 0 ? totalBytesExpectedToSend : totalBytes
        guard expectedBytes > 0 else { return }
        let rawProgress = Double(totalBytesSent) / Double(expectedBytes)
        let clampedProgress = min(max(rawProgress, 0), 1)
        let progress = max(lastProgress, clampedProgress)
        lastProgress = progress
        
        // Call progress handler on main thread
        DispatchQueue.main.async { [weak self] in
            self?.progressHandler?(progress)
        }
        
        // Log progress every 10%
        let percentage = Int(progress * 100)
        if percentage % 10 == 0 {
            logDebug(
                "SupabaseStorageService",
                "Yükleme ilerlemesi",
                details: "\(percentage)% - \(ByteCountFormatter.string(fromByteCount: totalBytesSent, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: expectedBytes, countStyle: .file))"
            )
        }
    }
}
