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
        #if DEBUG
        let mode = pdfContent == nil ? "RAG" : "Legacy"
        logDebug("GeminiChatService", "Chat oturumu başlatıldı", details: "Mode: \(mode), File: \(fileId)")
        #endif
    }

    func resetChatSession(fileId: String) {
        sessions.removeValue(forKey: fileId)
    }

    func resetAllSessions() {
        sessions.removeAll()
    }

    func isSessionInitialized(fileId: String) -> Bool {
        sessions[fileId] != nil
    }

    /// Returns the chat session for the given file, lazily creating a RAG-mode
    /// session if the document was never explicitly initialised. This keeps each
    /// document isolated and avoids `sessionNotInitialized` race conditions.
    private func session(for fileId: String) -> Chat {
        if let chat = sessions[fileId] {
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
        return chat
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
        - Her önemli bilgi için kaynak göster: [1], [2] veya [Sayfa X]

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

        return AsyncThrowingStream { continuation in
            Task {
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

    // MARK: - Image Questions

    func askAboutImage(_ imageData: Data, question: String, fileId: String) async throws -> String {
        try await GeminiConfig.executeWithRetry(serviceName: "GeminiChat") {
            let chat = self.session(for: fileId)

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
