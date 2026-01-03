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
    @Published var showTranslationPopup = false
    @Published var extractedText = ""
    
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
    
    init(file: PDFDocumentMetadata) {
        self.fileMetadata = file
    }
    
    // MARK: - Load Document
    
    func loadDocument() async {
        isLoading = true
        
        do {
            logInfo("PDFReaderVM", "PDF yükleniyor: \(fileMetadata.name)")
            let url = try await supabaseService.getFileURL(storagePath: fileMetadata.storagePath)
            logDebug("PDFReaderVM", "URL alındı", details: url.absoluteString)
            
            // Always download data first for reliability
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                logDebug("PDFReaderVM", "HTTP Status: \(httpResponse.statusCode)")
                guard (200...299).contains(httpResponse.statusCode) else {
                    logError("PDFReaderVM", "Sunucu hatası: \(httpResponse.statusCode)")
                    throw NSError(domain: "Network", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Sunucu hatası: \(httpResponse.statusCode)"])
                }
            }
            
            logDebug("PDFReaderVM", "Veri indirildi", details: "\(data.count) bytes")
            
            // Verify we have valid PDF data
            guard !data.isEmpty else {
                logError("PDFReaderVM", "İndirilen veri boş")
                isLoading = false
                return
            }
            
            guard let pdfDocument = PDFDocument(data: data) else {
                logError("PDFReaderVM", "PDFDocument oluşturulamadı", error: NSError(domain: "PDFKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "PDF verisi okunamadı veya bozuk."]))
                isLoading = false
                return
            }
            
            self.pdfData = data
            logInfo("PDFReaderVM", "PDF yüklendi", details: "\(pdfDocument.pageCount) sayfa")
            guard pdfDocument.pageCount > 0 else {
                logError("PDFReaderVM", "PDF 0 sayfa içeriyor", error: NSError(domain: "PDFKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "PDF dosyası boş görünüyor."]))
                isLoading = false
                return
            }
            
            // Update UI properties on MainActor
            self.document = pdfDocument
            self.totalPages = pdfDocument.pageCount
            self.isLoading = false
            
            // Load annotations in background
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
            
            // Prepare AI Chat in a detached task to avoid blocking MainActor
            // Pass URL to create a separate PDFDocument instance for thread safety
            let fileURL = try await supabaseService.getFileURL(storagePath: fileMetadata.storagePath)
            Task.detached(priority: .background) {
                logInfo("PDFReaderVM", "AI Chat hazırlanıyor...")
                await self.prepareAIChat(url: fileURL, fileId: self.fileMetadata.id)
                logInfo("PDFReaderVM", "AI Chat hazır")
            }
            
        } catch {
            logError("PDFReaderVM", "Doküman yükleme hatası", error: error)
            self.isLoading = false
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
    
    // MARK: - Navigation
    
    func goToPage(_ page: Int) {
        guard page >= 1, page <= totalPages else { return }
        currentPage = page
    }
    
    func nextPage() {
        goToPage(currentPage + 1)
    }
    
    func previousPage() {
        goToPage(currentPage - 1)
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
        
        searchResults = pdfService.search(query: searchQuery, in: doc)
        currentSearchIndex = 0
        
        if let first = searchResults.first {
            goToPage(first.pageNumber)
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
    
    func handleSelection(text: String, rect: CGRect, page: Int) {
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
              let rect = selectionRect,
              let page = selectionPage else { return }
        
        let annotationRect = AnnotationRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: rect.height
        )
        
        let annotation = Annotation(
            fileId: fileMetadata.id,
            pageNumber: page,
            type: type,
            color: color,
            rects: [annotationRect],
            text: text,
            note: note,
            isAiGenerated: isAiGenerated
        )
        
        annotations.append(annotation)
        
        do {
            try await supabaseService.saveAnnotation(annotation)
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
            try await supabaseService.updateAnnotation(id: annotationId, note: note)
            logInfo("PDFReaderVM", "Not güncellendi", details: "ID: \(annotationId)")
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
            try await supabaseService.deleteAnnotation(id: annotationId)
            logInfo("PDFReaderVM", "Annotation silindi", details: "ID: \(annotationId)")
        } catch {
            logError("PDFReaderVM", "Annotation silme hatası", error: error)
        }
    }
    
}
