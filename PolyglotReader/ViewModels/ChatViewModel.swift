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

    private let geminiService = GeminiService.shared
    private let supabaseService = SupabaseService.shared
    private let ragService = RAGService.shared
    private let imageExtractor = PDFImageExtractor.shared
    
    // Sayfa referansı algılama regex'i
    private let pageReferenceRegex = try? NSRegularExpression(
        pattern: #"(?:sayfa|page|sf\.?|s\.?)\s*(\d+)(?:'?\s*(?:deki|daki|teki|taki|ndeki|ndaki))?\s*(?:görsel|resim|şekil|grafik|tablo|diyagram|image|figure|chart|table)"#,
        options: [.caseInsensitive]
    )
    
    let fileId: String
    weak var pdfDocument: PDFDocument?  // PDF referansı (görsel çıkarma için)
    
    static let suggestions = [
        ChatSuggestion(label: "Dokümanı Özetle", icon: "doc.text", prompt: "Lütfen tüm dokümanın kısa bir özetini çıkar, ana hedefleri ve sonuçları vurgula."),
        ChatSuggestion(label: "Grafikleri Analiz Et", icon: "chart.bar", prompt: "Dokümandaki görsel öğelere bak. Gördüğün grafik ve tabloları yorumla."),
        ChatSuggestion(label: "Tarihleri Çıkar", icon: "calendar", prompt: "Dokümanda geçen tüm önemli tarihleri çıkar ve bağlamlarıyla birlikte bir tabloda sun."),
        ChatSuggestion(label: "Ana Noktalar", icon: "lightbulb", prompt: "Bu dosyadan çıkarılabilecek en önemli 5 nokta nedir?")
    ]
    
    init(fileId: String) {
        self.fileId = fileId
        addWelcomeMessage()
    }
    
    private func addWelcomeMessage() {
        let welcome = ChatMessage(
            role: .model,
            text: "Merhaba! Doküman hakkındaki sorularınızı yanıtlamaya hazırım. Tablolar, grafikler ve içerik hakkında yardımcı olabilirim."
        )
        messages.append(welcome)
    }
    
    // MARK: - Send Message (RAG Enhanced + Image Aware)
    
    func sendMessage(_ text: String? = nil) async {
        // Prevent re-entrancy / double submission
        guard !isLoading else { return }
        
        let textToSend = text ?? inputText
        guard !textToSend.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        let userText: String
        if let context = selectedText {
            userText = "Bağlam: \"\(context)\"\n\n\(textToSend)"
            selectedText = nil
        } else {
            userText = textToSend
        }
        
        // Clear input text if we used it
        if text == nil {
            inputText = ""
        }
        
        // Sayfa görsel referansı algıla
        let pageImageReference = detectPageImageReference(in: userText)
        
        let userMessage = ChatMessage(role: .user, text: userText)
        messages.append(userMessage)
        
        // Save to Supabase in background
        Task {
            try? await supabaseService.saveChatMessage(fileId: fileId, role: "user", content: userText)
        }
        
        isLoading = true
        
        do {
            // Eğer sayfa görseli referansı varsa, özel işleme yap
            if let pageRef = pageImageReference {
                await handlePageImageQuery(userText: userText, pageNumber: pageRef)
                return
            }
            
            // Initial empty message for streaming
            let aiMessageId = UUID().uuidString
            let initialAiMessage = ChatMessage(id: aiMessageId, role: .model, text: "")
            messages.append(initialAiMessage)
            
            var fullResponse = ""
            
            // RAG modu: Profesyonel hybrid search + reranking pipeline
            let stream: AsyncThrowingStream<String, Error>

            if isRAGEnabled, let fileUUID = UUID(uuidString: fileId) {
                logDebug("ChatViewModel", "RAG sorgusu başlatılıyor", 
                        details: "FileID: \(fileUUID.uuidString), Query: \(userText.prefix(50))...")
                
                // Yeni RAG Pipeline: Hybrid Search -> Token-Aware Context
                // Derin Arama ayarına göre reranking ve query expansion aktif edilir
                let (ragContext, chunks) = try await ragService.performRAGQuery(
                    query: userText,
                    fileId: fileUUID,
                    enableRerank: isDeepSearchEnabled,         // Derin Arama ayarına bağlı
                    enableQueryExpansion: isDeepSearchEnabled  // Derin Arama ayarına bağlı
                )

                // Görsel caption'larında da ara
                let imageMatches = try? await searchImageCaptions(query: userText, fileId: fileUUID)

                if !ragContext.isEmpty || !(imageMatches?.isEmpty ?? true) {
                    var context = ragContext

                    // Görsel caption'larını da context'e ekle
                    if let images = imageMatches, !images.isEmpty {
                        context += "\n\n📷 İlgili Görseller:\n"
                        for image in images {
                            context += "- Sayfa \(image.pageNumber): \(image.caption ?? "Açıklama yok")\n"
                        }
                    }

                    logInfo("ChatViewModel", "RAG context oluşturuldu",
                            details: "\(chunks.count) chunk, \(imageMatches?.count ?? 0) görsel")
                    stream = try await geminiService.sendMessageStreamWithContext(userText, context: context)
                } else {
                    // Chunk bulunamadı, normal modda devam et
                    logWarning("ChatViewModel", "RAG chunk bulunamadı, legacy mod kullanılıyor")
                    stream = try await geminiService.sendMessageStream(userText)
                }
            } else {
                // Legacy mod
                stream = try await geminiService.sendMessageStream(userText)
            }
            
            for try await chunk in stream {
                fullResponse += chunk
                
                // Update the last message (which is our AI message)
                if let index = messages.firstIndex(where: { $0.id == aiMessageId }) {
                    messages[index] = ChatMessage(id: aiMessageId, role: .model, text: fullResponse)
                    
                    // Hide loading indicator once we start receiving text
                    if !fullResponse.isEmpty {
                        isLoading = false
                    }
                }
            }
            
            // Ensure loading is false when done
            isLoading = false
            
            // Save to Supabase in background
            Task {
                try? await supabaseService.saveChatMessage(fileId: fileId, role: "model", content: fullResponse)
            }
            
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            
            // Remove the empty/partial message if it failed completely or add error indication?
            // For now, allow partial response to stay and add error message
            let errorMsg = ChatMessage(role: .model, text: "Üzgünüm, bir hata oluştu: \(error.localizedDescription)")
            messages.append(errorMsg)
        }
    }
    
    func sendSuggestion(_ prompt: String) async {
        inputText = prompt
        await sendMessage()
    }
    
    // MARK: - Send Message With Image
    
    /// Görsel ile birlikte soru gönder
    func sendMessageWithImage(_ text: String? = nil) async {
        // Prevent re-entrancy
        guard !isLoading else { return }
        
        let textToSend = text ?? inputText
        guard !textToSend.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard let imageData = selectedImage else {
            // Görsel yoksa normal mesaj gönder
            await sendMessage(text)
            return
        }
        
        // Clear input and image
        if text == nil {
            inputText = ""
        }
        selectedImage = nil
        
        let userMessage = ChatMessage(role: .user, text: "📷 [Görsel] \(textToSend)")
        messages.append(userMessage)
        
        // Save to Supabase in background
        Task {
            try? await supabaseService.saveChatMessage(fileId: fileId, role: "user", content: textToSend)
        }
        
        isLoading = true
        
        do {
            let response = try await geminiService.askAboutImage(imageData, question: textToSend)
            
            let aiMessage = ChatMessage(role: .model, text: response)
            messages.append(aiMessage)
            
            isLoading = false
            
            // Save to Supabase in background
            Task {
                try? await supabaseService.saveChatMessage(fileId: fileId, role: "model", content: response)
            }
            
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
            
            let errorMsg = ChatMessage(role: .model, text: "Üzgünüm, görsel analiz edilirken bir hata oluştu: \(error.localizedDescription)")
            messages.append(errorMsg)
        }
    }
    
    // MARK: - Load History
    
    func loadHistory() async {
        do {
            let history = try await supabaseService.getChatHistory(fileId: fileId)
            if !history.isEmpty {
                messages = history
            }
        } catch {
            logWarning("ChatViewModel", "Chat geçmişi yüklenemedi", details: error.localizedDescription)
        }
    }
    
    // MARK: - Image Metadata Management
    
    /// Dosyadaki görsel metadata'larını yükle veya oluştur
    func loadImageMetadata(document: PDFDocument) async {
        self.pdfDocument = document
        
        guard let fileUUID = UUID(uuidString: fileId) else { return }
        
        do {
            // Önce cache'den yükle
            let existing = try await supabaseService.getImageMetadata(fileId: fileUUID)
            
            if !existing.isEmpty {
                cachedImageMetadata = existing
                logInfo("ChatViewModel", "Görsel metadata yüklendi", details: "\(existing.count) adet")
            } else {
                // Henüz taranmamış - arka planda tara
                Task.detached(priority: .background) {
                    await self.extractAndSaveImageMetadata(document: document, fileId: fileUUID)
                }
            }
        } catch {
            logWarning("ChatViewModel", "Görsel metadata yüklenemedi", details: error.localizedDescription)
        }
    }
    
    /// PDF'deki görselleri tara ve kaydet
    private func extractAndSaveImageMetadata(document: PDFDocument, fileId: UUID) async {
        let images = await imageExtractor.extractAllImages(from: document, fileId: fileId)
        
        guard !images.isEmpty else { return }
        
        do {
            try await supabaseService.saveImageMetadata(images)
            await MainActor.run {
                self.cachedImageMetadata = images
            }
            logInfo("ChatViewModel", "Görsel metadata kaydedildi", details: "\(images.count) adet")
        } catch {
            logWarning("ChatViewModel", "Görsel metadata kaydedilemedi", details: error.localizedDescription)
        }
    }
    
    // MARK: - Page Image Reference Detection
    
    /// Mesajda sayfa görseli referansı var mı kontrol et
    /// Örnek: "sayfa 5'teki görseli açıkla", "3. sayfadaki tabloyu analiz et"
    private func detectPageImageReference(in text: String) -> Int? {
        guard let regex = pageReferenceRegex else { return nil }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        
        if let match = regex.firstMatch(in: text, options: [], range: range),
           let pageRange = Range(match.range(at: 1), in: text),
           let pageNumber = Int(text[pageRange]) {
            logInfo("ChatViewModel", "Sayfa görsel referansı algılandı", details: "Sayfa \(pageNumber)")
            return pageNumber
        }
        
        return nil
    }
    
    /// Sayfa görseli sorgusunu işle
    private func handlePageImageQuery(userText: String, pageNumber: Int) async {
        guard let document = pdfDocument,
              let fileUUID = UUID(uuidString: fileId),
              pageNumber > 0,
              pageNumber <= document.pageCount else {
            let errorMsg = ChatMessage(role: .model, text: "Belirtilen sayfa bulunamadı.")
            messages.append(errorMsg)
            isLoading = false
            return
        }
        
        do {
            // Sayfadaki görselleri getir
            var pageImages = cachedImageMetadata.filter { $0.pageNumber == pageNumber }
            
            // Cache'de yoksa tespit et
            if pageImages.isEmpty, let page = document.page(at: pageNumber - 1) {
                pageImages = await imageExtractor.extractImagesFromPage(page, pageNumber: pageNumber, fileId: fileUUID)
            }
            
            guard !pageImages.isEmpty else {
                let noImageMsg = ChatMessage(
                    role: .model, 
                    text: "Sayfa \(pageNumber)'de tespit edilebilen bir görsel bulunamadı. Sayfada metin dışında görsel içerik olmayabilir veya görsel formatı desteklenmiyor olabilir."
                )
                messages.append(noImageMsg)
                isLoading = false
                return
            }
            
            // Görselleri render et ve AI'a gönder
            var imagesWithData: [(data: Data, caption: String?)] = []
            
            for imageMetadata in pageImages {
                guard let bounds = imageMetadata.bounds,
                      let page = document.page(at: pageNumber - 1),
                      let renderedImage = imageExtractor.renderRegionFullSize(rect: bounds.cgRect, in: page),
                      let jpegData = renderedImage.jpegData(compressionQuality: 0.85) else {
                    continue
                }
                
                imagesWithData.append((data: jpegData, caption: imageMetadata.caption))
            }
            
            guard !imagesWithData.isEmpty else {
                let errorMsg = ChatMessage(role: .model, text: "Sayfa \(pageNumber)'deki görseller işlenemedi.")
                messages.append(errorMsg)
                isLoading = false
                return
            }
            
            // AI'a sayfa görselleri ile soru sor
            let response = try await geminiService.askWithPageImages(
                userText,
                images: imagesWithData,
                pageNumber: pageNumber
            )
            
            let aiMessage = ChatMessage(role: .model, text: response)
            messages.append(aiMessage)
            
            isLoading = false
            
            // Kaydet
            Task {
                try? await supabaseService.saveChatMessage(fileId: fileId, role: "model", content: response)
            }
            
            // Lazy caption oluştur (henüz analiz edilmemiş görseller için)
            Task.detached(priority: .background) {
                await self.lazyAnalyzePageImages(pageImages, document: document, fileId: fileUUID)
            }
            
        } catch {
            isLoading = false
            let errorMsg = ChatMessage(role: .model, text: "Görsel analizi sırasında hata oluştu: \(error.localizedDescription)")
            messages.append(errorMsg)
        }
    }
    
    /// Henüz analiz edilmemiş görselleri arka planda analiz et
    private func lazyAnalyzePageImages(_ images: [PDFImageMetadata], document: PDFDocument, fileId: UUID) async {
        let unanalyzed = images.filter { !$0.isAnalyzed }
        guard !unanalyzed.isEmpty else { return }
        
        var requests: [ImageAnalysisRequest] = []
        
        for image in unanalyzed {
            guard let bounds = image.bounds,
                  let page = document.page(at: image.pageNumber - 1),
                  let renderedImage = imageExtractor.renderRegionFullSize(rect: bounds.cgRect, in: page),
                  let jpegData = renderedImage.jpegData(compressionQuality: 0.8) else {
                continue
            }
            
            // Çevredeki metni context olarak al
            let contextRect = bounds.cgRect.insetBy(dx: -50, dy: -50)
            let context = page.selection(for: contextRect)?.string
            
            requests.append(ImageAnalysisRequest(
                imageId: image.id,
                imageData: jpegData,
                pageNumber: image.pageNumber,
                context: context
            ))
        }
        
        let results = await geminiService.batchAnalyzeImages(requests)
        
        // Caption'ları kaydet
        for result in results {
            try? await supabaseService.updateImageCaption(
                imageId: result.imageId,
                caption: result.caption,
                embedding: result.captionEmbedding
            )
        }
        
        // Cache'i güncelle
        await MainActor.run {
            for result in results {
                if let index = cachedImageMetadata.firstIndex(where: { $0.id == result.imageId }) {
                    cachedImageMetadata[index].caption = result.caption
                    cachedImageMetadata[index].analyzedAt = result.analyzedAt
                }
            }
        }
    }
    
    /// Görsel caption'larında arama (RAG hibrit arama için)
    private func searchImageCaptions(query: String, fileId: UUID) async throws -> [PDFImageMetadata] {
        let embedding = try await ragService.createEmbedding(for: query)
        return try await supabaseService.searchImageCaptions(
            embedding: embedding,
            fileId: fileId,
            limit: 3,
            threshold: 0.6
        )
    }
}

// MARK: - Chat Suggestion
struct ChatSuggestion: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let prompt: String
}
