import Foundation
import GoogleGenerativeAI

// MARK: - Analysis Service
@MainActor
class GeminiAnalysisService {
    private let model: GenerativeModel

    init() {
        self.model = GeminiConfig.createModel()
    }

    // MARK: - Translation

    func translateText(_ text: String, context: String? = nil) async throws -> TranslationResult {
        guard !text.isEmpty else {
            return TranslationResult(original: text, translated: "", detectedLanguage: "Unknown")
        }

        return try await GeminiConfig.executeWithRetry(serviceName: "GeminiAnalysis") {
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
            guard let responseText = response.text else { throw GeminiError.noResponse }

            let cleanedText = self.cleanJSON(responseText)
            guard let data = cleanedText.data(using: .utf8) else { throw GeminiError.parseError }

            struct TranslationResponse: Decodable {
                let translatedText: String
                let detectedLanguage: String
            }

            let result = try JSONDecoder().decode(TranslationResponse.self, from: data)

            return TranslationResult(
                original: String(text.prefix(2000)),
                translated: result.translatedText,
                detectedLanguage: result.detectedLanguage
            )
        }
    }

    // MARK: - Smart Note

    func generateSmartNote(_ text: String) async throws -> String {
        try await GeminiConfig.executeWithRetry(serviceName: "GeminiAnalysis") {
            let prompt = """
            Seçilen metni analiz et ve Türkçe kısa bir çalışma notu oluştur (maksimum 2 cümle).
            Ana kavrama veya önemli noktaya odaklan.

            Metin: "\(text)"
            """

            let response = try await self.model.generateContent(prompt)
            return response.text ?? "Not oluşturulamadı."
        }
    }

    // MARK: - Summary

    func generateDocumentSummary(_ text: String) async throws -> String {
        try await GeminiConfig.executeWithRetry(serviceName: "GeminiAnalysis") {
            let prompt = """
            Aşağıdaki doküman metnini analiz et.
            Sadece 2 cümlelik, çok kısa bir Türkçe özet oluştur.
            Kesinlikle markdown başlığı (###), liste (*) veya kalın yazı (**) kullanma.
            Sadece düz metin olsun. Dokümanın ana amacını açıkla.

            Metin: "\(text.prefix(4000))"
            """

            let response = try await self.model.generateContent(prompt)
            return response.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    // MARK: - Tags

    func generateTags(_ text: String, existingTags: [String] = []) async throws -> GeminiService.AITagResult {
        try await GeminiConfig.executeWithRetry(serviceName: "GeminiAnalysis") {
            let existingTagsSection = self.buildExistingTagsSection(existingTags)
            let prompt = self.buildTagsPrompt(text: text, existingTagsSection: existingTagsSection)
            let response = try await self.model.generateContent(prompt)
            guard let responseText = response.text else { throw GeminiError.noResponse }
            return try self.decodeTagResult(from: responseText)
        }
    }

    // MARK: - Quiz

    func generateQuiz(context: String) async throws -> [QuizQuestion] {
        try await GeminiConfig.executeWithRetry(serviceName: "GeminiAnalysis") {
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

            let response = try await self.model.generateContent(prompt)
            guard let text = response.text else { throw GeminiError.noResponse }

            let cleanedText = self.cleanJSON(text)
            guard let data = cleanedText.data(using: .utf8) else { throw GeminiError.parseError }

            struct QuizResponse: Decodable {
                let questions: [QuizQuestion]
            }

            let result = try JSONDecoder().decode(QuizResponse.self, from: data)
            return result.questions
        }
    }

    // MARK: - Image Analysis

    func analyzeImage(_ imageData: Data, prompt: String? = nil) async throws -> String {
        try await GeminiConfig.executeWithRetry(serviceName: "GeminiAnalysis") {
            let analysisPrompt = prompt ?? """
            Bu görseli analiz et ve Türkçe olarak açıkla.
            Görsel bir grafik, tablo veya diyagram ise:
            - İçeriği özetle
            - Önemli verileri listele
            - Varsa trendleri veya örüntüleri belirt
            """

            let response = try await self.model.generateContent([
                ModelContent.Part.data(mimetype: "image/jpeg", imageData),
                ModelContent.Part.text(analysisPrompt)
            ])

            return response.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    func generateImageCaption(_ imageData: Data, context: String? = nil) async throws -> String {
        try await GeminiConfig.executeWithRetry(serviceName: "GeminiAnalysis") {
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

            let response = try await self.model.generateContent([
                ModelContent.Part.data(mimetype: "image/jpeg", imageData),
                ModelContent.Part.text(prompt)
            ])

            return response.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    func batchAnalyzeImages(_ requests: [ImageAnalysisRequest]) async -> [ImageAnalysisResult] {
        var results: [ImageAnalysisResult] = []

        for (index, request) in requests.enumerated() {
            do {
                let caption = try await generateImageCaption(request.imageData, context: request.context)
                let embedding = try? await RAGService.shared.createEmbedding(for: caption)

                let result = ImageAnalysisResult(
                    imageId: request.imageId,
                    caption: caption,
                    captionEmbedding: embedding
                )
                results.append(result)

                if index < requests.count - 1 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            } catch {
                #if DEBUG
                logWarning(
                    "GeminiAnalysisService",
                    "Batch image failed",
                    details: error.localizedDescription
                )
                #endif
            }
        }
        return results
    }

    // MARK: - Helpers

    private func cleanJSON(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildExistingTagsSection(_ existingTags: [String]) -> String {
        guard !existingTags.isEmpty else { return "" }
        let tagList = existingTags.prefix(20).joined(separator: ", ")
        return """

        MEVCUT ETİKETLER (sadece gerçekten uyuyorsa kullan, zorla uydurmaya çalışma):
        [\(tagList)]

        Önemli: Eğer mevcut etiketlerden biri dokümanın konusuna tam olarak uyuyorsa onu kullan.
        Ancak doküman farklı bir konudaysa yeni etiket oluşturmaktan çekinme.
        Benzer ama farklı konularda (örn: "kasko sigortası" varken
        "hayat sigortası" gerekiyorsa) yeni etiket oluştur.

        """
    }

    private func buildTagsPrompt(text: String, existingTagsSection: String) -> String {
        """
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
    }

    private func decodeTagResult(from responseText: String) throws -> GeminiService.AITagResult {
        let cleanedText = self.cleanJSON(responseText)
        guard let data = cleanedText.data(using: .utf8) else { throw GeminiError.parseError }
        let resultRaw = try JSONDecoder().decode(TagResponse.self, from: data)
        let processedTags = resultRaw.tags.map { tag -> String in
            let words = tag.split(separator: " ").prefix(2)
            return words.joined(separator: " ")
        }
        return GeminiService.AITagResult(tags: processedTags, category: resultRaw.category)
    }

    private struct TagResponse: Decodable {
        let tags: [String]
        let category: String
    }
}
