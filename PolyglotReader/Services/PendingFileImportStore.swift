import Foundation
import Combine

/// "Open in / Corio Docs'a kopyala" ile dışarıdan gelen PDF'leri, kütüphane
/// görünümü tüketene kadar bekletir. App `onOpenURL`'de kuyruğa ekler;
/// LibraryView oturum açıkken kuyruğu boşaltıp yüklemeyi başlatır — böylece
/// login öncesi gelen dosyalar kaybolmaz.
@MainActor
final class PendingFileImportStore: ObservableObject {
    static let shared = PendingFileImportStore()

    @Published private(set) var pendingURLs: [URL] = []

    private init() {}

    func enqueue(_ url: URL) {
        pendingURLs.append(url)
        logInfo("PendingFileImportStore", "Dışarıdan PDF alındı", details: url.lastPathComponent)
    }

    /// Kuyruğu boşaltır ve bekleyen URL'leri döndürür.
    func drain() -> [URL] {
        let urls = pendingURLs
        pendingURLs = []
        return urls
    }
}
