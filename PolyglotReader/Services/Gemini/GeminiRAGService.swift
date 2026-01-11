import Foundation
import GoogleGenerativeAI

@MainActor
class GeminiRAGService {
    private let model: GenerativeModel

    // Cache for query translation
    private var queryTranslationCache: [String: String] = [:]

    init() {
        self.model = GeminiConfig.createModel()
    }

    // MARK: - Reranking

    struct RerankResult {
        let index: Int
        let score: Float
        let reason: String?
    }

    func rerankChunks(query: String, chunks: String) async throws -> [RerankResult] {
        try await GeminiConfig.executeWithRetry(serviceName: "GeminiRAG") {
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

            let response = try await self.model.generateContent(prompt)
            guard let text = response.text else { throw GeminiError.noResponse }

            let cleanedText = self.cleanJSON(text)
            guard let data = cleanedText.data(using: .utf8) else { throw GeminiError.parseError }

            struct RerankResponse: Decodable {
                let index: Int
                let score: Float
                let reason: String?
            }

            let results = try JSONDecoder().decode([RerankResponse].self, from: data)
            return results.map { RerankResult(index: $0.index, score: $0.score, reason: $0.reason) }
        }
    }

    // MARK: - Query Expansion

    struct ExpandedQuery {
        let original: String
        let expanded: String
        let keywords: [String]
        let hypotheticalAnswer: String?
    }

    func expandQuery(_ query: String, documentContext: String? = nil) async throws -> ExpandedQuery {
        try await GeminiConfig.executeWithRetry(serviceName: "GeminiRAG") {
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

            let response = try await self.model.generateContent(prompt)
            guard let text = response.text else { throw GeminiError.noResponse }

            let cleanedText = self.cleanJSON(text)
            guard let data = cleanedText.data(using: .utf8) else { throw GeminiError.parseError }

            struct ExpansionResponse: Decodable {
                let expanded: String
                let keywords: [String]
                let hypotheticalAnswer: String?
            }

            let result = try JSONDecoder().decode(ExpansionResponse.self, from: data)

            return ExpandedQuery(
                original: query,
                expanded: result.expanded,
                keywords: result.keywords,
                hypotheticalAnswer: result.hypotheticalAnswer
            )
        }
    }

    // MARK: - Query Translation

    func translateQueryForSearch(_ query: String) async throws -> String {
        if let cached = queryTranslationCache[query] {
            return cached
        }

        // Simple heuristic
        let turkishChars = CharacterSet(charactersIn: "çğıöşüÇĞİÖŞÜ")
        let turkishWords = [
            "bu", "ne", "nasıl", "nedir", "için", "ile", "ve", "veya", "ama",
            "çalışma", "sonuç", "hakkında", "neler", "ana", "nokta", "özet", "merhaba"
        ]

        let hasTurkishChars = query.unicodeScalars.contains { turkishChars.contains($0) }
        let hasTurkishWords = turkishWords.contains { query.lowercased().contains($0) }

        if !hasTurkishChars && !hasTurkishWords {
            return query
        }

        return try await GeminiConfig.executeWithRetry(serviceName: "GeminiRAG") {
            let prompt = """
            Translate this Turkish text to English. Return ONLY the translation, nothing else. No explanations.

            "\(query)"
            """

            let response = try await self.model.generateContent(prompt)
            guard let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw GeminiError.noResponse
            }

            var cleaned = text.replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let firstLine = cleaned.components(separatedBy: "\n").first {
                cleaned = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if cleaned.count > 200 {
                cleaned = String(cleaned.prefix(200))
            }

            self.queryTranslationCache[query] = cleaned
            return cleaned
        }
    }

    // MARK: - Helpers

    private func cleanJSON(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
