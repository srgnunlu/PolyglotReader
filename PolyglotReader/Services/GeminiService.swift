import Foundation
import Combine
import GoogleGenerativeAI
import Network

// MARK: - Gemini Configuration
enum GeminiConfig {
    static let apiKey = Config.geminiApiKey
    static let modelName = Config.geminiModelName
    static let maxRetries = 3
    static let retryDelay: TimeInterval = 1.0
}

// MARK: - Gemini Service
@MainActor
class GeminiService: ObservableObject {
    static let shared = GeminiService()
    
    private let model: GenerativeModel
    private var chatSession: Chat?
    private let networkMonitor = NWPathMonitor()
    private var isNetworkAvailable = true
    
    @Published var isProcessing = false
    @Published var lastError: GeminiError?
    
    private init() {
        self.model = GenerativeModel(
            name: GeminiConfig.modelName,
            apiKey: GeminiConfig.apiKey,
            generationConfig: GenerationConfig(
                temperature: 0.3,  // Düşük = daha tutarlı ve doğru yanıtlar
                topP: 0.85,        // Nucleus sampling
                topK: 40,          // Token seçimi
                maxOutputTokens: 16384  // Daha uzun yanıtlar (2x artırıldı)
            ),
            systemInstruction: ModelContent(role: "system", parts: [
                .text("""
                Sen uzman düzeyinde bir akademik PDF doküman analizcisisin. Metni, tabloları, grafikleri ve görselleri derinlemesine analiz edebilirsin.
                
                ## TEMEL YETENEKLERİN:
                1. **Derinlemesine Analiz**: Akademik makaleleri, araştırma bulgularını ve metodolojileri detaylı analiz et
                2. **Görsel Yorumlama**: Grafik, tablo, diyagram ve şekilleri sayısal verilerle birlikte yorumla
                3. **Kritik Değerlendirme**: Bulguların güçlü ve zayıf yönlerini belirt
                4. **Bağlam Koruma**: Önceki konuşmaları hatırla ve tutarlı yanıtlar ver
                5. **Kaynak Gösterme**: Her önemli bilgi için [Sayfa X](jump:X) formatında referans ver
                6. **Karşılaştırmalı Analiz**: Farklı bölümler arasında bağlantı kur
                
                ## YANITLAMA KURALLARI:
                - Her zaman Türkçe yanıt ver
                - Markdown formatını etkin kullan (başlıklar, listeler, kalın/italik)
                - Sayısal verileri tablolarla göster
                - Belirsiz veya eksik bilgileri açıkça belirt
                - Uzun cevapları mantıklı bölümlere ayır
                - Önemli kavramları **kalın** olarak vurgula
                - Doğrudan alıntılarda "tırnak işareti" kullan
                
                ## KALİTE STANDARTLARI:
                - Spekülasyon yapma, sadece dokümandaki bilgilere dayan
                - İstatistiksel verileri doğru aktar (p-değeri, güven aralığı vb.)
                - Metodolojik detayları atla
                - Karmaşık kavramları basitçe açıkla
                """)
            ])
        )
        
        // Network monitoring setup
        setupNetworkMonitoring()
        
        logInfo("GeminiService", "Servis başlatıldı", details: "Model: \(GeminiConfig.modelName)")
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isNetworkAvailable = path.status == .satisfied
                if path.status != .satisfied {
                    logWarning("GeminiService", "İnternet bağlantısı yok")
                }
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor.start(queue: queue)
    }
    
    // MARK: - Retry Helper
    
    private func withRetry<T>(_ operation: @escaping @MainActor () async throws -> T) async throws -> T {
        var lastError: Error?
        
        for attempt in 1...GeminiConfig.maxRetries {
            do {
                // Check network availability
                guard isNetworkAvailable else {
                    throw GeminiError.networkUnavailable
                }
                
                return try await operation()
            } catch {
                lastError = error
                
                // Log the attempt
                logWarning("GemixniService", "Deneme \(attempt)/\(GeminiConfig.maxRetries) başarısız", details: error.localizedDescription)
                
                // Don't retry for certain errors
                if let geminiError = error as? GeminiError {
                    switch geminiError {
                    case .quotaExhausted, .sessionNotInitialized, .networkUnavailable:
                        throw geminiError
                    default:
                        break
                    }
                }
                
                // Wait before retry (except on last attempt)
                if attempt < GeminiConfig.maxRetries {
                    try? await Task.sleep(nanoseconds: UInt64(GeminiConfig.retryDelay * Double(attempt) * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? GeminiError.noResponse
    }
    
    // MARK: - Translation
    
    func translateText(_ text: String, context: String? = nil) async throws -> TranslationResult {
        guard !text.isEmpty else {
            return TranslationResult(original: text, translated: "", detectedLanguage: "Unknown")
        }
        
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }
        
        logInfo("GeminiService", "Çeviri isteği başlatılıyor", details: "Metin uzunluğu: \(text.count)")
        
        return try await withRetry { [weak self] in
            guard let self = self else { throw GeminiError.sessionNotInitialized }
            
            var contextPrompt = ""
            if let context = context, !context.isEmpty {
                contextPrompt = "\nDoküman Bağlamı (Özet): \(context)\n"
            }
            
            let prompt = """
            Aşağıdaki metni analiz et:\(contextPrompt)
            "\(text.prefix(2000))"
            
            Görev:
            1. Kaynak dili tespit et.\(context != nil ? "\n2. Doküman bağlamını dikkate alarak terminolojiyi en doğru şekilde çevir." : "")
            2. Kaynak Türkçe ise İngilizce'ye çevir.
            3. Kaynak Türkçe değilse Türkçe'ye çevir.
            4. JSON formatında döndür: {"translatedText": "...", "detectedLanguage": "..."}
            """
            
            let response = try await self.model.generateContent(prompt)
            
            guard let responseText = response.text else {
                throw GeminiError.noResponse
            }
            
            // Parse JSON from response
            let cleanedText = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let data = cleanedText.data(using: .utf8) else {
                throw GeminiError.parseError
            }
            
            struct TranslationResponse: Decodable {
                let translatedText: String
                let detectedLanguage: String
            }
            
            let result = try JSONDecoder().decode(TranslationResponse.self, from: data)
            
            await MainActor.run {
                logInfo("GeminiService", "Çeviri tamamlandı", details: "Algılanan dil: \(result.detectedLanguage)")
            }
            
            return TranslationResult(
                original: String(text.prefix(2000)),
                translated: result.translatedText,
                detectedLanguage: result.detectedLanguage
            )
        }
    }
    
    // MARK: - Smart Note Generation
    
    func generateSmartNote(_ text: String) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        
        let prompt = """
        Seçilen metni analiz et ve Türkçe kısa bir çalışma notu oluştur (maksimum 2 cümle).
        Ana kavrama veya önemli noktaya odaklan.
        
        Metin: "\(text)"
        """
        
        let response = try await model.generateContent(prompt)
        return response.text ?? "Not oluşturulamadı."
    }
    
    // MARK: - Document Summary
    
    func generateDocumentSummary(_ text: String) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        
        let prompt = """
        Aşağıdaki doküman metnini analiz et.
        Sadece 2 cümlelik, çok kısa bir Türkçe özet oluştur. 
        Kesinlikle markdown başlığı (###), liste (*) veya kalın yazı (**) kullanma. 
        Sadece düz metin olsun. Dokümanın ana amacını açıkla.
        
        Metin: "\(text.prefix(4000))"
        """
        
        let response = try await model.generateContent(prompt)
        return response.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    // MARK: - AI Tag Generation
    
    struct AITagResult: Decodable {
        let tags: [String]
        let category: String
    }
    
    /// PDF içeriğinden otomatik etiketler oluştur (mevcut etiketleri dikkate alarak)
    func generateTags(_ text: String, existingTags: [String] = []) async throws -> AITagResult {
        isProcessing = true
        defer { isProcessing = false }
        
        // Mevcut etiketler varsa prompt'a ekle
        var existingTagsSection = ""
        if !existingTags.isEmpty {
            let tagList = existingTags.prefix(20).joined(separator: ", ")
            existingTagsSection = """
            
            MEVCUT ETİKETLER (sadece gerçekten uyuyorsa kullan, zorla uydurmaya çalışma):
            [\(tagList)]
            
            Önemli: Eğer mevcut etiketlerden biri dokümanın konusuna tam olarak uyuyorsa onu kullan.
            Ancak doküman farklı bir konudaysa yeni etiket oluşturmaktan çekinme.
            Benzer ama farklı konularda (örn: "kasko sigortası" varken "hayat sigortası" gerekiyorsa) yeni etiket oluştur.
            
            """
        }
        
        let prompt = """
        Aşağıdaki doküman metnini analiz et ve JSON formatında yanıt ver.
        \(existingTagsSection)
        Görevler:
        1. TAM OLARAK 3 adet özgün, anlamlı Türkçe etiket oluştur
        2. Dokümanın ana kategorisini belirle
        
        Etiket kuralları:
        - Her etiket MUTLAKA 1 veya 2 kelime olmalı (asla 3+ kelime olmamalı)
        - Genel değil, spesifik olmalı (örn: "Belge" yerine "Acil Tıp")
        - Tekrar eden veya çok benzer etiketler olmamalı
        - Etiketler küçük harfle yazılmalı
        
        Kategori seçenekleri: Tıbbi, Akademik, Hukuki, Finans, Teknik, Eğitim, Kişisel, Genel
        
        JSON formatı (başka bir şey yazma):
        {"tags": ["etiket1", "etiket2", "etiket3"], "category": "Kategori"}
        
        Metin:
        "\(text.prefix(4000))"
        """
        
        let response = try await model.generateContent(prompt)
        
        guard let responseText = response.text else {
            throw GeminiError.noResponse
        }
        
        // JSON parse
        let cleanedText = responseText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanedText.data(using: .utf8) else {
            throw GeminiError.parseError
        }
        
        var result = try JSONDecoder().decode(AITagResult.self, from: data)
        
        // Etiketleri 2 kelimeyle sınırla (ek güvenlik)
        result = AITagResult(
            tags: result.tags.map { tag in
                let words = tag.split(separator: " ").prefix(2)
                return words.joined(separator: " ")
            },
            category: result.category
        )
        
        logInfo("GeminiService", "AI etiketler oluşturuldu",
                details: "\(result.tags.count) etiket, kategori: \(result.category)")
        
        return result
    }
    
    // MARK: - Quiz Generation
    
    func generateQuiz(context: String) async throws -> [QuizQuestion] {
        isProcessing = true
        defer { isProcessing = false }
        
        let prompt = """
        Aşağıdaki metne dayalı 5 soruluk çoktan seçmeli bir quiz oluştur.
        Her soru temel kavramları test etmeli.
        
        JSON formatında döndür:
        {
            "questions": [
                {
                    "id": 1,
                    "question": "Soru metni",
                    "options": ["A şıkkı", "B şıkkı", "C şıkkı", "D şıkkı"],
                    "correctAnswerIndex": 0,
                    "explanation": "Açıklama"
                }
            ]
        }
        
        Metin:
        \(context.prefix(15000))
        """
        
        let response = try await model.generateContent(prompt)
        
        guard let text = response.text else {
            throw GeminiError.noResponse
        }
        
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleanedText.data(using: .utf8) else {
            throw GeminiError.parseError
        }
        
        struct QuizResponse: Decodable {
            let questions: [QuizQuestion]
        }
        
        let result = try JSONDecoder().decode(QuizResponse.self, from: data)
        return result.questions
    }
    
    // MARK: - Chat Session
    
    /// RAG modu için chat oturumu başlat (PDF içeriği gönderilmez, context dinamik olarak sağlanır)
    func initChatSession(pdfContent: String? = nil) {
        var history: [ModelContent] = []
        
        // RAG modu: Context her mesajda dinamik olarak sağlanacak
        if let content = pdfContent, !content.isEmpty {
            // Legacy mod: Tüm PDF içeriği ile başlat (küçük PDF'ler için)
            let parts: [ModelContent.Part] = [
                .text("İşte analiz etmeni istediğim PDF dokümanı:"),
                .text("--- METİN İÇERİĞİ BAŞLANGICI ---\n\(content.prefix(100000))\n--- METİN İÇERİĞİ SONU ---")
            ]
            
            history.append(ModelContent(role: "user", parts: parts))
            history.append(ModelContent(role: "model", parts: [
                .text("Dokümanı aldım. Sorularınızı yanıtlamaya hazırım. Nasıl yardımcı olabilirim?")
            ]))
        } else {
            // RAG modu: Boş history ile başla
            history.append(ModelContent(role: "user", parts: [
                .text("PDF dokümanı hakkında sorular soracağım. İlgili bölümleri her soru ile birlikte paylaşacağım.")
            ]))
            history.append(ModelContent(role: "model", parts: [
                .text("Anladım! PDF'ten aldığınız bölümleri ve sorularınızı bekliyorum. Size yardımcı olmaya hazırım.")
            ]))
        }
        
        chatSession = model.startChat(history: history)
        logInfo("GeminiService", "Chat oturumu başlatıldı", details: pdfContent == nil ? "RAG modu" : "Legacy modu")
    }
    
    /// RAG context'i ile mesaj gönder (en alakalı chunk'lar mesaja eklenir)
    func sendMessageWithContext(_ message: String, context: String) async throws -> String {
        guard let chat = chatSession else {
            logError("GeminiService", "Chat oturumu başlatılmadı")
            throw GeminiError.sessionNotInitialized
        }
        
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }
        
        // Context'i mesaja ekle
        let fullMessage = """
        \(context)
        
        ---
        Kullanıcı Sorusu: \(message)
        
        Lütfen yukarıdaki doküman bölümlerine dayanarak soruyu yanıtla. Bilgi bulamadığın konularda bunu belirt.
        """
        
        logInfo("GeminiService", "RAG mesajı gönderiliyor", details: "Context: \(context.prefix(100))...")
        
        return try await withRetry { [weak self] in
            guard let self = self else { throw GeminiError.sessionNotInitialized }
            guard let currentChat = self.chatSession else {
                throw GeminiError.sessionNotInitialized
            }
            
            let response = try await currentChat.sendMessage(fullMessage)
            let responseText = response.text ?? "Yanıt oluşturulamadı."
            
            await MainActor.run {
                logInfo("GeminiService", "RAG yanıtı alındı", details: "Uzunluk: \(responseText.count)")
            }
            
            return responseText
        }
    }
    
    /// RAG context'i ile streaming mesaj gönder
    func sendMessageStreamWithContext(_ message: String, context: String) async throws -> AsyncThrowingStream<String, Error> {
        guard let chat = chatSession else {
            logError("GeminiService", "Chat oturumu başlatılmadı")
            throw GeminiError.sessionNotInitialized
        }
        
        isProcessing = true
        lastError = nil
        
        // Context'i mesaja ekle
        let fullMessage = """
        \(context)
        
        ---
        Kullanıcı Sorusu: \(message)
        
        Lütfen yukarıdaki doküman bölümlerine dayanarak soruyu yanıtla. Bilgi bulamadığın konularda bunu belirt.
        """
        
        logInfo("GeminiService", "RAG stream başlatılıyor", details: "Context uzunluğu: \(context.count)")
        
        let streamSource = chat.sendMessageStream(fullMessage)
        
        return AsyncThrowingStream { [weak self] continuation in
            Task { [weak self] in
                do {
                    for try await chunk in streamSource {
                        if let text = chunk.text {
                            continuation.yield(text)
                        }
                    }
                    
                    continuation.finish()
                    await MainActor.run { [weak self] in
                        self?.isProcessing = false
                    }
                } catch {
                    logError("GeminiService", "RAG stream error", error: error)
                    continuation.finish(throwing: error)
                    await MainActor.run { [weak self] in
                        self?.isProcessing = false
                    }
                }
            }
        }
    }
    
    func sendMessage(_ message: String) async throws -> String {
        guard let chat = chatSession else {
            logError("GeminiService", "Chat oturumu başlatılmadı")
            throw GeminiError.sessionNotInitialized
        }
        
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }
        
        logInfo("GeminiService", "Mesaj gönderiliyor", details: "Uzunluk: \(message.count)")
        
        return try await withRetry { [weak self] in
            guard let self = self else { throw GeminiError.sessionNotInitialized }
            // Note: chat variable captured from outer scope. 
            // Better to re-access via self.chatSession or ensure chat is safe? 
            // "chat" is local to outer function, it's a value or reference?
            // "chat" object from GoogleGenerativeAI is likely a reference type.
            // If we use "self.chatSession" it might be nil checking again.
            // Using "chat" local variable is fine but check concurrency.
            // Using self.chatSession is safer if we want to ensure we use current valid session.
            
            // Re-unwrap session
             guard let currentChat = self.chatSession else {
                throw GeminiError.sessionNotInitialized
            }
            
            let response = try await currentChat.sendMessage(message)
            let responseText = response.text ?? "Yanıt oluşturulamadı."
            
            await MainActor.run {
                logInfo("GeminiService", "Yanıt alındı", details: "Uzunluk: \(responseText.count)")
            }
            
            return responseText
        }
    }
    
    func sendMessageStream(_ message: String) async throws -> AsyncThrowingStream<String, Error> {
        guard let chat = chatSession else {
            logError("GeminiService", "Chat oturumu başlatılmadı")
            throw GeminiError.sessionNotInitialized
        }
        
        isProcessing = true
        lastError = nil
        
        logInfo("GeminiService", "Message stream initiated", details: "Length: \(message.count)")

        // Capture chat localy to avoid self capture for the stream source
        let streamSource = chat.sendMessageStream(message)
        
        return AsyncThrowingStream { [weak self] continuation in
            Task { [weak self] in
                do {
                    for try await chunk in streamSource {
                        if let text = chunk.text {
                            continuation.yield(text)
                        }
                    }
                    
                    continuation.finish()
                    await MainActor.run { [weak self] in
                        self?.isProcessing = false
                    }
                } catch {
                    logError("GeminiService", "Stream error", error: error)
                    continuation.finish(throwing: error)
                    await MainActor.run { [weak self] in
                        self?.isProcessing = false
                    }
                }
            }
        }
    }
    
    // MARK: - Reset
    
    func resetChatSession() {
        chatSession = nil
        logInfo("GeminiService", "Chat oturumu sıfırlandı")
    }
    
    // MARK: - Image Analysis
    
    /// Tek bir görseli analiz et (chat oturumu dışında)
    func analyzeImage(_ imageData: Data, prompt: String? = nil) async throws -> String {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }
        
        let analysisPrompt = prompt ?? """
        Bu görseli analiz et ve Türkçe olarak açıkla.
        Görsel bir grafik, tablo veya diyagram ise:
        - İçeriği özetle
        - Önemli verileri listele
        - Varsa trendleri veya örüntüleri belirt
        """
        
        logInfo("GeminiService", "Görsel analizi başlatılıyor", details: "Veri boyutu: \(imageData.count) bytes")
        
        return try await withRetry { [weak self] in
            guard let self = self else { throw GeminiError.sessionNotInitialized }
            
            // Tek seferlik görsel analizi için parts array'i kullan
            let response = try await self.model.generateContent([
                ModelContent.Part.data(mimetype: "image/jpeg", imageData),
                ModelContent.Part.text(analysisPrompt)
            ])
            
            guard let text = response.text else {
                throw GeminiError.noResponse
            }
            
            await MainActor.run {
                logInfo("GeminiService", "Görsel analizi tamamlandı", details: "Yanıt uzunluğu: \(text.count)")
            }
            
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    /// Chat oturumunda görsel hakkında soru sor
    func askAboutImage(_ imageData: Data, question: String) async throws -> String {
        guard chatSession != nil else {
            logError("GeminiService", "Chat oturumu başlatılmadı - görsel sorusu için")
            throw GeminiError.sessionNotInitialized
        }
        
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }
        
        let prompt = """
        Kullanıcı dokümanın bir bölümünü (görsel/tablo/grafik) seçti ve şu soruyu soruyor:
        
        \(question)
        
        Lütfen görseli analiz ederek soruyu yanıtla. 
        Eğer görsel dokümanın bir parçasıysa, doküman bağlamını da kullan.
        """
        
        logInfo("GeminiService", "Görsel sorusu gönderiliyor", details: "Soru: \(question.prefix(50))...")
        
        return try await withRetry { [weak self] in
            guard let self = self else { throw GeminiError.sessionNotInitialized }
            guard let currentChat = self.chatSession else {
                throw GeminiError.sessionNotInitialized
            }
            
            // Chat'e ModelContent olarak gönder
            let content = ModelContent(
                role: "user",
                parts: [
                    .data(mimetype: "image/jpeg", imageData),
                    .text(prompt)
                ]
            )
            let response = try await currentChat.sendMessage([content])
            
            let responseText = response.text ?? "Yanıt oluşturulamadı."
            
            await MainActor.run {
                logInfo("GeminiService", "Görsel sorusu yanıtlandı", details: "Yanıt uzunluğu: \(responseText.count)")
            }
            
            return responseText
        }
    }
    
    // MARK: - Batch Image Analysis (Lazy Caption Generation)
    
    /// Görsel için kısa caption oluştur (RAG indexleme için)
    func generateImageCaption(_ imageData: Data, context: String? = nil) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        
        var prompt = """
        Bu görseli analiz et ve kısa, öz bir Türkçe açıklama oluştur (maksimum 2-3 cümle).
        
        Açıklama şunları içermeli:
        - Görselin türü (grafik, tablo, diyagram, fotoğraf, vs.)
        - Ana içerik veya mesaj
        - Varsa önemli veriler veya etiketler
        
        Sadece açıklamayı yaz, başka bir şey ekleme.
        """
        
        if let context = context, !context.isEmpty {
            prompt += "\n\nBağlam (çevredeki metin): \(context.prefix(500))"
        }
        
        logInfo("GeminiService", "Görsel caption oluşturuluyor")
        
        return try await withRetry { [weak self] in
            guard let self = self else { throw GeminiError.sessionNotInitialized }
            
            let response = try await self.model.generateContent([
                ModelContent.Part.data(mimetype: "image/jpeg", imageData),
                ModelContent.Part.text(prompt)
            ])
            
            guard let text = response.text else {
                throw GeminiError.noResponse
            }
            
            let caption = text.trimmingCharacters(in: .whitespacesAndNewlines)
            
            await MainActor.run {
                logInfo("GeminiService", "Caption oluşturuldu", details: "\(caption.prefix(50))...")
            }
            
            return caption
        }
    }
    
    /// Birden fazla görseli sırayla analiz et (rate limiting ile)
    func batchAnalyzeImages(_ requests: [ImageAnalysisRequest]) async -> [ImageAnalysisResult] {
        var results: [ImageAnalysisResult] = []
        
        logInfo("GeminiService", "Batch görsel analizi başlıyor", details: "\(requests.count) görsel")
        
        for (index, request) in requests.enumerated() {
            do {
                let caption = try await generateImageCaption(request.imageData, context: request.context)
                
                // Caption için embedding oluştur (arama için)
                let embedding = try? await RAGService.shared.createEmbedding(for: caption)
                
                let result = ImageAnalysisResult(
                    imageId: request.imageId,
                    caption: caption,
                    captionEmbedding: embedding
                )
                results.append(result)
                
                // Rate limiting - API limitlerini aşmamak için
                if index < requests.count - 1 {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                }
                
            } catch {
                logWarning("GeminiService", "Görsel \(index + 1) analiz edilemedi", details: error.localizedDescription)
                // Hata olsa bile devam et
            }
        }
        
        logInfo("GeminiService", "Batch analiz tamamlandı", details: "\(results.count)/\(requests.count) başarılı")
        return results
    }
    
    /// Sayfa görselleri ile birlikte soru yanıtla
    func askWithPageImages(_ question: String, images: [(data: Data, caption: String?)], pageNumber: Int) async throws -> String {
        guard chatSession != nil else {
            throw GeminiError.sessionNotInitialized
        }
        
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }
        
        // Prompt oluştur
        var prompt = """
        Kullanıcı Sayfa \(pageNumber) hakkında şunu soruyor: "\(question)"
        
        Bu sayfada \(images.count) görsel bulunuyor.
        """
        
        // Caption'ları ekle
        for (index, image) in images.enumerated() {
            if let caption = image.caption {
                prompt += "\n- Görsel \(index + 1): \(caption)"
            }
        }
        
        prompt += "\n\nLütfen görselleri inceleyerek soruyu yanıtla."
        
        logInfo("GeminiService", "Sayfa görselleri ile soru", details: "Sayfa \(pageNumber), \(images.count) görsel")
        
        return try await withRetry { [weak self] in
            guard let self = self else { throw GeminiError.sessionNotInitialized }
            guard let currentChat = self.chatSession else {
                throw GeminiError.sessionNotInitialized
            }
            
            // Görselleri ve prompt'u birleştir
            var parts: [ModelContent.Part] = images.map { .data(mimetype: "image/jpeg", $0.data) }
            parts.append(.text(prompt))
            
            let content = ModelContent(role: "user", parts: parts)
            let response = try await currentChat.sendMessage([content])
            
            return response.text ?? "Yanıt oluşturulamadı."
        }
    }
    
    // MARK: - Faz 5: Reranking for RAG
    
    struct RerankResult {
        let index: Int
        let score: Float
        let reason: String?
    }
    
    /// Chunk'ları soruya alakaya göre yeniden sırala (RAG için)
    func rerankChunks(query: String, chunks: String) async throws -> [RerankResult] {
        isProcessing = true
        defer { isProcessing = false }
        
        let prompt = """
        Aşağıdaki metin parçalarını verilen soruya alakaya göre puanla.
        
        SORU: \(query)
        
        METİN PARÇALARI:
        \(chunks)
        
        Her parça için 0-10 arası puan ver:
        - 10: Soruya doğrudan cevap veriyor
        - 7-9: Çok alakalı bilgi içeriyor
        - 4-6: Kısmen alakalı
        - 1-3: Dolaylı olarak ilgili
        - 0: Alakasız
        
        SADECE JSON formatında döndür (başka hiçbir şey yazma):
        [{"index": 0, "score": 8.5, "reason": "Ana konuyu açıklıyor"}]
        
        İndeksler 0'dan başlıyor.
        """
        
        logInfo("GeminiService", "Reranking başlatılıyor")
        
        return try await withRetry { [weak self] in
            guard let self = self else { throw GeminiError.sessionNotInitialized }
            
            let response = try await self.model.generateContent(prompt)
            
            guard let text = response.text else {
                throw GeminiError.noResponse
            }
            
            // JSON parse
            let cleanedText = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let data = cleanedText.data(using: .utf8) else {
                throw GeminiError.parseError
            }
            
            struct RerankResponse: Decodable {
                let index: Int
                let score: Float
                let reason: String?
            }
            
            let results = try JSONDecoder().decode([RerankResponse].self, from: data)
            
            await MainActor.run {
                logInfo("GeminiService", "Reranking tamamlandı", details: "\(results.count) chunk puanlandı")
            }
            
            return results.map { RerankResult(index: $0.index, score: $0.score, reason: $0.reason) }
        }
    }
    
    // MARK: - Faz 6: Query Expansion
    
    struct ExpandedQuery {
        let original: String
        let expanded: String
        let keywords: [String]
        let hypotheticalAnswer: String?
    }
    
    /// Sorguyu genişlet ve HyDE uygula (RAG için)
    func expandQuery(_ query: String, documentContext: String? = nil) async throws -> ExpandedQuery {
        isProcessing = true
        defer { isProcessing = false }
        
        var contextSection = ""
        if let context = documentContext, !context.isEmpty {
            contextSection = "\nDOKÜMAN BAĞLAMI (kısa özet): \(context.prefix(500))\n"
        }
        
        let prompt = """
        Aşağıdaki kullanıcı sorusunu analiz et ve zenginleştir.
        \(contextSection)
        KULLANICI SORUSU: "\(query)"
        
        Görevler:
        1. Soruyu anahtar kelimeler ve eş anlamlılarla genişlet
        2. Alakalı terimleri ve kavramları ekle
        3. Kısa bir varsayımsal cevap oluştur (HyDE - doküman içeriği gibi yaz)
        
        JSON formatında döndür:
        {
            "expanded": "Genişletilmiş soru metni (Türkçe)",
            "keywords": ["anahtar", "kelime", "listesi"],
            "hypotheticalAnswer": "Bu konuda... (2-3 cümle varsayımsal cevap)"
        }
        """
        
        logInfo("GeminiService", "Query expansion başlatılıyor")
        
        return try await withRetry { [weak self] in
            guard let self = self else { throw GeminiError.sessionNotInitialized }
            
            let response = try await self.model.generateContent(prompt)
            
            guard let text = response.text else {
                throw GeminiError.noResponse
            }
            
            // JSON parse
            let cleanedText = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let data = cleanedText.data(using: .utf8) else {
                throw GeminiError.parseError
            }
            
            struct ExpansionResponse: Decodable {
                let expanded: String
                let keywords: [String]
                let hypotheticalAnswer: String?
            }
            
            let result = try JSONDecoder().decode(ExpansionResponse.self, from: data)
            
            await MainActor.run {
                logInfo("GeminiService", "Query expansion tamamlandı", 
                       details: "Orijinal: \(query.prefix(30))..., Expanded: \(result.expanded.prefix(30))...")
            }
            
            return ExpandedQuery(
                original: query,
                expanded: result.expanded,
                keywords: result.keywords,
                hypotheticalAnswer: result.hypotheticalAnswer
            )
        }
    }
    
    // MARK: - Query Translation (Türkçe → İngilizce)
    
    /// Türkçe sorguyu İngilizce'ye çevir (İngilizce dokümanlarda arama için)
    /// Bu, cross-lingual RAG için kritik öneme sahip
    /// Cache ile optimize edilmiş
    private var queryTranslationCache: [String: String] = [:]
    
    func translateQueryForSearch(_ query: String) async throws -> String {
        // Cache kontrolü
        if let cached = queryTranslationCache[query] {
            logDebug("GeminiService", "Query cache hit", details: query.prefix(30) + "...")
            return cached
        }
        
        // Zaten İngilizce mi kontrol et (basit heuristik)
        let turkishChars = CharacterSet(charactersIn: "çğıöşüÇĞİÖŞÜ")
        let turkishWords = ["bu", "ne", "nasıl", "nedir", "için", "ile", "ve", "veya", "ama", "çalışma", "sonuç", "hakkında", "neler", "ana", "nokta", "özet", "merhaba"]
        
        let hasTurkishChars = query.unicodeScalars.contains { turkishChars.contains($0) }
        let hasTurkishWords = turkishWords.contains { query.lowercased().contains($0) }
        
        // İngilizce ise direkt döndür
        if !hasTurkishChars && !hasTurkishWords {
            return query
        }
        
        // ÇÖOK kısa prompt - sadece çeviri, açıklama YOK
        let prompt = """
        Translate this Turkish text to English. Return ONLY the translation, nothing else. No explanations.
        
        "\(query)"
        """
        
        return try await withRetry { [weak self] in
            guard let self = self else { throw GeminiError.sessionNotInitialized }
            
            let response = try await self.model.generateContent(prompt)
            guard let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw GeminiError.noResponse
            }
            
            // Temizle ve sadece ilk satırı al (uzun açıklamaları engelle)
            var cleaned = text
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Sadece ilk satırı al (Gemini bazen uzun açıklama yapıyor)
            if let firstLine = cleaned.components(separatedBy: "\n").first {
                cleaned = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Çok uzunsa kes (max 200 karakter)
            if cleaned.count > 200 {
                cleaned = String(cleaned.prefix(200))
            }
            
            // Cache'e ekle
            await MainActor.run {
                self.queryTranslationCache[query] = cleaned
                logDebug("GeminiService", "Query çevirisi", details: "TR: \(query) → EN: \(cleaned)")
            }
            
            return cleaned
        }
    }
}

// MARK: - Errors
enum GeminiError: Error, LocalizedError {
    case noResponse
    case parseError
    case sessionNotInitialized
    case rateLimitExceeded
    case quotaExhausted
    case networkUnavailable
    
    var errorDescription: String? {
        switch self {
        case .noResponse:
            return "AI'dan yanıt alınamadı."
        case .parseError:
            return "Yanıt işlenemedi."
        case .sessionNotInitialized:
            return "Chat oturumu başlatılmadı."
        case .rateLimitExceeded:
            return "Çok fazla istek gönderildi. Lütfen bekleyin."
        case .quotaExhausted:
            return "Günlük kullanım limiti aşıldı."
        case .networkUnavailable:
            return "İnternet bağlantısı yok. Lütfen bağlantınızı kontrol edin."
        }
    }
}
