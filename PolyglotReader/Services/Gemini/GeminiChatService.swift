import Foundation
import Combine
import GoogleGenerativeAI

@MainActor
class GeminiChatService {
    private let model: GenerativeModel

    /// Per-document chat sessions keyed by file ID.
    /// A single shared session would let a second opened document overwrite the
    /// first one's context, so the user could end up talking to the wrong PDF.
    private var sessions: [String: Chat] = [:]

    /// LRU order for `sessions`. Sessions hold full conversation histories
    /// (plus up to 100k chars of PDF text in legacy mode), so without a cap
    /// they accumulate for every document opened in the app's lifetime.
    private var sessionAccessOrder: [String] = []
    private let maxLiveSessions = 5

    private func touchSession(_ fileId: String) {
        sessionAccessOrder.removeAll { $0 == fileId }
        sessionAccessOrder.append(fileId)
        while sessions.count > maxLiveSessions, let oldest = sessionAccessOrder.first {
            sessionAccessOrder.removeFirst()
            sessions.removeValue(forKey: oldest)
            logDebug("GeminiChatService", "LRU session tahliye edildi", details: "File: \(oldest)")
        }
    }

    // Status properties managed by Facade, but service can expose async methods
    // The Service is NOT ObservableObject, the Facade is.

    init() {
        self.model = GeminiConfig.createModel()
    }

    // MARK: - Session Management

    func initChatSession(fileId: String, pdfContent: String? = nil) {
        var history: [ModelContent] = []

        if let content = pdfContent, !content.isEmpty {
            let parts: [ModelContent.Part] = [
                .text("İşte analiz etmeni istediğim PDF dokümanı:"),
                .text("--- METİN İÇERİĞİ BAŞLANGICI ---\n\(content.prefix(100000))\n--- METİN İÇERİĞİ SONU ---")
            ]

            history.append(ModelContent(role: "user", parts: parts))
            history.append(ModelContent(role: "model", parts: [
                .text("Dokümanı aldım. Sorularınızı yanıtlamaya hazırım. Nasıl yardımcı olabilirim?")
            ]))
        } else {
            history.append(ModelContent(role: "user", parts: [
                .text("PDF dokümanı hakkında sorular soracağım. İlgili bölümleri her soru ile birlikte paylaşacağım.")
            ]))
            history.append(ModelContent(role: "model", parts: [
                .text("Anladım! PDF'ten aldığınız bölümleri ve sorularınızı bekliyorum. Size yardımcı olmaya hazırım.")
            ]))
        }

        sessions[fileId] = model.startChat(history: history)
        touchSession(fileId)
        #if DEBUG
        let mode = pdfContent == nil ? "RAG" : "Legacy"
        logDebug("GeminiChatService", "Chat oturumu başlatıldı", details: "Mode: \(mode), File: \(fileId)")
        #endif
    }

    func resetChatSession(fileId: String) {
        sessions.removeValue(forKey: fileId)
        sessionAccessOrder.removeAll { $0 == fileId }
    }

    func resetAllSessions() {
        sessions.removeAll()
        sessionAccessOrder.removeAll()
    }

    func isSessionInitialized(fileId: String) -> Bool {
        sessions[fileId] != nil
    }

    /// Returns the chat session for the given file, lazily creating a RAG-mode
    /// session if the document was never explicitly initialised. This keeps each
    /// document isolated and avoids `sessionNotInitialized` race conditions.
    private func session(for fileId: String) -> Chat {
        if let chat = sessions[fileId] {
            touchSession(fileId)
            return chat
        }
        let history: [ModelContent] = [
            ModelContent(role: "user", parts: [
                .text("PDF dokümanı hakkında sorular soracağım. İlgili bölümleri her soru ile birlikte paylaşacağım.")
            ]),
            ModelContent(role: "model", parts: [
                .text("Anladım! PDF'ten aldığınız bölümleri ve sorularınızı bekliyorum. Size yardımcı olmaya hazırım.")
            ])
        ]
        let chat = model.startChat(history: history)
        sessions[fileId] = chat
        touchSession(fileId)
        return chat
    }

    /// Injects previously persisted chat turns into the session history so the
    /// model remembers earlier conversations after an app restart. Without this,
    /// the UI shows the old messages but the model starts from a blank session.
    /// Only runs while the session is still fresh (seed pair only) — once real
    /// turns exist in memory, they are already the source of truth.
    func seedPersistedHistory(fileId: String, turns: [(role: String, text: String)]) {
        guard !turns.isEmpty else { return }
        let chat = session(for: fileId)
        guard chat.history.count <= 2 else { return }

        var appended: [ModelContent] = []
        for turn in turns {
            let role = turn.role == "user" ? "user" : "model"
            // The SDK expects strictly alternating roles starting with "user"
            // after the seed model reply; skip turns that would break that.
            if appended.isEmpty && role != "user" { continue }
            if let last = appended.last, last.role == role { continue }
            appended.append(ModelContent(role: role, parts: [.text(turn.text)]))
        }
        // History must end on a model turn before the next user message.
        if appended.last?.role == "user" { appended.removeLast() }
        guard !appended.isEmpty else { return }

        chat.history = Self.trimmedHistory(
            chat.history + appended,
            maxTokens: GeminiConfig.maxHistoryTokens
        )
        logInfo(
            "GeminiChatService",
            "Kalıcı chat geçmişi oturuma yüklendi",
            details: "\(appended.count) mesaj, File: \(fileId)"
        )
    }

    // MARK: - History Budgeting

    /// Word-count based token estimate (same idiom as RAGConfig.tokenMultiplier).
    static func estimatedTokens(of content: ModelContent) -> Int {
        let words = content.parts.reduce(0) { count, part in
            if case .text(let text) = part {
                return count + text.split(separator: " ").count
            }
            return count
        }
        return Int(Float(words) * RAGConfig.tokenMultiplier)
    }

    /// Returns history trimmed to roughly `maxTokens` by dropping the oldest
    /// user/model turn pairs. The initial context pair (created in
    /// `initChatSession`) is always preserved, and pairs are removed whole so
    /// the alternating role structure the SDK expects is never broken.
    static func trimmedHistory(_ history: [ModelContent], maxTokens: Int) -> [ModelContent] {
        let preservedCount = 2 // Initial context user/model pair at the start.
        // Always keep the preserved pair plus at least the most recent pair.
        guard history.count > preservedCount + 2 else { return history }

        var totalTokens = history.reduce(0) { $0 + estimatedTokens(of: $1) }
        guard totalTokens > maxTokens else { return history }

        var trimmed = history
        while totalTokens > maxTokens, trimmed.count > preservedCount + 2 {
            let pairRange = preservedCount...(preservedCount + 1)
            totalTokens -= trimmed[pairRange].reduce(0) { $0 + Self.estimatedTokens(of: $1) }
            trimmed.removeSubrange(pairRange)
        }
        return trimmed
    }

    /// Applies the history budget to a live session before sending a new turn.
    private func trimHistoryIfNeeded(_ chat: Chat) {
        let originalCount = chat.history.count
        let trimmed = Self.trimmedHistory(chat.history, maxTokens: GeminiConfig.maxHistoryTokens)
        guard trimmed.count < originalCount else { return }
        chat.history = trimmed
        logInfo(
            "GeminiChatService",
            "Chat geçmişi token bütçesi için kırpıldı",
            details: "\(originalCount - trimmed.count) mesaj düşürüldü, \(trimmed.count) mesaj kaldı"
        )
    }

    // MARK: - Messaging

    /// Stateless one-shot generation (no conversation history).
    /// Used for utility prompts such as smart-suggestion generation so they
    /// never pollute or depend on a document's chat session.
    func sendMessage(_ message: String) async throws -> String {
        try await GeminiConfig.executeWithRetry(serviceName: "GeminiChat") {
            let response = try await self.model.generateContent(message)
            return response.text ?? "Yanıt oluşturulamadı."
        }
    }

    func sendMessageWithContext(_ message: String, context: String, fileId: String) async throws -> String {
        try await GeminiConfig.executeWithRetry(serviceName: "GeminiChat") {
            let chat = self.session(for: fileId)
            self.trimHistoryIfNeeded(chat)

            let fullMessage = self.buildEnhancedPrompt(message: message, context: context)

            let response = try await chat.sendMessage(fullMessage)
            return response.text ?? "Yanıt oluşturulamadı."
        }
    }

    // MARK: - Enhanced Prompt Builder (NotebookLM-Style)
    private func buildEnhancedPrompt(message: String, context: String) -> String {
        """
        \(context)

        ---

        ## Kullanıcı Sorusu
        \(message)

        ---

        ## Yanıt Kuralları

        ### 1. Kaynak Kullanımı
        - SADECE yukarıdaki doküman bölümlerini kullan
        - Dış bilgi veya varsayım YAPMA
        - Her önemli bilgi için kaynak göster — tıklanabilir link formatıyla: [Sayfa X](jump:X)

        ### 2. Yanıt Formatı
        - **Kısa soru** → Öz ve net cevap (1-3 cümle)
        - **Açıklama istekleri** → Yapılandırılmış maddeler halinde
        - **Karşılaştırma** → Tablo formatı kullan
        - **Tanım soruları** → Önce tanım, sonra detay

        ### 3. Belirsizlik Durumu
        Eğer bilgi dokümanda YOKSA:
        - "Bu bilgi dokümanda yer almıyor." de
        - Varsa ilgili konuları öner: "Ancak Sayfa X'te şu konu ele alınıyor: ..."
        - ASLA tahmin yapma veya uydurma

        ### 4. Dil ve Ton
        - Akademik ama anlaşılır Türkçe
        - Teknik terimleri koru, gerekirse açıkla
        - Gereksiz tekrardan kaçın

        Şimdi yukarıdaki kurallara uyarak soruyu yanıtla:
        """
    }

    func sendMessageStream(_ message: String, fileId: String) -> AsyncThrowingStream<String, Error> {
        let chat = session(for: fileId)
        trimHistoryIfNeeded(chat)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let streamSource = chat.sendMessageStream(message)
                    for try await chunk in streamSource {
                        if let text = chunk.text {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Stop the underlying network stream when the consumer cancels,
            // otherwise the SDK keeps generating into a dead continuation.
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func sendMessageStreamWithContext(
        _ message: String,
        context: String,
        fileId: String
    ) -> AsyncThrowingStream<String, Error> {
        let fullMessage = buildEnhancedPrompt(message: message, context: context)
        return sendMessageStream(fullMessage, fileId: fileId)
    }

    // MARK: - Library Chat (multi-document)

    /// Kütüphane sohbeti tek sanal oturumda yaşar (dosya oturumlarıyla
    /// karışmaz); LRU tahliyesine diğerleri gibi tabidir.
    static let librarySessionKey = "library_chat"

    func sendLibraryMessageStream(_ message: String, context: String) -> AsyncThrowingStream<String, Error> {
        let prompt = context.isEmpty
            ? message
            : buildLibraryPrompt(message: message, context: context)
        return sendMessageStream(prompt, fileId: Self.librarySessionKey)
    }

    func resetLibrarySession() {
        resetChatSession(fileId: Self.librarySessionKey)
    }

    /// Web'deki buildLibraryPrompt (web/src/lib/gemini.ts) ile hizalı —
    /// iki platform kütüphane sorularına aynı kurallarla yanıt versin.
    private func buildLibraryPrompt(message: String, context: String) -> String {
        """
        # Kütüphane Bölümleri
        Aşağıda kullanıcının sorusuyla ilgili, kütüphanedeki **birden fazla dokümandan** \
        alınan bölümler yer almaktadır. Her bölümün başında kaynak dosya adı ve sayfası belirtilmiştir.

        \(context)

        ---

        ## Kullanıcı Sorusu
        \(message)

        ---

        ## Yanıt Kuralları
        - **SADECE** yukarıdaki doküman bölümlerini kullan; dış bilgi veya varsayım YAPMA
        - Her önemli bilgi için kaynağı belirt: dosya adı ve sayfa — örn. "(rapor.pdf, Sayfa 4)"
        - Farklı dokümanlardan gelen bilgileri karşılaştırırken hangi dosyadan geldiğini netleştir
        - Doküman İngilizce, soru Türkçe olabilir: terimlerin Türkçe karşılığını da ver
        - Akademik ama anlaşılır Türkçe kullan; gereksiz tekrardan kaçın
        - Eğer konu hiçbir dokümanda yoksa: "Kütüphanenizdeki dokümanlar bu konuda bilgi içermiyor." de — ASLA uydurma

        Şimdi yukarıdaki kurallara uyarak soruyu yanıtla:
        """
    }

    // MARK: - Image Questions

    func askAboutImage(_ imageData: Data, question: String, fileId: String) async throws -> String {
        try await GeminiConfig.executeWithRetry(serviceName: "GeminiChat") {
            let chat = self.session(for: fileId)
            self.trimHistoryIfNeeded(chat)

            let prompt = """
            Kullanıcı dokümanın bir bölümünü (görsel/tablo/grafik) seçti ve şu soruyu soruyor:

            \(question)

            Lütfen görseli analiz ederek soruyu yanıtla.
            Eğer görsel dokümanın bir parçasıysa, doküman bağlamını da kullan.
            """

            let content = ModelContent(
                role: "user",
                parts: [
                    .data(mimetype: "image/jpeg", imageData),
                    .text(prompt)
                ]
            )

            let response = try await chat.sendMessage([content])
            return response.text ?? "Yanıt oluşturulamadı."
        }
    }

    func askWithPageImages(
        _ question: String,
        images: [(data: Data, caption: String?)],
        pageNumber: Int,
        fileId: String
    ) async throws -> String {
        try await GeminiConfig.executeWithRetry(serviceName: "GeminiChat") {
            let chat = self.session(for: fileId)
            self.trimHistoryIfNeeded(chat)

            var prompt = """
            Kullanıcı Sayfa \(pageNumber) hakkında şunu soruyor: "\(question)"

            Bu sayfada \(images.count) görsel bulunuyor.
            """

            for (index, image) in images.enumerated() {
                if let caption = image.caption {
                    prompt += "\n- Görsel \(index + 1): \(caption)"
                }
            }

            prompt += "\n\nLütfen görselleri inceleyerek soruyu yanıtla."

            var parts: [ModelContent.Part] = images.map { .data(mimetype: "image/jpeg", $0.data) }
            parts.append(.text(prompt))

            let content = ModelContent(role: "user", parts: parts)
            let response = try await chat.sendMessage([content])
            return response.text ?? "Yanıt oluşturulamadı."
        }
    }
}
