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
    @Published var errorMessage: String?
    @Published var searchQuery = ""
    @Published var viewMode: ViewMode = .grid
    @Published var sortBy: SortOption = .date
    @Published var sortOrder: SortOrder = .descending
    
    // Klasör Yönetimi
    @Published var folders: [Folder] = []
    @Published var currentFolder: Folder? = nil
    @Published var folderPath: [Folder] = []
    
    // Etiket Yönetimi
    @Published var allTags: [Tag] = []
    @Published var selectedTags: Set<UUID> = []
    @Published var showTagFilter: Bool = false
    
    private let supabaseService = SupabaseService.shared
    private let pdfService = PDFService.shared
    
    // Thumbnail cache - memory based
    private var thumbnailCache: [String: Data] = [:]
    private var thumbnailLoadingTasks: [String: Task<Void, Never>] = [:]
    private let summaryCacheKeyPrefix = "pdf_summary_cache_"
    
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
        result.sort { a, b in
            switch sortBy {
            case .date:
                return sortOrder == .descending ? a.uploadedAt > b.uploadedAt : a.uploadedAt < b.uploadedAt
            case .name:
                let nameComparison = a.name.localizedCompare(b.name) == .orderedAscending
                return sortOrder == .ascending ? nameComparison : !nameComparison
            case .size:
                return sortOrder == .descending ? a.size > b.size : a.size < b.size
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
            for tag in file.tags {
                if !tagIds.contains(tag.id) {
                    tagIds.insert(tag.id)
                    uniqueTags.append(tag)
                }
            }
        }
        
        // Dosya sayısına göre sırala (allTags'taki file_count bilgisini kullan)
        return uniqueTags.sorted { tag1, tag2 in
            let count1 = allTags.first { $0.id == tag1.id }?.fileCount ?? 0
            let count2 = allTags.first { $0.id == tag2.id }?.fileCount ?? 0
            return count1 > count2
        }
    }
    
    // MARK: - Load Files
    
    func loadFiles() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            files = try await supabaseService.listFiles()
            applyCachedSummaries()
            
            // Dosya etiketlerini yükle
            for index in files.indices {
                let fileTags = try await supabaseService.getFileTags(fileId: files[index].id)
                files[index].tags = fileTags
            }
            
            // Thumbnailleri lazy olarak yükle
            for index in files.indices {
                loadThumbnailIfNeeded(for: files[index])
            }
        } catch {
            errorMessage = "Dosyalar yüklenemedi: \(error.localizedDescription)"
        }
    }
    
    /// Klasör ve etiketleri yükle
    func loadFoldersAndTags() async {
        do {
            // Her zaman tüm etiketleri yükle (filtreleme için)
            allTags = try await supabaseService.listTags()
            
            // Mevcut klasörün alt klasörlerini yükle
            folders = try await supabaseService.listFolders(parentId: currentFolder?.id)
            
            logInfo("LibraryViewModel", "Klasör ve etiketler yüklendi",
                    details: "\(folders.count) klasör, \(allTags.count) etiket")
        } catch {
            logWarning("LibraryViewModel", "Klasör/etiket yükleme hatası", details: error.localizedDescription)
        }
    }
    
    // MARK: - Thumbnail Loading (Lazy)
    
    func loadThumbnailIfNeeded(for file: PDFDocumentMetadata) {
        // Zaten thumbnail varsa veya yükleme devam ediyorsa atla
        guard file.thumbnailData == nil else { return }
        guard thumbnailLoadingTasks[file.id] == nil else { return }
        
        // Cache'ten kontrol et
        if let cachedData = thumbnailCache[file.id] {
            updateFileThumbnail(fileId: file.id, thumbnailData: cachedData)
            return
        }
        
        if let diskData = loadThumbnailFromDisk(fileId: file.id) {
            thumbnailCache[file.id] = diskData
            updateFileThumbnail(fileId: file.id, thumbnailData: diskData)
            return
        }
        
        // Arka planda thumbnail yükle
        let task = Task {
            await self.generateThumbnail(for: file)
        }
        thumbnailLoadingTasks[file.id] = task
    }
    
    private func generateThumbnail(for file: PDFDocumentMetadata) async {
        defer { thumbnailLoadingTasks[file.id] = nil }
        
        do {
            // PDF'i indir
            let url = try await supabaseService.getFileURL(storagePath: file.storagePath)
            
            // URL'den veri oku
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // PDFDocument oluştur
            guard let document = PDFDocument(data: data) else { return }
            
            // Thumbnail oluştur
            if let thumbnailData = pdfService.generateThumbnailData(for: document) {
                // Cache'e ekle
                thumbnailCache[file.id] = thumbnailData
                saveThumbnailToDisk(thumbnailData, fileId: file.id)
                
                // Dosyayı güncelle
                updateFileThumbnail(fileId: file.id, thumbnailData: thumbnailData)
            }
        } catch {
            logError("LibraryViewModel", "Thumbnail oluşturulamadı: \(file.name)", error: error)
        }
    }
    
    private func updateFileThumbnail(fileId: String, thumbnailData: Data) {
        if let index = files.firstIndex(where: { $0.id == fileId }) {
            files[index].thumbnailData = thumbnailData
        }
    }
    
    // MARK: - Upload File
    
    func uploadFile(url: URL, userId: String) async {
        isUploading = true
        defer { isUploading = false }
        
        do {
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Dosyaya erişim izni yok"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let data = try Data(contentsOf: url)
            let fileName = url.lastPathComponent
            
            // Yükleme yap
            var metadata = try await supabaseService.uploadFile(data, fileName: fileName, userId: userId)
            
            // Mevcut klasöre ekle
            if let folderId = currentFolder?.id {
                do {
                    try await supabaseService.moveFileToFolder(fileId: metadata.id, folderId: folderId)
                    metadata.folderId = folderId
                    logInfo("LibraryViewModel", "Dosya klasöre eklendi", details: currentFolder?.name ?? "")
                } catch {
                    // Migration uygulanmamışsa bu hata verebilir
                    logWarning("LibraryViewModel", "Dosya klasöre eklenemedi (migration gerekli olabilir)", details: error.localizedDescription)
                }
            }
            
            // Thumbnail oluştur
            if let document = PDFDocument(data: data),
               let thumbnailData = pdfService.generateThumbnailData(for: document) {
                metadata.thumbnailData = thumbnailData
                thumbnailCache[metadata.id] = thumbnailData
                saveThumbnailToDisk(thumbnailData, fileId: metadata.id)
            }
            
            files.insert(metadata, at: 0)
            
            // Klasör dosya sayılarını güncelle
            await loadFoldersAndTags()
            
            // Arka planda özet ve etiketler oluştur
            let uploadedFile = metadata
            let pdfData = data
            Task {
                await generateSummary(for: uploadedFile, force: true)
                await generateAndAssignTags(for: uploadedFile, pdfData: pdfData)
            }
            
        } catch {
            errorMessage = "Yükleme başarısız: \(error.localizedDescription)"
        }
    }
    
    /// AI ile etiketler oluştur ve dosyaya ata
    private func generateAndAssignTags(for file: PDFDocumentMetadata, pdfData: Data) async {
        do {
            // PDF metnini çıkar
            guard let document = PDFDocument(data: pdfData) else {
                logWarning("LibraryViewModel", "PDF oluşturulamadı - etiketleme için")
                return
            }
            
            let text = extractTextForSummary(from: document)
            guard !text.isEmpty else {
                logWarning("LibraryViewModel", "PDF'den metin çıkarılamadı - etiketleme için")
                return
            }
            
            // Mevcut etiketleri al (tutarlılık için AI'a gönderilecek)
            let existingTagNames = allTags.map { $0.name }
            
            // AI etiketler oluştur (mevcut etiketleri dikkate alarak)
            let aiResult = try await GeminiService.shared.generateTags(text, existingTags: existingTagNames)
            
            // Etiketleri Supabase'e kaydet veya mevcut olanları bul
            var tagIds: [UUID] = []
            for tagName in aiResult.tags {
                let tag = try await supabaseService.getOrCreateTag(name: tagName)
                tagIds.append(tag.id)
            }
            
            // Dosyaya etiketleri bağla
            try await supabaseService.addTagsToFile(fileId: file.id, tagIds: tagIds)
            
            // Kategoriyi güncelle
            try await supabaseService.updateFileCategory(fileId: file.id, category: aiResult.category)
            
            // Lokal state'i güncelle
            if let index = files.firstIndex(where: { $0.id == file.id }) {
                files[index].tags = try await supabaseService.getFileTags(fileId: file.id)
                files[index].aiCategory = aiResult.category
            }
            
            // Etiket listesini güncelle
            allTags = try await supabaseService.listTags()
            
            logInfo("LibraryViewModel", "AI etiketleme tamamlandı", details: "\(tagIds.count) etiket eklendi")
            
        } catch {
            logError("LibraryViewModel", "AI etiketleme hatası", error: error)
        }
    }
    
    // MARK: - Delete File
    
    func deleteFile(_ file: PDFDocumentMetadata) async {
        do {
            try await supabaseService.deleteFile(id: file.id, storagePath: file.storagePath)
            files.removeAll { $0.id == file.id }
            thumbnailCache.removeValue(forKey: file.id)
            removeThumbnailFromDisk(fileId: file.id)
            removeSummaryFromCache(fileId: file.id)
            
            // Arka planda temizlik yap
            Task {
                // RAG chunk'larını sil
                do {
                    if let fileUUID = UUID(uuidString: file.id) {
                        try await supabaseService.deleteDocumentChunks(fileId: fileUUID)
                    }
                } catch {
                    logWarning("LibraryViewModel", "RAG chunk'ları silinemedi", details: error.localizedDescription)
                }
                
                // Kullanılmayan etiketleri temizle
                do {
                    try await supabaseService.cleanupUnusedTags()
                    // Etiket listesini güncelle
                    await loadFoldersAndTags()
                } catch {
                    logWarning("LibraryViewModel", "Etiket temizliği başarısız", details: error.localizedDescription)
                }
            }
        } catch {
            errorMessage = "Silme başarısız: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Get File URL
    
    func getFileURL(_ file: PDFDocumentMetadata) async -> URL? {
        do {
            return try await supabaseService.getFileURL(storagePath: file.storagePath)
        } catch {
            errorMessage = "Dosya URL'i alınamadı"
            return nil
        }
    }
    
    // MARK: - Toggle Sort
    
    func toggleSort(_ option: SortOption) {
        if sortBy == option {
            sortOrder = sortOrder == .ascending ? .descending : .ascending
        } else {
            sortBy = option
            sortOrder = .descending
        }
    }
    
    // MARK: - Folder Management
    
    /// Klasöre git
    func navigateToFolder(_ folder: Folder?) {
        if let folder = folder {
            folderPath.append(folder)
            currentFolder = folder
        } else {
            folderPath.removeAll()
            currentFolder = nil
        }
        Task {
            await loadFoldersAndTags()
        }
    }
    
    /// Bir önceki klasöre dön
    func navigateBack() {
        guard !folderPath.isEmpty else { return }
        folderPath.removeLast()
        currentFolder = folderPath.last
        Task {
            await loadFoldersAndTags()
        }
    }
    
    /// Yeni klasör oluştur
    func createFolder(name: String, color: String = "#6366F1") async {
        do {
            let folder = try await supabaseService.createFolder(
                name: name,
                color: color,
                parentId: currentFolder?.id
            )
            // Klasörleri yeniden yükle (dosya sayılarıyla birlikte)
            await loadFoldersAndTags()
            logInfo("LibraryViewModel", "Klasör oluşturuldu", details: folder.name)
        } catch {
            errorMessage = "Klasör oluşturulamadı: \(error.localizedDescription)"
            logError("LibraryViewModel", "Klasör oluşturma hatası", error: error)
        }
    }
    
    /// Klasör sil
    func deleteFolder(_ folder: Folder) async {
        do {
            try await supabaseService.deleteFolder(id: folder.id)
            await loadFoldersAndTags()
            logInfo("LibraryViewModel", "Klasör silindi", details: folder.name)
        } catch {
            errorMessage = "Klasör silinemedi: \(error.localizedDescription)"
            logError("LibraryViewModel", "Klasör silme hatası", error: error)
        }
    }
    
    /// Dosyayı klasöre taşı
    func moveFile(_ file: PDFDocumentMetadata, to folder: Folder?) async {
        do {
            try await supabaseService.moveFileToFolder(fileId: file.id, folderId: folder?.id)
            if let index = files.firstIndex(where: { $0.id == file.id }) {
                files[index].folderId = folder?.id
            }
            // Klasör dosya sayılarını güncelle
            await loadFoldersAndTags()
        } catch {
            errorMessage = "Dosya taşınamadı: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Tag Management
    
    /// Etiket filtresini aç/kapa
    func toggleTagFilter(_ tagId: UUID) {
        if selectedTags.contains(tagId) {
            selectedTags.remove(tagId)
        } else {
            selectedTags.insert(tagId)
        }
    }
    
    /// Tüm etiket filtrelerini temizle
    func clearTagFilters() {
        selectedTags.removeAll()
    }
    
    // MARK: - Clear Cache
    
    func clearThumbnailCache() {
        thumbnailCache.removeAll()
        thumbnailLoadingTasks.values.forEach { $0.cancel() }
        thumbnailLoadingTasks.removeAll()
        
        if let cacheDirectory = thumbnailCacheDirectoryURL() {
            try? FileManager.default.removeItem(at: cacheDirectory)
        }
    }
    
    // MARK: - AI Summary Generation
    
    /// PDF için AI özeti oluştur
    func generateSummary(for file: PDFDocumentMetadata, force: Bool = false) async {
        // Zaten özet varsa ve force değilse atla
        if !force {
            if let summary = file.summary, !summary.isEmpty {
                return
            }
            
            if let cachedSummary = cachedSummary(for: file.id), !cachedSummary.isEmpty {
                updateFileSummary(fileId: file.id, summary: cachedSummary)
                return
            }
        }
        
        do {
            // PDF'i indir
            let url = try await supabaseService.getFileURL(storagePath: file.storagePath)
            let (data, _) = try await URLSession.shared.data(from: url)
            
            // PDFDocument oluştur
            guard let document = PDFDocument(data: data) else {
                logError("LibraryViewModel", "PDF oluşturulamadı: \(file.name)")
                return
            }
            
            // Metin çıkar (ilk birkaç sayfa yeterli)
            let text = extractTextForSummary(from: document)
            
            guard !text.isEmpty else {
                logWarning("LibraryViewModel", "PDF'den metin çıkarılamadı: \(file.name)")
                return
            }
            
            // AI ile özet oluştur
            let summary = try await GeminiService.shared.generateDocumentSummary(text)
            
            // Dosyayı güncelle
            updateFileSummary(fileId: file.id, summary: summary)
            saveSummaryToCache(summary, fileId: file.id)
            
            // Supabase'e kaydet
            try? await supabaseService.updateFileSummary(fileId: file.id, summary: summary)
            
            logInfo("LibraryViewModel", "Özet oluşturuldu: \(file.name)")
            
        } catch {
            logError("LibraryViewModel", "Özet oluşturma hatası: \(file.name)", error: error)
        }
    }
    
    /// PDF'den özet için metin çıkar (ilk 3 sayfa)
    private func extractTextForSummary(from document: PDFDocument) -> String {
        var text = ""
        let pageCount = min(document.pageCount, 3)
        
        for i in 0..<pageCount {
            if let page = document.page(at: i), let pageText = page.string {
                text += pageText + "\n\n"
            }
        }
        
        // Maksimum 3000 karakter
        return String(text.prefix(3000))
    }
    
    /// Dosya özetini güncelle
    private func updateFileSummary(fileId: String, summary: String) {
        if let index = files.firstIndex(where: { $0.id == fileId }) {
            files[index].summary = summary
        }
    }
    
    // MARK: - Summary Cache
    
    private func summaryCacheKey(for fileId: String) -> String {
        "\(summaryCacheKeyPrefix)\(fileId)"
    }
    
    private func cachedSummary(for fileId: String) -> String? {
        UserDefaults.standard.string(forKey: summaryCacheKey(for: fileId))
    }
    
    private func saveSummaryToCache(_ summary: String, fileId: String) {
        UserDefaults.standard.set(summary, forKey: summaryCacheKey(for: fileId))
    }
    
    private func removeSummaryFromCache(fileId: String) {
        UserDefaults.standard.removeObject(forKey: summaryCacheKey(for: fileId))
    }
    
    private func applyCachedSummaries() {
        for index in files.indices {
            let fileId = files[index].id
            if let summary = files[index].summary, !summary.isEmpty {
                saveSummaryToCache(summary, fileId: fileId)
                continue
            }
            
            if let cachedSummary = cachedSummary(for: fileId), !cachedSummary.isEmpty {
                files[index].summary = cachedSummary
            }
        }
    }
    
    // MARK: - Thumbnail Disk Cache
    
    private func thumbnailCacheDirectoryURL() -> URL? {
        guard let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let directory = baseURL.appendingPathComponent("pdf_thumbnail_cache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
    
    private func thumbnailDiskURL(for fileId: String) -> URL? {
        guard let directory = thumbnailCacheDirectoryURL() else { return nil }
        return directory.appendingPathComponent("\(fileId).jpg")
    }
    
    private func loadThumbnailFromDisk(fileId: String) -> Data? {
        guard let url = thumbnailDiskURL(for: fileId) else { return nil }
        return try? Data(contentsOf: url)
    }
    
    private func saveThumbnailToDisk(_ data: Data, fileId: String) {
        guard let url = thumbnailDiskURL(for: fileId) else { return }
        try? data.write(to: url, options: [.atomic])
    }
    
    private func removeThumbnailFromDisk(fileId: String) {
        guard let url = thumbnailDiskURL(for: fileId) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
