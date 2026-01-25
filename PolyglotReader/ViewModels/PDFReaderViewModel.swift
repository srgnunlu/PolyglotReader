import Foundation
import Combine
import PDFKit

// MARK: - PDF Reader ViewModel
@MainActor
class PDFReaderViewModel: ObservableObject {
    @Published var document: PDFDocument?
    @Published var currentPage = 1
    @Published var totalPages = 0
    @Published var scale: CGFloat = 1.0
    @Published var isLoading = false
    @Published var isChatReady = false
    @Published var searchQuery = ""
    @Published var searchResults: [PDFSearchResult] = []
    @Published var currentSearchIndex = 0
    @Published var annotations: [Annotation] = []
    @Published var selectedText: String?
    @Published var selectionRect: CGRect?
    @Published var selectionPage: Int?
    @Published var selectionPDFRects: [CGRect]?  // PDF koordinatları - annotation için
    @Published var initialScrollPosition: CGPoint? // Başlangıç scroll pozisyonu
    @Published var showTranslationPopup = false
    @Published var extractedText = ""

    // MARK: - Network Status (Phase 6)
    @Published private(set) var isOffline = false  // Çevrimdışı durumu

    // MARK: - Page Cache for Instant Loading
    @Published var cachedFirstPageImage: UIImage?  // İlk sayfa için önbellek görseli

    // Hızlı Çeviri Modu
    @Published var isQuickTranslationMode = false
    @Published var showQuickTranslation = false

    // Görsel Seçim
    @Published var selectedImage: PDFImageInfo?
    @Published var showImagePopup = false

    let fileMetadata: PDFDocumentMetadata
    private let pdfService = PDFService.shared
    private let geminiService = GeminiService.shared
    private let supabaseService = SupabaseService.shared
    private var pdfData: Data?

    // MARK: - Page Pre-rendering
    // MARK: - Page Pre-rendering
    private var pagePreRenderingTask: Task<Void, Never>?
    private var progressUpdateTask: Task<Void, Never>?
    private var networkObserver: AnyCancellable?
    private let adjacentPagesToPreRender = 1  // Pre-render 1 page ahead/behind

    init(file: PDFDocumentMetadata) {
        self.fileMetadata = file
        setupNetworkObserver()
        #if DEBUG
        MemoryDebugger.shared.logInit(self)
        #endif
    }

    deinit {
        #if DEBUG
        // Log deinit immediately without creating a Task that could hold references
        print("[MemoryDebugger] [DEINIT] PDFReaderViewModel")
        #endif
        pagePreRenderingTask?.cancel()
        progressUpdateTask?.cancel()
        networkObserver?.cancel()
    }

    // MARK: - Network Observer (Phase 6)

    private func setupNetworkObserver() {
        networkObserver = NetworkMonitor.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                self?.isOffline = !isConnected
                if isConnected {
                    logInfo("PDFReaderVM", "Network restored - syncing pending annotations")
                    SyncQueue.shared.processQueue()
                }
            }
    }

    // MARK: - Load Document

    func loadDocument() async {
        isLoading = true
        defer { isLoading = false }

        // İlk sayfa görseli disk cache'de varsa hemen yükle (instant placeholder)
        loadCachedFirstPageImage()

        do {
            logInfo("PDFReaderVM", "PDF yükleniyor: \(fileMetadata.name)")

            // Cache-first strategy: Try disk cache first, then network
            let (data, url) = try await loadPdfDataWithCache()
            let pdfDocument = try createPdfDocument(from: data)

            applyLoadedDocument(pdfDocument, data: data)
            loadAnnotationsAsync()
            loadReadingProgressAsync()
            prepareChatAsync(url: url)

            // İlk sayfayı arka planda cache'e kaydet (bir sonraki açılış için)
            cacheFirstPageAsync(document: pdfDocument)
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            logError("PDFReaderVM", "Doküman yükleme hatası", error: appError)
            ErrorHandlingService.shared.handle(
                appError,
                context: .init(
                    source: "PDFReaderVM",
                    operation: "LoadDocument"
                ) { [weak self] in
                    Task { await self?.loadDocument() }
                    return
                }
            )
        }
    }

    /// Disk cache'den ilk sayfa görselini yükle (instant loading için)
    private func loadCachedFirstPageImage() {
        if let cachedImage = PDFPageCacheService.shared.getCachedPageImage(fileId: fileMetadata.id, pageNumber: 1) {
            cachedFirstPageImage = cachedImage
            logInfo("PDFReaderVM", "📦 İlk sayfa görseli cache'den yüklendi (instant)")
        }
    }

    /// İlk sayfayı disk cache'e kaydet (sonraki açılışlar için)
    private func cacheFirstPageAsync(document: PDFDocument) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            // İlk 3 sayfayı cache'le (instant loading için)
            for pageNum in 1...min(3, document.pageCount) {
                guard let page = document.page(at: pageNum - 1) else { continue }

                // Cache'de zaten varsa atla
                if PDFPageCacheService.shared.isCached(fileId: self.fileMetadata.id, pageNumber: pageNum) {
                    continue
                }

                do {
                    // Render page at 1.5x scale (good balance between quality and size)
                    let image = try PDFService.shared.renderPageAsImage(page: page, scale: 1.5)
                    PDFPageCacheService.shared.cachePageImage(image, fileId: self.fileMetadata.id, pageNumber: pageNum)

                    // İlk sayfa ise published property'yi güncelle
                    if pageNum == 1 {
                        await MainActor.run {
                            self.cachedFirstPageImage = image
                        }
                    }

                    logDebug("PDFReaderVM", "Sayfa \(pageNum) cache'e kaydedildi")
                } catch {
                    logDebug("PDFReaderVM", "Sayfa \(pageNum) cache'e kaydedilemedi", details: error.localizedDescription)
                }
            }
        }
    }
    
    /// Load PDF data with cache-first strategy
    /// Returns cached data if available, otherwise downloads and caches
    private func loadPdfDataWithCache() async throws -> (Data, URL) {
        let storagePath = fileMetadata.storagePath
        
        // 1. Check disk cache first
        if let cachedData = PDFCacheService.shared.getCachedPDF(for: storagePath) {
            logInfo("PDFReaderVM", "📦 Cache'den yüklendi", details: "\(ByteCountFormatter.string(fromByteCount: Int64(cachedData.count), countStyle: .file))")
            // Still need URL for AI chat, but don't download
            let url = try await fetchFileURL()
            return (cachedData, url)
        }
        
        // 2. Cache miss - download from network
        logInfo("PDFReaderVM", "🌐 Ağdan indiriliyor...")
        let url = try await fetchFileURL()
        let data = try await downloadPdfData(from: url)
        
        // 3. Save to disk cache for next time
        PDFCacheService.shared.cachePDF(data, for: storagePath)
        
        return (data, url)
    }

    private func fetchFileURL() async throws -> URL {
        let url = try await supabaseService.getFileURL(storagePath: fileMetadata.storagePath)
        logDebug("PDFReaderVM", "URL alındı", details: url.absoluteString)
        return url
    }

    private func downloadPdfData(from url: URL) async throws -> Data {
        let (data, response) = try await SecurityManager.shared.secureSession.data(from: url)

        if let httpResponse = response as? HTTPURLResponse {
            logDebug("PDFReaderVM", "HTTP Status: \(httpResponse.statusCode)")
            guard (200...299).contains(httpResponse.statusCode) else {
                logError("PDFReaderVM", "Sunucu hatası: \(httpResponse.statusCode)")
                throw AppError.network(reason: .server(statusCode: httpResponse.statusCode))
            }
        }

        logDebug("PDFReaderVM", "Veri indirildi", details: "\(data.count) bytes")
        return data
    }

    private func createPdfDocument(from data: Data) throws -> PDFDocument {
        let pdfDocument = try pdfService.loadPDF(from: data)
        logInfo("PDFReaderVM", "PDF yüklendi", details: "\(pdfDocument.pageCount) sayfa")
        return pdfDocument
    }

    private func applyLoadedDocument(_ pdfDocument: PDFDocument, data: Data) {
        pdfData = data
        document = pdfDocument
        totalPages = pdfDocument.pageCount
    }

    private func loadAnnotationsAsync() {
        Task {
            do {
                let loadedAnnotations = try await supabaseService.getAnnotations(fileId: fileMetadata.id)
                await MainActor.run {
                    self.annotations = loadedAnnotations
                    logDebug("PDFReaderVM", "Annotasyonlar yüklendi", details: "\(loadedAnnotations.count) adet")
                }
            } catch {
                logWarning("PDFReaderVM", "Annotasyon yükleme hatası", details: error.localizedDescription)
            }
        }
    }

    private func prepareChatAsync(url: URL) {
        Task.detached(priority: .background) {
            logInfo("PDFReaderVM", "AI Chat hazırlanıyor...")
            await self.prepareAIChat(url: url, fileId: self.fileMetadata.id)
            logInfo("PDFReaderVM", "AI Chat hazır")
        }
    }

    private func prepareAIChat(url: URL, fileId: String) async {
        // Create a SEPARATE PDFDocument instance for background text extraction
        // This is CRITICAL to prevent EXC_BAD_ACCESS caused by concurrent access to the same PDFDocument
        // while the main thread renders it.
        guard let backgroundDoc = PDFDocument(url: url) else {
            logError("PDFReaderVM", "Background PDFDocument oluşturulamadı")
            return
        }

        // ID'yi UUID'ye çevir
        guard let fileUUID = UUID(uuidString: fileId) else {
            logError("PDFReaderVM", "Geçersiz dosya ID formatı")
            await MainActor.run {
                self.isChatReady = true // Fallback to legacy
            }
            return
        }

        // Metin çıkar (from ISOLATED document)
        let text = PDFService.shared.extractText(from: backgroundDoc)

        await MainActor.run {
            self.extractedText = text
            // Chat butonunu hemen göster - PDF içeriği ile legacy modda başlat
            // Böylece RAG hazır olmasa bile kullanıcı soru sorabilir
            GeminiService.shared.initChatSession(pdfContent: text)
            self.isChatReady = true
            logInfo("PDFReaderVM", "AI Chat hazır (PDF içeriği yüklendi)")
        }

        // RAG indexleme kontrolü - arka planda devam et
        let isIndexed = await RAGService.shared.isDocumentIndexed(fileId: fileUUID)

        if isIndexed {
            // Zaten indexli - RAG modu aktif
            logInfo("PDFReaderVM", "RAG modu aktif (önceden indexlenmiş)")
        } else {
            // İlk kez açılıyor - arka planda indexle
            logInfo("PDFReaderVM", "Doküman arka planda indexleniyor...")

            Task.detached(priority: .background) {
                do {
                    try await RAGService.shared.indexDocument(text: text, fileId: fileUUID)
                    logInfo("PDFReaderVM", "RAG indexleme tamamlandı")
                } catch {
                    // Indexleme başarısız - legacy mod zaten aktif
                    logWarning("PDFReaderVM", "RAG indexleme başarısız", details: error.localizedDescription)
                }
            }
        }
    }

    private func loadReadingProgressAsync() {
        Task {
            do {
                if let progress = try await supabaseService.getReadingProgress(fileId: fileMetadata.id) {
                    await MainActor.run {
                        self.currentPage = progress.page
                        self.scale = CGFloat(progress.zoomScale)
                        self.initialScrollPosition = CGPoint(x: progress.offsetX, y: progress.offsetY)
                        logInfo("PDFReaderVM", "Okuma ilerlemesi yüklendi", details: "Sayfa \(progress.page)")
                    }
                }
            } catch {
                logWarning("PDFReaderVM", "Okuma ilerlemesi yüklenemedi", details: error.localizedDescription)
            }
        }
    }
    
    func updateReadingProgress(page: Int, point: CGPoint, scale: CGFloat) {
        // İlerleme kaydetme (debounce: 2 saniye)
        progressUpdateTask?.cancel()
        progressUpdateTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            
            do {
                try await supabaseService.saveReadingProgress(
                    fileId: fileMetadata.id,
                    page: page,
                    offsetX: point.x,
                    offsetY: point.y,
                    scale: Double(scale)
                )
                logDebug("PDFReaderVM", "Okuma ilerlemesi kaydedildi")
            } catch {
                logError("PDFReaderVM", "Okuma ilerlemesi kaydedilemedi", error: error)
            }
        }
    }

    // MARK: - Navigation

    func goToPage(_ page: Int) {
        guard page >= 1, page <= totalPages else { return }
        currentPage = page
        preRenderAdjacentPages()
    }

    func nextPage() {
        goToPage(currentPage + 1)
    }

    func previousPage() {
        goToPage(currentPage - 1)
    }

    // MARK: - P4: Current Page Text for Smart Suggestions
    /// Mevcut sayfanın metnini döndürür (Smart Suggestions için)
    var currentPageText: String? {
        guard let doc = document,
              currentPage >= 1,
              currentPage <= totalPages,
              let page = doc.page(at: currentPage - 1) else {
            return nil
        }
        return page.string
    }

    // MARK: - Zoom

    func zoomIn() {
        scale = min(scale + 0.1, 2.5)
    }

    func zoomOut() {
        scale = max(scale - 0.1, 0.5)
    }

    // MARK: - Search

    func search() {
        guard let doc = document, !searchQuery.isEmpty else {
            searchResults = []
            return
        }

        do {
            searchResults = try pdfService.search(query: searchQuery, in: doc)
            currentSearchIndex = 0

            if let first = searchResults.first {
                goToPage(first.pageNumber)
            }
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            ErrorHandlingService.shared.handle(
                appError,
                context: .init(source: "PDFReaderVM", operation: "Search")
            )
            searchResults = []
        }
    }

    func nextSearchResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex + 1) % searchResults.count
        goToPage(searchResults[currentSearchIndex].pageNumber)
    }

    func previousSearchResult() {
        guard !searchResults.isEmpty else { return }
        currentSearchIndex = (currentSearchIndex - 1 + searchResults.count) % searchResults.count
        goToPage(searchResults[currentSearchIndex].pageNumber)
    }

    // MARK: - Text Selection

    func handleSelection(text: String, rect: CGRect, page: Int, pdfRects: [CGRect] = []) {
        // Boş metin geldiyse seçimi temizle (dış alana tıklandığında)
        guard !text.isEmpty else {
            clearSelection()
            return
        }

        // Görsel seçimini temizle - text ve image popup aynı anda açık olmamalı
        clearImageSelection()

        selectedText = text
        selectionRect = rect
        selectionPage = page
        selectionPDFRects = pdfRects  // PDF koordinatlarını sakla

        // Hızlı Çeviri Modu aktifse direkt QuickTranslationPopup göster
        if isQuickTranslationMode {
            showTranslationPopup = false
            showQuickTranslation = true
        } else {
            showTranslationPopup = true
            showQuickTranslation = false
        }
    }

    func clearSelection() {
        selectedText = nil
        selectionRect = nil
        selectionPage = nil
        selectionPDFRects = nil
        showTranslationPopup = false
        showQuickTranslation = false
    }

    // MARK: - Image Selection

    func handleImageSelection(_ imageInfo: PDFImageInfo) {
        // Metin seçimini temizle
        clearSelection()

        // Görsel seçimini ayarla
        selectedImage = imageInfo
        showImagePopup = true

        logInfo("PDFReaderVM", "Görsel seçildi", details: "Sayfa: \(imageInfo.pageNumber)")
    }

    func clearImageSelection() {
        selectedImage = nil
        showImagePopup = false
    }

    func toggleQuickTranslationMode() {
        isQuickTranslationMode.toggle()
        clearSelection()
        logInfo("PDFReaderVM", isQuickTranslationMode ? "Hızlı Çeviri Modu açıldı" : "Normal mod")
    }

    // MARK: - Annotations

    func addAnnotation(type: AnnotationType, color: String, note: String? = nil, isAiGenerated: Bool = false) async {
        guard let text = selectedText,
              let page = selectionPage else { return }

        // PDF koordinatlarını kullan (doğru pozisyonlama için)
        let annotationRects: [AnnotationRect]
        if let pdfRects = selectionPDFRects, !pdfRects.isEmpty {
            annotationRects = pdfRects.map { rect in
                AnnotationRect(
                    x: rect.origin.x,
                    y: rect.origin.y,
                    width: rect.width,
                    height: rect.height
                )
            }
        } else {
            // Fallback: boş array - text search ile bulunacak
            annotationRects = []
        }

        let annotation = Annotation(
            fileId: fileMetadata.id,
            pageNumber: page,
            type: type,
            color: color,
            rects: annotationRects,
            text: text,
            note: note,
            isAiGenerated: isAiGenerated
        )

        annotations.append(annotation)

        do {
            // Phase 6: Queue if offline
            if NetworkMonitor.shared.isConnected {
                try await supabaseService.saveAnnotation(annotation)
            } else {
                try SyncQueue.shared.enqueue(
                    type: .annotationCreate,
                    object: annotation,
                    fileId: fileMetadata.id
                )
                logInfo("PDFReaderVM", "Annotation queued for sync (offline)")
            }
        } catch {
            logError("PDFReaderVM", "Failed to save annotation", error: error)
        }

        clearSelection()
    }

    func annotationsForCurrentPage() -> [Annotation] {
        annotations.filter { $0.pageNumber == currentPage }
    }

    // MARK: - Update Annotation Note

    func updateAnnotationNote(annotationId: String, note: String) async {
        // Yerel listeyi güncelle
        if let index = annotations.firstIndex(where: { $0.id == annotationId }) {
            annotations[index].note = note
            annotations[index].updatedAt = Date()
        }

        // Supabase'de güncelle
        do {
            // Phase 6: Queue if offline
            if NetworkMonitor.shared.isConnected {
                try await supabaseService.updateAnnotation(id: annotationId, note: note)
                logInfo("PDFReaderVM", "Not güncellendi", details: "ID: \(annotationId)")
            } else {
                if let annotation = annotations.first(where: { $0.id == annotationId }) {
                    try SyncQueue.shared.enqueue(
                        type: .annotationUpdate,
                        object: annotation,
                        fileId: fileMetadata.id
                    )
                    logInfo("PDFReaderVM", "Annotation update queued (offline)")
                }
            }
        } catch {
            logError("PDFReaderVM", "Not güncelleme hatası", error: error)
        }
    }

    // MARK: - Delete Annotation

    func deleteAnnotation(annotationId: String) async {
        // Yerel listeden sil
        annotations.removeAll { $0.id == annotationId }

        // Supabase'den sil
        do {
            // Phase 6: Queue if offline
            if NetworkMonitor.shared.isConnected {
                try await supabaseService.deleteAnnotation(id: annotationId)
                logInfo("PDFReaderVM", "Annotation silindi", details: "ID: \(annotationId)")
            } else {
                SyncQueue.shared.enqueue(
                    type: .annotationDelete,
                    payload: Data(annotationId.utf8),
                    fileId: fileMetadata.id
                )
                logInfo("PDFReaderVM", "Annotation deletion queued (offline)")
            }
        } catch {
            logError("PDFReaderVM", "Annotation silme hatası", error: error)
        }
    }

    // MARK: - Page Pre-rendering

    /// Pre-render adjacent pages for smoother navigation
    private func preRenderAdjacentPages() {
        guard let doc = document else { return }

        // Cancel any existing pre-rendering task
        pagePreRenderingTask?.cancel()

        pagePreRenderingTask = Task.detached(priority: .utility) {
            await self.renderAdjacentPages(for: doc)
        }
    }

    private func renderAdjacentPages(for doc: PDFDocument) async {
        let fileId = fileMetadata.id
        let current = await MainActor.run { self.currentPage }
        let total = await MainActor.run { self.totalPages }
        let currentScale = await MainActor.run { self.scale }

        // Calculate pages to pre-render
        let pagesToRender = [
            current - 1,  // Previous page
            current + 1   // Next page
        ].filter { $0 >= 1 && $0 <= total }

        for pageNum in pagesToRender {
            // Check if cancelled
            guard !Task.isCancelled else { return }

            // Check cache first
            if CacheService.shared.getPDFPage(
                fileId: fileId,
                pageNumber: pageNum,
                scale: currentScale
            ) != nil {
                continue  // Already cached
            }

            // Render page (0-indexed in PDFKit)
            guard let page = doc.page(at: pageNum - 1) else { continue }

            do {
                let image = try PDFService.shared.renderPageAsImage(
                    page: page,
                    scale: min(currentScale, 1.5)  // Limit pre-render scale for performance
                )

                // Store in cache
                CacheService.shared.setPDFPage(
                    image,
                    fileId: fileId,
                    pageNumber: pageNum,
                    scale: currentScale
                )

                logDebug(
                    "PDFReaderVM",
                    "Sayfa ön-render edildi",
                    details: "Sayfa \(pageNum)"
                )
            } catch {
                // Silently fail for pre-rendering
                logDebug(
                    "PDFReaderVM",
                    "Ön-render başarısız",
                    details: "Sayfa \(pageNum): \(error.localizedDescription)"
                )
            }
        }
    }

    /// Clear page cache when document is closed
    func cleanup() {
        pagePreRenderingTask?.cancel()
        CacheService.shared.removePDFPages(forFileId: fileMetadata.id)
        logDebug("PDFReaderVM", "Sayfa cache temizlendi")
    }
}
