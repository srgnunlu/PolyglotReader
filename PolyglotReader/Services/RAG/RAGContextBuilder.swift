import Foundation

// MARK: - RAG Context Builder (Enhanced Citation v3.0)
class RAGContextBuilder {
    static let shared = RAGContextBuilder()

    private init() {}

    // MARK: - Token-Aware Context Building

    /// Token limitine göre zengin citation formatıyla context oluşturur
    func buildContextWithTokenLimit(from scoredChunks: [ScoredChunk],
                                    maxTokens: Int = RAGConfig.maxContextTokens) -> String {
        var context = buildContextHeader()
        var currentTokens = estimateTokens(context)
        var includedCount = 0
        var pagesSeen: Set<Int> = []

        for scored in scoredChunks {
            let chunk = scored.chunk

            // Sayfa bilgisi
            let pageInfo = formatPageInfo(chunk: chunk)
            if let page = chunk.pageNumber ?? chunk.startPage {
                pagesSeen.insert(page)
            }

            // Güven skoru göstergesi
            let confidenceIndicator = formatConfidence(scored: scored)

            // P1.2: Metadata özeti (tablo, liste, görsel bilgisi)
            let metadataInfo = formatMetadata(chunk: chunk)

            // Zengin citation formatı
            let chunkText = """
            ---
            [\(includedCount + 1)]\(pageInfo)\(confidenceIndicator)\(metadataInfo)
            \(chunk.content)

            """

            let chunkTokens = estimateTokens(chunkText)

            // Token limiti kontrolü
            if currentTokens + chunkTokens > maxTokens {
                break
            }

            context += chunkText
            currentTokens += chunkTokens
            includedCount += 1
        }

        // Context özeti ekle
        context += buildContextFooter(
            chunkCount: includedCount,
            pagesSeen: pagesSeen,
            tokenCount: currentTokens
        )

        return context
    }

    // MARK: - Format Helpers

    // MARK: - P3.4: Enhanced Citation Header

    private func buildContextHeader() -> String {
        """
        # Doküman Bölümleri
        Aşağıda kullanıcının sorusuyla ilgili doküman bölümleri yer almaktadır.
        Her bölüm [numara](Sayfa X) formatında etiketlenmiştir.

        ## Kaynak Gösterme Kuralları
        - Yanıtlarında bilgi verirken mutlaka sayfa numarasını belirt
        - Format MUTLAKA tıklanabilir link olsun: [Sayfa X](jump:X) — örnek: "... [Sayfa 5](jump:5)"
        - Birden fazla kaynaktan bilgi alıyorsan hepsini ayrı linkle: [Sayfa 3](jump:3), [Sayfa 7](jump:7)
        - Tablo veya liste içeren bölümleri özellikle vurgula

        """
    }

    private func formatPageInfo(chunk: DocumentChunk) -> String {
        if let start = chunk.startPage, let end = chunk.endPage, start != end {
            return " (Sayfa \(start)-\(end))"
        } else if let page = chunk.pageNumber ?? chunk.startPage {
            return " (Sayfa \(page))"
        }
        return ""
    }

    private func formatConfidence(scored: ScoredChunk) -> String {
        // Yüksek güvenli chunk'lar için gösterge
        if let similarity = scored.chunk.similarity, similarity >= 0.7 {
            return " [Yüksek Eşleşme]"
        } else if scored.rerankScore ?? 0 >= 8.0 {
            return " [Çok İlgili]"
        }
        return ""
    }

    // MARK: - P1.2: Metadata Formatting

    private func formatMetadata(chunk: DocumentChunk) -> String {
        var parts: [String] = []

        // Bölüm başlığı
        if let section = chunk.sectionTitle, !section.isEmpty {
            parts.append("📑 \(section)")
        }

        // Tablo içeriği
        if chunk.containsTable {
            parts.append("📊 Tablo")
        }

        // Liste içeriği
        if chunk.containsList {
            parts.append("📝 Liste")
        }

        // Görsel referansları
        if !chunk.imageReferences.isEmpty {
            parts.append("🖼️ \(chunk.imageReferences.count) görsel")
        }

        guard !parts.isEmpty else { return "" }
        return " [\(parts.joined(separator: " | "))]"
    }

    // MARK: - P3.4: Enhanced Citation Footer

    private func buildContextFooter(chunkCount: Int, pagesSeen: Set<Int>, tokenCount: Int) -> String {
        let sortedPages = pagesSeen.sorted()
        let pagesText = sortedPages.isEmpty ? "Bilinmiyor" :
            sortedPages.count <= 5 ? sortedPages.map(String.init).joined(separator: ", ") :
            "\(sortedPages.first!)...\(sortedPages.last!) (\(sortedPages.count) sayfa)"

        // P3.4: Sayfa listesini AI'ın kullanması için formatla
        let pageListForCitation = sortedPages.isEmpty ? "" :
            "\n📍 **Kullanılabilir Sayfalar:** \(sortedPages.map { "Sayfa \($0)" }.joined(separator: ", "))"

        return """

        ---
        **Bağlam Özeti:** \(chunkCount) bölüm, Sayfalar: \(pagesText)\(pageListForCitation)

        ⚠️ **Hatırlatma:** Yanıtında bilgilerin hangi sayfadan geldiğini mutlaka belirt!

        """
    }

    /// Token tahmini (kelime * multiplier)
    private func estimateTokens(_ text: String) -> Int {
        let wordCount = text.split(separator: " ").count
        return Int(Float(wordCount) * RAGConfig.tokenMultiplier)
    }

    // MARK: - Backward Compatibility

    func buildContext(from chunks: [DocumentChunk]) -> String {
        let scoredChunks = chunks.map { ScoredChunk(chunk: $0, vectorScore: 1.0, bm25Score: 0, rrfScore: 1.0) }
        return buildContextWithTokenLimit(from: scoredChunks)
    }
}
