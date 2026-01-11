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
    @Published var viewMode: ViewMode = .grid
    @Published var sortBy: SortOption = .date
    @Published var sortOrder: SortOrder = .descending

    // Klasör Yönetimi
    @Published var folders: [Folder] = []
    @Published var currentFolder: Folder?
    @Published var folderPath: [Folder] = []

    // Etiket Yönetimi
    @Published var allTags: [Tag] = []
    @Published var selectedTags: Set<UUID> = []
    @Published var showTagFilter: Bool = false

    let supabaseService = SupabaseService.shared
    let pdfService = PDFService.shared

    // Thumbnail loading tasks (cache moved to CacheService)
    var thumbnailLoadingTasks: [String: Task<Void, Never>] = [:]
    let summaryCacheKeyPrefix = "pdf_summary_cache_"

    enum ViewMode {
        case grid, list
    }

    enum SortOption: String, CaseIterable {
        case date = "Tarih"
        case name = "İsim"
        case size = "Boyut"
    }

    enum SortOrder {
        case ascending, descending
    }

    // MARK: - Computed Properties

    var filteredFiles: [PDFDocumentMetadata] {
        var result = files

        // Klasör filtresi
        result = result.filter { $0.folderId == currentFolder?.id }

        // Etiket filtresi
        if !selectedTags.isEmpty {
            result = result.filter { file in
                let fileTagIds = Set(file.tags.map { $0.id })
                return !selectedTags.isDisjoint(with: fileTagIds)
            }
        }

        // Arama filtresi
        if !searchQuery.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchQuery) ||
                $0.tags.contains { $0.name.localizedCaseInsensitiveContains(searchQuery) }
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
            }
        }

        return result
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
            return
        }

        // Debounce the search
        searchDebounceTask = Task {
            do {
                try await Task.sleep(nanoseconds: searchDebounceDelay)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.searchQuery = newQuery
                }
            } catch {
                // Task was cancelled, ignore
            }
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
