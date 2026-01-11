import Foundation

// MARK: - Smart Suggestion Service (P4)
/// Doküman içeriğine göre dinamik soru önerileri oluşturur
class SmartSuggestionService {
    static let shared = SmartSuggestionService()

    private let geminiService = GeminiService.shared

    private init() {}

    // MARK: - Suggestion Categories

    enum SuggestionCategory: String, CaseIterable {
        case summary = "özet"
        case analysis = "analiz"
        case extraction = "çıkarım"
        case comparison = "karşılaştırma"
        case clarification = "açıklama"
        case table = "tablo"
        case image = "görsel"

        var icon: String {
            switch self {
            case .summary: return "doc.text"
            case .analysis: return "chart.bar.doc.horizontal"
            case .extraction: return "text.magnifyingglass"
            case .comparison: return "arrow.left.arrow.right"
            case .clarification: return "questionmark.circle"
            case .table: return "tablecells"
            case .image: return "photo"
            }
        }
    }

    // MARK: - Static Fallback Suggestions

    static let defaultSuggestions: [ChatSuggestion] = [
        ChatSuggestion(
            label: "Dokümanı Özetle",
            icon: "doc.text",
            prompt: "Lütfen tüm dokümanın kısa bir özetini çıkar, ana hedefleri ve sonuçları vurgula."
        ),
        ChatSuggestion(
            label: "Ana Noktalar",
            icon: "lightbulb",
            prompt: "Bu dosyadan çıkarılabilecek en önemli 5 nokta nedir?"
        ),
        ChatSuggestion(
            label: "Anahtar Terimler",
            icon: "text.magnifyingglass",
            prompt: "Dokümandaki anahtar terimleri ve kavramları listele ve kısaca açıkla."
        ),
        ChatSuggestion(
            label: "Soru-Cevap",
            icon: "questionmark.circle",
            prompt: "Bu doküman hakkında en sık sorulabilecek 5 soruyu ve cevaplarını hazırla."
        )
    ]

    // MARK: - Page-Based Suggestions

    /// Mevcut sayfa içeriğine göre öneriler oluşturur
    func generatePageBasedSuggestions(
        pageText: String,
        pageNumber: Int,
        hasTable: Bool = false,
        hasImage: Bool = false
    ) -> [ChatSuggestion] {
        var suggestions: [ChatSuggestion] = []

        // Sayfa bazlı temel öneri
        suggestions.append(ChatSuggestion(
            label: "Sayfa \(pageNumber) Özeti",
            icon: "doc.text",
            prompt: "Sayfa \(pageNumber)'deki içeriği özetle ve ana noktaları belirt."
        ))

        // Tablo varsa
        if hasTable {
            suggestions.append(ChatSuggestion(
                label: "Tabloyu Açıkla",
                icon: "tablecells",
                prompt: "Sayfa \(pageNumber)'deki tabloyu analiz et. Verilerin ne anlama geldiğini açıkla."
            ))
        }

        // Görsel varsa
        if hasImage {
            suggestions.append(ChatSuggestion(
                label: "Görseli Yorumla",
                icon: "photo",
                prompt: "Sayfa \(pageNumber)'deki görseli incele ve ne anlattığını açıkla."
            ))
        }

        // İçerik analizi ile ek öneriler
        let contentSuggestions = analyzeContentForSuggestions(pageText, pageNumber: pageNumber)
        suggestions.append(contentsOf: contentSuggestions)

        return Array(suggestions.prefix(4)) // Maksimum 4 öneri
    }

    // MARK: - Content Analysis

    /// İçeriği analiz ederek ilgili öneriler oluşturur
    private func analyzeContentForSuggestions(_ text: String, pageNumber: Int) -> [ChatSuggestion] {
        var suggestions: [ChatSuggestion] = []
        let lowercased = text.lowercased()

        // Sayısal veri kontrolü
        let numberPattern = #"\d+[.,]\d+"#
        if let regex = try? NSRegularExpression(pattern: numberPattern),
           regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) > 3 {
            suggestions.append(ChatSuggestion(
                label: "Verileri Analiz Et",
                icon: "chart.bar",
                prompt: "Sayfa \(pageNumber)'deki sayısal verileri analiz et ve önemli trendleri belirt."
            ))
        }

        // Tarih kontrolü
        let dateKeywords = ["tarih", "yıl", "ay", "gün", "dönem", "süre", "zaman"]
        if dateKeywords.contains(where: { lowercased.contains($0) }) {
            suggestions.append(ChatSuggestion(
                label: "Kronoloji Çıkar",
                icon: "calendar",
                prompt: "Bu sayfadaki tarihleri ve zaman dilimlerini kronolojik sıraya koy."
            ))
        }

        // Liste/madde kontrolü
        let listIndicators = ["•", "◦", "▪", "1.", "2.", "a)", "b)", "-"]
        if listIndicators.contains(where: { text.contains($0) }) {
            suggestions.append(ChatSuggestion(
                label: "Maddeleri Açıkla",
                icon: "list.bullet",
                prompt: "Bu sayfadaki maddeleri tek tek açıkla ve önemini belirt."
            ))
        }

        // Teknik terim kontrolü
        let technicalIndicators = ["algoritma", "sistem", "model", "yöntem", "metod", "formül", "denklem"]
        if technicalIndicators.contains(where: { lowercased.contains($0) }) {
            suggestions.append(ChatSuggestion(
                label: "Basitçe Açıkla",
                icon: "text.bubble",
                prompt: "Bu sayfadaki teknik kavramları basit bir dille açıkla."
            ))
        }

        // Karşılaştırma kontrolü
        let comparisonIndicators = ["karşılaştır", "fark", "benzer", "aksine", "ancak", "oysa", "vs"]
        if comparisonIndicators.contains(where: { lowercased.contains($0) }) {
            suggestions.append(ChatSuggestion(
                label: "Karşılaştırma Yap",
                icon: "arrow.left.arrow.right",
                prompt: "Bu sayfada bahsedilen kavramları/konuları karşılaştır."
            ))
        }

        return suggestions
    }

    // MARK: - Section-Based Suggestions

    /// Bölüm başlığına göre öneriler oluşturur
    func generateSectionSuggestions(sectionTitle: String, pageNumber: Int) -> [ChatSuggestion] {
        var suggestions: [ChatSuggestion] = []
        let lowercased = sectionTitle.lowercased()

        // Bölüm tipi tespiti
        if lowercased.contains("giriş") || lowercased.contains("introduction") {
            suggestions.append(ChatSuggestion(
                label: "Giriş Özeti",
                icon: "arrow.right.circle",
                prompt: "Giriş bölümündeki ana argümanları ve hedefleri özetle."
            ))
        }

        if lowercased.contains("sonuç") || lowercased.contains("conclusion") {
            suggestions.append(ChatSuggestion(
                label: "Sonuçları Değerlendir",
                icon: "checkmark.circle",
                prompt: "Sonuç bölümündeki bulguları ve önerileri değerlendir."
            ))
        }

        if lowercased.contains("yöntem") || lowercased.contains("method") {
            suggestions.append(ChatSuggestion(
                label: "Yöntemi Açıkla",
                icon: "gearshape.2",
                prompt: "Kullanılan yöntemi adım adım açıkla."
            ))
        }

        if lowercased.contains("sonuç") || lowercased.contains("bulgular") || lowercased.contains("results") {
            suggestions.append(ChatSuggestion(
                label: "Bulguları Özetle",
                icon: "doc.text.magnifyingglass",
                prompt: "Bu bölümdeki ana bulguları ve önemli sonuçları listele."
            ))
        }

        // Genel bölüm önerisi
        if suggestions.isEmpty {
            suggestions.append(ChatSuggestion(
                label: "\(sectionTitle) Hakkında",
                icon: "info.circle",
                prompt: "\"\(sectionTitle)\" bölümünün ana fikirlerini özetle."
            ))
        }

        return suggestions
    }

    // MARK: - AI-Generated Suggestions (Advanced)

    /// Gemini kullanarak akıllı öneriler oluşturur (opsiyonel, API çağrısı gerektirir)
    func generateAISuggestions(
        documentSummary: String,
        currentPage: Int
    ) async throws -> [ChatSuggestion] {
        let prompt = """
        Aşağıdaki doküman özeti için kullanıcının sorabileceği 3 akıllı soru öner.
        Her soru kısa ve spesifik olmalı.

        Doküman özeti:
        \(documentSummary.prefix(500))

        Mevcut sayfa: \(currentPage)

        JSON formatında yanıt ver:
        [
            {"label": "kısa etiket", "prompt": "tam soru metni"},
            ...
        ]
        """

        let response = try await geminiService.sendMessage(prompt)

        // JSON parse
        guard let data = response.data(using: .utf8),
              let suggestions = try? JSONDecoder().decode([AISuggestionResponse].self, from: data) else {
            return []
        }

        return suggestions.map { suggestion in
            ChatSuggestion(
                label: suggestion.label,
                icon: "sparkles",
                prompt: suggestion.prompt
            )
        }
    }

    // MARK: - Combined Smart Suggestions

    /// Tüm kaynaklardan akıllı öneriler oluşturur
    func getSmartSuggestions(
        pageText: String?,
        pageNumber: Int,
        sectionTitle: String?,
        hasTable: Bool,
        hasImage: Bool
    ) -> [ChatSuggestion] {
        var allSuggestions: [ChatSuggestion] = []

        // 1. Bölüm bazlı öneriler (öncelikli)
        if let section = sectionTitle, !section.isEmpty {
            let sectionSuggestions = generateSectionSuggestions(sectionTitle: section, pageNumber: pageNumber)
            allSuggestions.append(contentsOf: sectionSuggestions)
        }

        // 2. Sayfa bazlı öneriler
        if let text = pageText, !text.isEmpty {
            let pageSuggestions = generatePageBasedSuggestions(
                pageText: text,
                pageNumber: pageNumber,
                hasTable: hasTable,
                hasImage: hasImage
            )
            allSuggestions.append(contentsOf: pageSuggestions)
        }

        // 3. Tekrarlayan önerileri kaldır
        var seen: Set<String> = []
        allSuggestions = allSuggestions.filter { suggestion in
            let key = suggestion.label.lowercased()
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }

        // 4. Maksimum 4 öneri döndür, eksikse default ekle
        if allSuggestions.count < 4 {
            let needed = 4 - allSuggestions.count
            let defaults = Self.defaultSuggestions.filter { def in
                !allSuggestions.contains { $0.label == def.label }
            }
            allSuggestions.append(contentsOf: defaults.prefix(needed))
        }

        return Array(allSuggestions.prefix(4))
    }
}

// MARK: - AI Response Model
private struct AISuggestionResponse: Decodable {
    let label: String
    let prompt: String
}
