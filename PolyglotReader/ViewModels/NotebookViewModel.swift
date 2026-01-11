import Foundation
import Combine

// MARK: - Notebook Category
enum NotebookCategory: String, CaseIterable, Identifiable {
    case favorites = "Favoriler"
    case notes = "Notlarım"
    case aiNotes = "AI Notları"
    case yellow = "Sarı Vurgular"
    case green = "Yeşil Vurgular"
    case blue = "Mavi Vurgular"
    case pink = "Pembe Vurgular"
    case underlines = "Altı Çizililer"
    case files = "Dosyalar"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .favorites: return "star.fill"
        case .notes: return "note.text"
        case .aiNotes: return "sparkles"
        case .yellow: return "highlighter"
        case .green: return "highlighter"
        case .blue: return "highlighter"
        case .pink: return "highlighter"
        case .underlines: return "underline"
        case .files: return "doc.text"
        }
    }

    var color: String {
        switch self {
        case .favorites: return "#F59E0B"
        case .notes: return "#6366F1"
        case .aiNotes: return "#8B5CF6"
        case .yellow: return "#fef08a"
        case .green: return "#bbf7d0"
        case .blue: return "#bae6fd"
        case .pink: return "#fbcfe8"
        case .underlines: return "#EF4444"
        case .files: return "#3B82F6"
        }
    }
}

// MARK: - Sort Option
enum NotebookSortOption: String, CaseIterable {
    case newest = "En Yeni"
    case oldest = "En Eski"
    case fileName = "Dosya Adı"
    case pageNumber = "Sayfa No"
}

// MARK: - File Annotation Info
struct FileAnnotationInfo: Identifiable {
    let id: String
    let name: String
    let count: Int
}

// MARK: - Notebook ViewModel
@MainActor
class NotebookViewModel: ObservableObject {
    @Published var annotations: [AnnotationWithFile] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchQuery = ""
    @Published var selectedCategory: NotebookCategory?
    @Published var selectedFileId: String?
    @Published var sortOption: NotebookSortOption = .newest
    @Published var stats = AnnotationStats()
    @Published var fileAnnotationCounts: [FileAnnotationInfo] = []
    @Published var recentFavorites: [AnnotationWithFile] = []

    private let supabaseService = SupabaseService.shared

    static let highlightColors = [
        ("#fef08a", "Sarı"),
        ("#bbf7d0", "Yeşil"),
        ("#fbcfe8", "Pembe"),
        ("#bae6fd", "Mavi")
    ]

    /// Benzersiz dosya listesi (filtreleme için)
    var uniqueFiles: [(id: String, name: String)] {
        var seen = Set<String>()
        var result: [(id: String, name: String)] = []

        for ann in annotations where !seen.contains(ann.fileId) {
            seen.insert(ann.fileId)
            result.append((id: ann.fileId, name: ann.fileName))
        }

        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Filtrelenmiş ve sıralanmış annotation'lar
    var filteredAnnotations: [AnnotationWithFile] {
        var result = annotations

        // Arama filtresi
        if !searchQuery.isEmpty {
            result = result.filter { ann in
                (ann.text?.localizedCaseInsensitiveContains(searchQuery) ?? false) ||
                (ann.note?.localizedCaseInsensitiveContains(searchQuery) ?? false) ||
                ann.fileName.localizedCaseInsensitiveContains(searchQuery)
            }
        }

        // Kategori filtresi
        if let category = selectedCategory {
            result = result.filter { ann in
                switch category {
                case .favorites:
                    return ann.isFavorite
                case .notes:
                    return !(ann.note ?? "").isEmpty && !ann.isAiGenerated
                case .aiNotes:
                    return ann.isAiGenerated
                case .yellow:
                    return ann.color.lowercased() == "#fef08a" && ann.type == .highlight
                case .green:
                    return ann.color.lowercased() == "#bbf7d0" && ann.type == .highlight
                case .blue:
                    return ann.color.lowercased() == "#bae6fd" && ann.type == .highlight
                case .pink:
                    return ann.color.lowercased() == "#fbcfe8" && ann.type == .highlight
                case .underlines:
                    return ann.type == .underline
                case .files:
                    return true // Dosya filtresi ayrı
                }
            }
        }

        // Dosya filtresi (case-insensitive UUID karşılaştırma)
        if let fileId = selectedFileId {
            result = result.filter { $0.fileId.lowercased() == fileId.lowercased() }
        }

        // Sıralama
        switch sortOption {
        case .newest:
            result.sort { $0.createdAt > $1.createdAt }
        case .oldest:
            result.sort { $0.createdAt < $1.createdAt }
        case .fileName:
            result.sort { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
        case .pageNumber:
            result.sort {
                if $0.fileName == $1.fileName {
                    return $0.pageNumber < $1.pageNumber
                }
                return $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending
            }
        }

        return result
    }

    var hasActiveFilters: Bool {
        !searchQuery.isEmpty || selectedCategory != nil || selectedFileId != nil
    }

    func resetFilters() {
        searchQuery = ""
        selectedCategory = nil
        selectedFileId = nil
        sortOption = .newest
    }

    // MARK: - Supabase Operations

    func loadAnnotations() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let results = try await supabaseService.getAllAnnotations()

            annotations = results.map { item in
                AnnotationWithFile(
                    id: item.annotation.id,
                    fileId: item.annotation.fileId,
                    fileName: item.fileName,
                    fileThumbnail: nil,
                    pageNumber: item.annotation.pageNumber,
                    type: item.annotation.type,
                    color: item.annotation.color,
                    rects: item.annotation.rects,
                    text: item.annotation.text,
                    note: item.annotation.note,
                    isAiGenerated: item.annotation.isAiGenerated,
                    isFavorite: item.isFavorite,
                    createdAt: item.annotation.createdAt
                )
            }

            // Son 5 favoriyi güncelle
            recentFavorites = annotations
                .filter { $0.isFavorite }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(5)
                .map { $0 }

            logInfo("NotebookVM", "Annotations yüklendi", details: "\(annotations.count) adet")
        } catch {
            errorMessage = "Notlar yüklenirken hata oluştu: \(error.localizedDescription)"
            logError("NotebookVM", "Annotations yükleme hatası", error: error)
        }
    }

    func loadStats() async {
        do {
            let result = try await supabaseService.getAnnotationStats()
            stats = AnnotationStats(
                total: result.total,
                highlights: result.highlights,
                notes: result.notes,
                aiNotes: result.aiNotes,
                favorites: result.favorites,
                colorCounts: result.colorCounts
            )
            logInfo("NotebookVM", "Stats yüklendi", details: "Toplam: \(result.total)")
        } catch {
            logError("NotebookVM", "Stats yükleme hatası", error: error)
        }
    }

    func loadFileAnnotationCounts() async {
        do {
            isLoading = true
            let counts = try await supabaseService.getFileAnnotationCounts()

            // Get files to resolve names
            let files = try await supabaseService.listFiles() // Or simplified list

            fileAnnotationCounts = counts
                .map { fileId, count in
                    let fileName = files.first { $0.id == fileId }?.name ?? "Unknown Document"
                    return FileAnnotationInfo(id: fileId, name: fileName, count: count)
                }
                .sorted { $0.count > $1.count }

            isLoading = false
            logInfo("NotebookVM", "Dosya sayıları yüklendi", details: "\(fileAnnotationCounts.count) dosya")
        } catch {
            logError("NotebookVM", "Dosya sayıları yükleme hatası", error: error)
        }
    }

    func loadDashboard() async {
        isLoading = true
        defer { isLoading = false }

        // Paralel yükleme
        async let annotationsTask: () = loadAnnotations()
        async let statsTask: () = loadStats()
        async let fileCountsTask: () = loadFileAnnotationCounts()

        await annotationsTask
        await statsTask
        await fileCountsTask
    }

    func toggleFavorite(_ id: String) async {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }

        let newValue = !annotations[index].isFavorite

        do {
            _ = try await supabaseService.toggleAnnotationFavorite(id: id)
            annotations[index].isFavorite = newValue

            // Stats güncelle
            if newValue {
                stats.favorites += 1
            } else {
                stats.favorites = max(0, stats.favorites - 1)
            }

            // Favoriler listesini güncelle
            recentFavorites = annotations
                .filter { $0.isFavorite }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(5)
                .map { $0 }

            logInfo("NotebookVM", "Favori güncellendi", details: "ID: \(id), Favori: \(newValue)")
        } catch {
            errorMessage = "Favori güncellenemedi"
            logError("NotebookVM", "Favori güncelleme hatası", error: error)
        }
    }

    func deleteAnnotation(_ id: String) async {
        do {
            try await supabaseService.deleteAnnotation(id: id)
            annotations.removeAll { $0.id == id }

            // Stats güncelle
            stats.total = max(0, stats.total - 1)

            logInfo("NotebookVM", "Annotation silindi", details: "ID: \(id)")
        } catch {
            errorMessage = "Silme işlemi başarısız: \(error.localizedDescription)"
            logError("NotebookVM", "Annotation silme hatası", error: error)
        }
    }

    func refreshAnnotations() async {
        await loadDashboard()
    }

    /// Dosya metadata'sını al (navigasyon için)
    func getFileMetadata(fileId: String) async throws -> PDFDocumentMetadata? {
        try await supabaseService.getFile(id: fileId)
    }

    /// Kategoriye göre sayı al
    func countForCategory(_ category: NotebookCategory) -> Int {
        switch category {
        case .favorites:
            return stats.favorites
        case .notes:
            return stats.notes
        case .aiNotes:
            return stats.aiNotes
        case .yellow:
            return stats.yellowCount
        case .green:
            return stats.greenCount
        case .blue:
            return stats.blueCount
        case .pink:
            return stats.pinkCount
        case .underlines:
            return annotations.filter { $0.type == .underline }.count
        case .files:
            return fileAnnotationCounts.count
        }
    }
}

// MARK: - Annotation With File
struct AnnotationWithFile: Identifiable {
    let id: String
    var fileId: String
    var fileName: String
    var fileThumbnail: Data?
    var pageNumber: Int
    var type: AnnotationType
    var color: String
    var rects: [AnnotationRect]
    var text: String?
    var note: String?
    var isAiGenerated: Bool
    var isFavorite: Bool
    var createdAt: Date

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.string(from: createdAt)
    }

    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM"
        formatter.locale = Locale(identifier: "tr_TR")
        return formatter.string(from: createdAt)
    }

    var displayText: String {
        if let text = text, !text.isEmpty {
            return text
        }
        if let note = note, !note.isEmpty {
            return note
        }
        return "Sayfa \(pageNumber)"
    }

    var colorName: String {
        switch color.lowercased() {
        case "#fef08a": return "Sarı"
        case "#bbf7d0": return "Yeşil"
        case "#bae6fd": return "Mavi"
        case "#fbcfe8": return "Pembe"
        default: return "Diğer"
        }
    }
}
