import Foundation
import Combine
import PDFKit

// MARK: - Chat ViewModel
@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedText: String? // Store text selected in PDF
    @Published var selectedImage: Data?  // Store image selected in PDF (JPEG data)
    @Published var isRAGEnabled = true   // RAG modu aktif mi?
    @Published var isDeepSearchEnabled = false  // Derin Arama (Reranking + Query Expansion)
    @Published var cachedImageMetadata: [PDFImageMetadata] = []  // Dosyadaki görseller

    // MARK: - Smart Suggestions (P4)
    @Published var smartSuggestions: [ChatSuggestion] = []
    @Published var currentPageNumber: Int = 1
    @Published var currentPageText: String?
    @Published var currentSectionTitle: String?
    @Published var currentPageHasTable: Bool = false
    @Published var currentPageHasImage: Bool = false

    // MARK: - Indexleme Durumu (P0 Fix)
    @Published var isDocumentIndexed = false      // Doküman RAG için hazır mı?
    @Published var isIndexing = false             // Şu an indexleniyor mu?
    @Published var indexingProgress: Float = 0    // İndexleme ilerlemesi (0-1)
    @Published var indexingStatus: IndexingStatus = .unknown

    enum IndexingStatus: Equatable {
        case unknown           // Henüz kontrol edilmedi
        case checking          // Kontrol ediliyor
        case notIndexed        // Indexlenmemiş
        case indexing          // Indexleniyor
        case ready             // Hazır
        case failed(String)    // Hata

        var message: String {
            switch self {
            case .unknown: return ""
            case .checking: return "Doküman durumu kontrol ediliyor..."
            case .notIndexed: return "Doküman henüz hazırlanmamış"
            case .indexing: return "Doküman hazırlanıyor..."
            case .ready: return "Doküman hazır"
            case .failed(let error): return "Hata: \(error)"
            }
        }

        var isBlocking: Bool {
            switch self {
            case .checking, .indexing: return true
            default: return false
            }
        }
    }

    // Görsel tarama kontrolü - tekrar taramayı önler
    var imageMetadataLoaded = false
    var imageExtractionInProgress = false

    let geminiService = GeminiService.shared
    let supabaseService = SupabaseService.shared
    let ragService = RAGService.shared
    let imageService = PDFImageService.shared
    let smartSuggestionService = SmartSuggestionService.shared

    // Sayfa referansı algılama regex'i
    let pageReferenceRegex: NSRegularExpression? = {
        do {
            return try NSRegularExpression(
                pattern: #"(?:sayfa|page|sf\.?|s\.?)\s*(\d+)(?:'?\s*(?:deki|daki|teki|taki|ndeki|ndaki))?\s*"# +
                    #"(?:görsel|resim|şekil|grafik|tablo|diyagram|image|figure)"#,
                options: [.caseInsensitive]
            )
        } catch {
            logWarning(
                "ChatViewModel",
                "Sayfa referansı regex oluşturulamadı",
                details: error.localizedDescription
            )
            return nil
        }
    }()

    let fileId: String
    private let fileUUID: UUID?
    weak var pdfDocument: PDFDocument?  // PDF referansı (görsel çıkarma için)

    // MARK: - Smart Suggestions (P4)
    /// Dinamik öneriler - SmartSuggestionService'den alınır
    var currentSuggestions: [ChatSuggestion] {
        if smartSuggestions.isEmpty {
            return SmartSuggestionService.defaultSuggestions
        }
        return smartSuggestions
    }

    /// Sayfa değiştiğinde önerileri güncelle
    func updateSmartSuggestions() {
        smartSuggestions = smartSuggestionService.getSmartSuggestions(
            pageText: currentPageText,
            pageNumber: currentPageNumber,
            sectionTitle: currentSectionTitle,
            hasTable: currentPageHasTable,
            hasImage: currentPageHasImage
        )
        logInfo("ChatViewModel", "Smart suggestions güncellendi: \(smartSuggestions.count) öneri")
    }

    /// Sayfa bağlamını güncelle ve önerileri yenile
    func updatePageContext(
        pageNumber: Int,
        pageText: String?,
        sectionTitle: String? = nil,
        hasTable: Bool = false,
        hasImage: Bool = false
    ) {
        currentPageNumber = pageNumber
        currentPageText = pageText
        currentSectionTitle = sectionTitle
        currentPageHasTable = hasTable
        currentPageHasImage = hasImage
        updateSmartSuggestions()
    }

    private var indexingObserver: AnyCancellable?
    private var progressObserver: AnyCancellable?

    init(fileId: String) {
        self.fileId = fileId
        self.fileUUID = UUID(uuidString: fileId)
        addWelcomeMessage()
        setupIndexingObservers()
    }

    private func addWelcomeMessage() {
        let welcomeText = "Merhaba! Doküman hakkındaki sorularınızı yanıtlamaya hazırım. " +
            "Tablolar, grafikler ve içerik hakkında yardımcı olabilirim."
        let welcome = ChatMessage(
            role: .model,
            text: welcomeText
        )
        messages.append(welcome)
    }

    // MARK: - Indexleme Yönetimi (P0)

    /// RAGService'in indexleme durumunu observe et
    private func setupIndexingObservers() {
        indexingObserver = ragService.$isIndexing
            .combineLatest(ragService.$indexingFileId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] indexing, indexingFileId in
                guard let self = self else { return }

                let wasIndexing = self.isIndexing
                let isIndexingForFile = indexing && self.matchesCurrentFile(indexingFileId)
                self.isIndexing = isIndexingForFile

                if isIndexingForFile {
                    if !wasIndexing {
                        self.indexingProgress = 0
                    }
                    self.indexingStatus = .indexing
                } else if wasIndexing && !isIndexingForFile {
                    self.isDocumentIndexed = true
                    self.indexingProgress = max(self.indexingProgress, 1.0)
                    self.indexingStatus = .ready
                    logInfo("ChatViewModel", "Doküman indexleme tamamlandı ✅ (observer)")
                }
            }

        progressObserver = ragService.$indexingProgress
            .combineLatest(ragService.$indexingFileId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress, indexingFileId in
                guard let self = self else { return }
                guard self.matchesCurrentFile(indexingFileId) else { return }
                self.indexingProgress = max(self.indexingProgress, progress)
            }
    }

    /// Chat açıldığında doküman indexleme durumunu kontrol et
    func checkAndPrepareDocument(pdfText: String? = nil) async {
        guard let fileUUID = fileUUID else {
            indexingStatus = .failed("Geçersiz dosya ID")
            return
        }

        indexingStatus = .checking
        logInfo("ChatViewModel", "Doküman indexleme durumu kontrol ediliyor...")

        // Önce mevcut index durumunu kontrol et
        let indexed = await ragService.isDocumentIndexed(fileId: fileUUID)

        if indexed {
            isDocumentIndexed = true
            indexingStatus = .ready
            logInfo("ChatViewModel", "Doküman zaten indexlenmiş ✅")
            return
        }

        // Indexlenmemişse ve metin varsa indexle
        if let text = pdfText, !text.isEmpty {
            indexingStatus = .indexing
            logInfo("ChatViewModel", "Doküman indexleniyor...")

            do {
                try await ragService.indexDocument(text: text, fileId: fileUUID)
                isDocumentIndexed = true
                indexingStatus = .ready
                logInfo("ChatViewModel", "Doküman indexleme tamamlandı ✅")
            } catch {
                indexingStatus = .failed(error.localizedDescription)
                logError("ChatViewModel", "Doküman indexleme hatası", error: error)
            }
        } else {
            // Metin yok - PDF'den çekilmesi gerekiyor
            indexingStatus = .notIndexed
            logWarning("ChatViewModel", "PDF metni yok - indexleme için metin gerekli")
        }
    }

    /// Indexleme durumunu yenile (kullanıcı butona tıklarsa)
    func refreshIndexingStatus() async {
        guard let fileUUID = fileUUID else { return }

        indexingStatus = .checking
        let indexed = await ragService.isDocumentIndexed(fileId: fileUUID)
        isDocumentIndexed = indexed
        indexingStatus = indexed ? .ready : .notIndexed
    }

    private func matchesCurrentFile(_ indexingFileId: UUID?) -> Bool {
        guard let fileUUID = fileUUID else { return false }
        return fileUUID == indexingFileId
    }

    /// Kullanıcı mesaj gönderebilir mi? (Indexleme engelliyor mu?)
    var canSendMessage: Bool {
        !isLoading && !indexingStatus.isBlocking
    }

    /// Indexleme durumuna göre uyarı mesajı göster
    var indexingWarningMessage: String? {
        switch indexingStatus {
        case .checking:
            return "Doküman kontrol ediliyor, lütfen bekleyin..."
        case .indexing:
            let percent = Int(indexingProgress * 100)
            return "Doküman hazırlanıyor... %\(percent)"
        case .notIndexed:
            return "⚠️ Doküman henüz hazırlanmamış. Sorularınız genel yanıtlarla cevaplanacak."
        case .failed(let error):
            return "❌ Hata: \(error)"
        default:
            return nil
        }
    }
}
