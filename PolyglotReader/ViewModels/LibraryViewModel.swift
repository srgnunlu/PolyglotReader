import Foundation
import Combine
import SwiftUI
import UniformTypeIdentifiers
import PDFKit

// MARK: - Library ViewModel
@MainActor
class LibraryViewModel: ObservableObject {
    @Published var files: [PDFDocumentMetadata] = []
    @Published var isLoading = false
    @Published var isUploading = false
    @Published var uploadProgress: Double = 0.0  // 0.0 to 1.0
    @Published var errorMessage: String?
    @Published var searchQuery = ""

    // Search debouncing
    private var searchDebounceTask: Task<Void, Never>?
    private let searchDebounceDelay: UInt64 = 300_000_000  // 300ms in nanoseconds

    // Görünüm/sıralama tercihleri oturumlar arası korunur
    @Published var viewMode: ViewMode = .grid {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "library.viewMode") }
    }
    @Published var sortBy: SortOption = .date {
        didSet { UserDefaults.standard.set(sortBy.rawValue, forKey: "library.sortBy") }
    }
    @Published var sortOrder: SortOrder = .descending {
        didSet { UserDefaults.standard.set(sortOrder == .ascending, forKey: "library.sortAscending") }
    }

    // Klasör Yönetimi
    @Published var folders: [Folder] = []
    @Published var currentFolder: Folder?
    @Published var folderPath: [Folder] = []
    /// Tüm klasörler (seviye filtresiz) — hiyerarşik taşıma/oluşturma hedef listesi.
    @Published var allFolders: [Folder] = []

    // Taşıma/silme sonrası geri alma (snackbar)
    @Published var undoToast: UndoToast?

    // Çöp kutusu (soft delete edilen dosyalar)
    @Published var trashedFiles: [PDFDocumentMetadata] = []

    // Paylaşım için indirme durumu
    @Published var isPreparingShare = false

    // Çoklu yükleme kuyruğu (1-bazlı konum; tekli yüklemede total = 1)
    @Published var uploadQueueIndex = 0
    @Published var uploadQueueTotal = 0

    /// Genel "Geri Al" snackbar'ı: mesaj + geri alma eylemi (taşıma → eski
    /// klasöre döndür, silme → çöpten geri yükle).
    struct UndoToast: Identifiable {
        let id = UUID()
        let message: String
        let action: @MainActor () async -> Void
    }

    // Etiket Yönetimi
    @Published var allTags: [Tag] = []
    @Published var selectedTags: Set<UUID> = []
    @Published var showTagFilter: Bool = false

    // Favori filtresi
    @Published var showFavoritesOnly = false

    // İçerik araması: arama kutusundaki sorgu PDF içeriklerinde de aranır
    // (BM25, search_files_by_content RPC). Eşleşen dosya ID'leri (lowercase).
    @Published var contentMatchIds: Set<String> = []
    private var contentSearchTask: Task<Void, Never>?

    // Çoklu seçim / toplu işlem
    @Published var isSelectionMode = false
    @Published var selectedFileIds: Set<String> = []

    let supabaseService = SupabaseService.shared
    let pdfService = PDFService.shared

    // Thumbnail loading tasks (cache moved to CacheService).
    // Kept as a plain var so deinit (nonisolated) can still cancel them.
    var thumbnailLoadingTasks: [String: Task<Void, Never>] = [:]
    // Eşzamanlılık sınırı: taze kurulumda 40 paralel indirme yerine sıralı kuyruk.
    var thumbnailWaitQueue: [PDFDocumentMetadata] = []
    var activeThumbnailTaskCount = 0
    let maxConcurrentThumbnailTasks = 3
    // Reactive mirror of in-flight thumbnail work — drives card skeletons,
    // including clearing them when generation fails.
    @Published var pendingThumbnailIds: Set<String> = []
    let summaryCacheKeyPrefix = "pdf_summary_cache_"

    enum ViewMode: String {
        case grid, list
    }

    enum SortOption: String, CaseIterable {
        case date = "Tarih"
        case name = "İsim"
        case size = "Boyut"
        case lastOpened = "Son Açılan"
    }

    enum SortOrder {
        case ascending, descending
    }

    // MARK: - Lifecycle

    init() {
        #if DEBUG
        MemoryDebugger.shared.logInit(self)
        #endif

        // Kaydedilmiş görünüm/sıralama tercihlerini geri yükle
        let defaults = UserDefaults.standard
        if let rawMode = defaults.string(forKey: "library.viewMode"),
           let savedMode = ViewMode(rawValue: rawMode) {
            viewMode = savedMode
        }
        if let rawSort = defaults.string(forKey: "library.sortBy"),
           let savedSort = SortOption(rawValue: rawSort) {
            sortBy = savedSort
        }
        if defaults.object(forKey: "library.sortAscending") != nil {
            sortOrder = defaults.bool(forKey: "library.sortAscending") ? .ascending : .descending
        }
    }

    deinit {
        #if DEBUG
        // Log deinit immediately without creating a Task that could hold references
        print("[MemoryDebugger] [DEINIT] LibraryViewModel")
        #endif
        thumbnailLoadingTasks.values.forEach { $0.cancel() }
        searchDebounceTask?.cancel()
        contentSearchTask?.cancel()
    }

    // MARK: - Computed Properties

    var filteredFiles: [PDFDocumentMetadata] {
        var result = files

        // Klasör filtresi (arama aktifken tüm kütüphanede ara — içerik
        // eşleşmesi başka klasördeki dosyayı da bulabilmeli)
        if searchQuery.isEmpty {
            result = result.filter { $0.folderId == currentFolder?.id }
        }

        // Favori filtresi
        if showFavoritesOnly {
            result = result.filter { $0.isFavorite }
        }

        // Etiket filtresi
        if !selectedTags.isEmpty {
            result = result.filter { file in
                let fileTagIds = Set(file.tags.map { $0.id })
                return !selectedTags.isDisjoint(with: fileTagIds)
            }
        }

        // Arama filtresi: isim + etiket + PDF içeriği (BM25 eşleşmeleri)
        if !searchQuery.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchQuery) ||
                $0.tags.contains { $0.name.localizedCaseInsensitiveContains(searchQuery) } ||
                contentMatchIds.contains($0.id.lowercased())
            }
        }

        // Sıralama
        result.sort { lhs, rhs in
            switch sortBy {
            case .date:
                return sortOrder == .descending
                    ? lhs.uploadedAt > rhs.uploadedAt
                    : lhs.uploadedAt < rhs.uploadedAt
            case .name:
                let nameComparison = lhs.name.localizedCompare(rhs.name) == .orderedAscending
                return sortOrder == .ascending ? nameComparison : !nameComparison
            case .size:
                return sortOrder == .descending ? lhs.size > rhs.size : lhs.size < rhs.size
            case .lastOpened:
                let lhsDate = lhs.lastOpenedAt ?? .distantPast
                let rhsDate = rhs.lastOpenedAt ?? .distantPast
                return sortOrder == .descending ? lhsDate > rhsDate : lhsDate < rhsDate
            }
        }

        return result
    }

    /// "Kaldığın yerden devam" şeridi: son açılan, henüz bitmemiş dosyalar.
    var continueReadingFiles: [PDFDocumentMetadata] {
        files
            .filter { $0.lastOpenedAt != nil && ($0.readingProgress ?? 0) < 0.999 }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Statistics

    /// Kütüphane istatistikleri — tamamen eldeki veriden hesaplanır, sorgu atmaz.
    struct LibraryStats {
        let totalFiles: Int
        let totalSize: Int
        let totalPages: Int
        let pagesRead: Int
        let completedCount: Int
        let inProgressCount: Int
        let favoriteCount: Int
        let openedThisWeek: Int
        let tagCount: Int
        let recentlyRead: [PDFDocumentMetadata]

        var formattedTotalSize: String {
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            formatter.countStyle = .file
            return formatter.string(fromByteCount: Int64(totalSize))
        }
    }

    var libraryStats: LibraryStats {
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        var completed = 0
        var inProgress = 0
        for file in files {
            guard let progress = file.readingProgress else { continue }
            if progress >= 0.999 {
                completed += 1
            } else if progress > 0 {
                inProgress += 1
            }
        }

        return LibraryStats(
            totalFiles: files.count,
            totalSize: files.reduce(0) { $0 + $1.size },
            totalPages: files.compactMap { $0.pageCount }.reduce(0, +),
            pagesRead: files.compactMap { $0.lastReadPage }.reduce(0, +),
            completedCount: completed,
            inProgressCount: inProgress,
            favoriteCount: files.filter { $0.isFavorite }.count,
            openedThisWeek: files.filter { ($0.lastOpenedAt ?? .distantPast) > weekAgo }.count,
            tagCount: allTags.count,
            recentlyRead: continueReadingFiles
        )
    }

    /// Mevcut klasördeki dosyaların etiketleri (klasör bazlı filtreleme)
    var visibleTags: [Tag] {
        // Mevcut klasördeki dosyaları bul
        let folderFiles = files.filter { $0.folderId == currentFolder?.id }

        // Bu dosyaların etiketlerini topla (benzersiz)
        var tagIds = Set<UUID>()
        var uniqueTags: [Tag] = []

        for file in folderFiles {
            for tag in file.tags where !tagIds.contains(tag.id) {
                tagIds.insert(tag.id)
                uniqueTags.append(tag)
            }
        }

        // Dosya sayısına göre sırala (allTags'taki file_count bilgisini kullan)
        return uniqueTags.sorted { tag1, tag2 in
            let count1 = allTags.first { $0.id == tag1.id }?.fileCount ?? 0
            let count2 = allTags.first { $0.id == tag2.id }?.fileCount ?? 0
            return count1 > count2
        }
    }

    // MARK: - Search Debouncing

    /// Update search with debouncing to prevent excessive filtering
    func updateSearchQuery(_ newQuery: String) {
        // Cancel previous debounce task
        searchDebounceTask?.cancel()

        // If empty, update immediately
        guard !newQuery.isEmpty else {
            searchQuery = ""
            contentSearchTask?.cancel()
            contentMatchIds = []
            return
        }

        // Debounce the search
        searchDebounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: searchDebounceDelay)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.searchQuery = newQuery
                    self.performContentSearch(newQuery)
                }
            } catch {
                // Task was cancelled, ignore
            }
        }
    }

    /// PDF içeriklerinde BM25 araması — isim/etiket filtresine ek eşleşmeler
    /// getirir. Kısa sorgularda gürültü üretmemesi için 3+ karakter ister.
    private func performContentSearch(_ query: String) {
        contentSearchTask?.cancel()

        guard query.count >= 3 else {
            contentMatchIds = []
            return
        }

        contentSearchTask = Task { [weak self] in
            guard let self else { return }
            let ids = (try? await self.supabaseService.searchFileIdsByContent(query: query)) ?? []
            guard !Task.isCancelled else { return }
            self.contentMatchIds = Set(ids)
        }
    }

    // MARK: - Favorites

    /// Favori durumunu iyimser günceller; sunucu hatasında geri alır.
    func toggleFavorite(_ file: PDFDocumentMetadata) async {
        guard let index = files.firstIndex(where: { $0.id == file.id }) else { return }
        let newValue = !files[index].isFavorite
        files[index].isFavorite = newValue

        do {
            try await supabaseService.updateFileFavorite(fileId: file.id, isFavorite: newValue)
        } catch {
            if let revertIndex = files.firstIndex(where: { $0.id == file.id }) {
                files[revertIndex].isFavorite = !newValue
            }
            let appError = ErrorHandlingService.mapToAppError(error)
            logError("LibraryViewModel", "Favori güncellenemedi", error: appError)
            ErrorHandlingService.shared.handle(
                appError,
                context: .silent(source: "LibraryViewModel", operation: "ToggleFavorite")
            )
        }
    }

    /// Get thumbnail from CacheService
    func getCachedThumbnail(forFileId fileId: String) -> Data? {
        CacheService.shared.getThumbnail(forFileId: fileId)
    }

    /// Cache thumbnail in CacheService
    func cacheThumbnail(_ data: Data, forFileId fileId: String) {
        CacheService.shared.setThumbnail(data, forFileId: fileId)
    }
}
