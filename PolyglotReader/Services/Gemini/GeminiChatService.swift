import Foundation
import Combine
import GoogleGenerativeAI

@MainActor
class GeminiChatService {
    private let model: GenerativeModel
    private var chatSession: Chat?

    // Status properties managed by Facade, but service can expose async methods
    // The Service is NOT ObservableObject, the Facade is.

    init() {
        self.model = GeminiConfig.createModel()
    }

    // MARK: - Session Management

    func initChatSession(pdfContent: String? = nil) {
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

        chatSession = model.startChat(history: history)
        #if DEBUG
        let mode = pdfContent == nil ? "RAG" : "Legacy"
        logDebug("GeminiChatService", "Chat oturumu başlatıldı", details: "Mode: \(mode)")
        #endif
    }

    func resetChatSession() {
        chatSession = nil
    }

    var isSessionInitialized: Bool {
        chatSession != nil
    }

    // MARK: - Messaging

    func sendMessage(_ message: String) async throws -> String {
        try await GeminiConfig.executeWithRetry(serviceName: "GeminiChat") {
            guard let chat = self.chatSession else {
                throw GeminiError.sessionNotInitialized
            }
            let response = try await chat.sendMessage(message)
            return response.text ?? "Yanıt oluşturulamadı."
        }
    }

    func sendMessageWithContext(_ message: String, context: String) async throws -> String {
        try await GeminiConfig.executeWithRetry(serviceName: "GeminiChat") {
            guard let chat = self.chatSession else {
                throw GeminiError.sessionNotInitialized
            }

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

    func sendMessageStream(_ message: String) -> AsyncThrowingStream<String, Error> {
        let streamSourceBlock: () throws -> AsyncThrowingStream<GenerateContentResponse, Error> = {
            guard let chat = self.chatSession else {
                throw GeminiError.sessionNotInitialized
            }
            return chat.sendMessageStream(message)
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Check logic?
                    // Stream isn't easily retriable in the middle, but we can retry init?
                    // GeminiConfig.executeWithRetry doesn't support stream directly.
                    // We assume stream is reliable or handled by caller?
                    // Original code didn't retry stream creation explicitly inside the stream?
                    // Actually original code did NOT wrap stream in `withRetry`.
                    // It just started it.

                    let streamSource = try streamSourceBlock()

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

    func sendMessageStreamWithContext(_ message: String, context: String) -> AsyncThrowingStream<String, Error> {
        let fullMessage = buildEnhancedPrompt(message: message, context: context)
        return sendMessageStream(fullMessage)
    }

    // MARK: - Image Questions

    func askAboutImage(_ imageData: Data, question: String) async throws -> String {
        try await GeminiConfig.executeWithRetry(serviceName: "GeminiChat") {
            guard let chat = self.chatSession else {
                throw GeminiError.sessionNotInitialized
            }

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
        pageNumber: Int
    ) async throws -> String {
        try await GeminiConfig.executeWithRetry(serviceName: "GeminiChat") {
            guard let chat = self.chatSession else {
                throw GeminiError.sessionNotInitialized
            }

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
