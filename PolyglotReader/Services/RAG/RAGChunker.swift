import Foundation

// MARK: - RAG Chunker (Structure-Aware v3.0)
class RAGChunker {
    static let shared = RAGChunker()

    private init() {}

    // MARK: - Heading Detection Patterns
    private let headingPatterns: [NSRegularExpression] = {
        let patterns = [
            // Numaralı başlıklar: "1.", "1.1", "1.1.1", "A.", "a)"
            #"^(?:\d+\.)+\s*[A-ZÇĞİÖŞÜ]"#,
            #"^[A-Z]\.\s+"#,
            #"^[a-z]\)\s+"#,
            // Markdown başlıkları
            #"^#{1,4}\s+"#,
            // BÜYÜK HARF BAŞLIKLAR (en az 3 kelime, tamamı büyük)
            #"^[A-ZÇĞİÖŞÜ][A-ZÇĞİÖŞÜ\s]{10,}$"#,
            // Bölüm/Kısım başlıkları
            #"^(?:BÖLÜM|KISIM|MADDE|Bölüm|Kısım|Madde|Chapter|Section)\s*\d*"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: []) }
    }()

    // MARK: - Chunking Context (Enhanced P1)
    private struct ChunkingContext {
        var sentences: [Sentence] = []
        var wordCount: Int = 0
        var chunkIndex: Int = 0
        var startPage: Int?
        var endPage: Int?
        var chunks: [DocumentChunk] = []
        let fileId: UUID
        var currentHeading: String?       // Mevcut bölüm başlığı
        var containsTable: Bool = false   // P1: Chunk tablo içeriyor mu
        var containsList: Bool = false    // P1: Chunk liste içeriyor mu
        var contentType: ChunkContentType = .text  // P1: İçerik tipi
    }

    // MARK: - P1: Tablo Algılama Patterns
    private let tablePatterns: [NSRegularExpression] = {
        let patterns = [
            // Pipe-separated tablo (Markdown style)
            #"\|[^|]+\|"#,
            // Tab-separated satırlar (en az 3 tab)
            #"^[^\t]+\t[^\t]+\t[^\t]+"#,
            // Tablo başlığı
            #"^(?:Tablo|Table|Çizelge)\s*\d+"#,
            // Hizalı sayısal veriler (sütun veri)
            #"^\s*[\d,.]+\s{2,}[\d,.]+\s{2,}[\d,.]+"#,
            // Çizgi ayırıcılar
            #"^[-─═]{5,}"#,
            #"^\+[-+]+\+"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.anchorsMatchLines]) }
    }()

    // MARK: - P1: Liste Algılama Patterns
    private let listPatterns: [NSRegularExpression] = {
        let patterns = [
            // Bullet listeler
            #"^[\s]*[•◦▪▸►‣⁃]\s+"#,
            #"^[\s]*[-*]\s+"#,
            // Numaralı listeler
            #"^[\s]*\d+[.)]\s+"#,
            // Harf listeler
            #"^[\s]*[a-zA-Z][.)]\s+"#,
            // Romen rakamları
            #"^[\s]*(?:i{1,3}|iv|vi{0,3}|ix|x)[.)]\s+"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.anchorsMatchLines, .caseInsensitive]) }
    }()

    /// Cümle ve paragraf sınırlarına saygılı akıllı chunking
    func semanticChunkText(_ text: String, fileId: UUID) -> [DocumentChunk] {
        semanticChunkText(text, fileId: fileId, imageMetadata: [])
    }

    /// P1.2: Görsel metadata ile zenginleştirilmiş chunking
    /// P3.3: Deduplication ile optimize edilmiş
    func semanticChunkText(_ text: String, fileId: UUID, imageMetadata: [PDFImageMetadata]) -> [DocumentChunk] {
        let paragraphs = extractParagraphs(from: text)
        var context = ChunkingContext(fileId: fileId)

        for paragraph in paragraphs {
            processParagraph(paragraph, context: &context)
        }

        finalizeChunks(context: &context)

        // P1.2: Chunk'lara sayfa bazlı görsel referansları ekle
        var chunks = assignImageReferences(to: context.chunks, from: imageMetadata)

        // P3.3: Tekrarlayan chunk'ları kaldır
        chunks = deduplicateChunks(chunks)

        return chunks
    }

    // MARK: - P3.3: Chunk Deduplication

    /// Benzer veya tekrarlayan chunk'ları tespit edip kaldırır
    private func deduplicateChunks(_ chunks: [DocumentChunk]) -> [DocumentChunk] {
        guard chunks.count > 1 else { return chunks }

        var uniqueChunks: [DocumentChunk] = []
        var seenHashes: Set<String> = []

        for chunk in chunks {
            // İçerik hash'i oluştur (normalleştirilmiş)
            let normalizedContent = normalizeForDedup(chunk.content)
            let hash = contentHash(normalizedContent)

            // Tam tekrar kontrolü
            if seenHashes.contains(hash) {
                logDebug("RAGChunker", "Tekrarlayan chunk atlandı", details: "Index: \(chunk.chunkIndex)")
                continue
            }

            // Yüksek benzerlik kontrolü (önceki chunk ile)
            if let lastChunk = uniqueChunks.last {
                let similarity = calculateJaccardSimilarity(
                    normalizeForDedup(lastChunk.content),
                    normalizedContent
                )
                if similarity > 0.85 {
                    // Çok benzer - birleştir (daha uzun olanı tut)
                    if chunk.content.count > lastChunk.content.count {
                        uniqueChunks.removeLast()
                        uniqueChunks.append(chunk)
                        seenHashes.insert(hash)
                    }
                    logDebug("RAGChunker", "Benzer chunk birleştirildi", details: "Similarity: \(similarity)")
                    continue
                }
            }

            seenHashes.insert(hash)
            uniqueChunks.append(chunk)
        }

        if uniqueChunks.count < chunks.count {
            logInfo("RAGChunker", "Deduplication tamamlandı",
                    details: "\(chunks.count) → \(uniqueChunks.count) chunk")
        }

        return uniqueChunks
    }

    /// İçeriği deduplication için normalleştirir
    private func normalizeForDedup(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Basit içerik hash'i (ilk ve son 50 karakter + uzunluk)
    private func contentHash(_ text: String) -> String {
        let prefix = String(text.prefix(50))
        let suffix = String(text.suffix(50))
        return "\(prefix)|\(text.count)|\(suffix)"
    }

    /// Jaccard benzerlik skoru hesaplar (kelime bazlı)
    private func calculateJaccardSimilarity(_ text1: String, _ text2: String) -> Float {
        let words1 = Set(text1.split(separator: " ").map(String.init))
        let words2 = Set(text2.split(separator: " ").map(String.init))

        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count

        guard union > 0 else { return 0 }
        return Float(intersection) / Float(union)
    }

    // MARK: - P1.2: Image Reference Assignment

    /// Her chunk'a ilgili görsellerin ID'lerini atar (sayfa örtüşmesine göre)
    private func assignImageReferences(
        to chunks: [DocumentChunk],
        from images: [PDFImageMetadata]
    ) -> [DocumentChunk] {
        guard !images.isEmpty else { return chunks }

        // Görselleri sayfa numarasına göre grupla
        let imagesByPage = Dictionary(grouping: images, by: { $0.pageNumber })

        return chunks.map { chunk in
            var updatedChunk = chunk

            // Chunk'ın kapsadığı sayfa aralığını belirle
            let startPage = chunk.startPage ?? chunk.pageNumber ?? 0
            let endPage = chunk.endPage ?? chunk.pageNumber ?? startPage

            // Bu sayfa aralığındaki tüm görselleri topla
            var relevantImages: [UUID] = []
            for page in startPage...max(startPage, endPage) {
                if let pageImages = imagesByPage[page] {
                    relevantImages.append(contentsOf: pageImages.map { $0.id })
                }
            }

            if !relevantImages.isEmpty {
                updatedChunk = DocumentChunk(
                    id: chunk.id,
                    fileId: chunk.fileId,
                    chunkIndex: chunk.chunkIndex,
                    content: chunk.content,
                    pageNumber: chunk.pageNumber,
                    startPage: chunk.startPage,
                    endPage: chunk.endPage,
                    sectionTitle: chunk.sectionTitle,
                    contentType: chunk.contentType,
                    containsTable: chunk.containsTable,
                    containsList: chunk.containsList,
                    imageReferences: relevantImages
                )
            }

            return updatedChunk
        }
    }

    // MARK: - Helper Methods

    private func processParagraph(_ paragraph: Paragraph, context: inout ChunkingContext) {
        // Başlık kontrolü - yeni bölüm başlıyorsa mevcut chunk'ı kapat
        if let heading = detectHeading(in: paragraph) {
            if !context.sentences.isEmpty && context.wordCount >= RAGConfig.minChunkSize {
                createAndAppendChunk(context: &context)
            }
            context.currentHeading = heading
            context.contentType = .heading
        }

        // P1: Paragrafta tablo veya liste var mı kontrol et
        let paragraphText = paragraph.text
        if detectTable(in: paragraphText) {
            context.containsTable = true
            context.contentType = context.containsList ? .mixed : .table
        }
        if detectList(in: paragraphText) {
            context.containsList = true
            context.contentType = context.containsTable ? .mixed : .list
        }

        for sentence in paragraph.sentences {
            if sentence.isPageBreak {
                handlePageBreak(sentence: sentence, context: &context)
                continue
            }

            // İlk sayfa numarasını belirle
            if context.startPage == nil {
                context.startPage = sentence.pageNumber ?? paragraph.pageNumber
            }
            context.endPage = sentence.pageNumber ?? paragraph.pageNumber ?? context.endPage

            // Cümleyi ekle
            context.sentences.append(sentence)
            context.wordCount += sentence.wordCount

            checkAndCreateChunk(context: &context)
        }

        // Paragraf sonu kontrolü
        if context.wordCount >= RAGConfig.targetChunkSize && !context.sentences.isEmpty {
            createAndAppendChunk(context: &context)
        }
    }

    // MARK: - P1/P2: Tablo Algılama (Enhanced)
    private func detectTable(in text: String) -> Bool {
        // P2: PDFTextExtractor'dan gelen tablo marker'larını kontrol et
        if text.contains("[TABLO_BAŞLANGIÇ]") || text.contains("[TABLO_BİTİŞ]") {
            return true
        }

        let range = NSRange(text.startIndex..., in: text)

        for pattern in tablePatterns {
            if pattern.firstMatch(in: text, options: [], range: range) != nil {
                return true
            }
        }

        // Ek heuristic: Çok sayıda tab veya çoklu boşluk = muhtemel tablo
        let tabCount = text.filter { $0 == "\t" }.count
        let multiSpaceMatches = text.range(of: #"\s{3,}"#, options: .regularExpression)
        let lineCount = text.components(separatedBy: .newlines).count

        // En az 2 satır ve her satırda ortalama 2+ tab varsa tablo olabilir
        if lineCount >= 2 && tabCount >= lineCount * 2 {
            return true
        }

        // Çoklu boşluk ile ayrılmış veri satırları
        if multiSpaceMatches != nil && lineCount >= 3 {
            let lines = text.components(separatedBy: .newlines)
            let linesWithMultiSpace = lines.filter { $0.range(of: #"\s{3,}"#, options: .regularExpression) != nil }
            if linesWithMultiSpace.count >= lineCount / 2 {
                return true
            }
        }

        return false
    }

    // MARK: - P1: Liste Algılama
    private func detectList(in text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines)
        var listItemCount = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let range = NSRange(trimmed.startIndex..., in: trimmed)

            for pattern in listPatterns {
                if pattern.firstMatch(in: trimmed, options: [], range: range) != nil {
                    listItemCount += 1
                    break
                }
            }
        }

        // En az 2 liste elemanı varsa liste kabul et
        return listItemCount >= 2
    }

    /// Paragrafın başlık olup olmadığını kontrol eder
    private func detectHeading(in paragraph: Paragraph) -> String? {
        guard let firstSentence = paragraph.sentences.first(where: { !$0.isPageBreak }),
              !firstSentence.text.isEmpty else {
            return nil
        }

        let text = firstSentence.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(text.startIndex..., in: text)

        // Pattern eşleşmesi
        for pattern in headingPatterns {
            if pattern.firstMatch(in: text, options: [], range: range) != nil {
                return text
            }
        }

        // Kısa satır + büyük harfle başlama = muhtemel başlık
        if text.count < 80,
           firstSentence.wordCount <= 10,
           text.first?.isUppercase == true,
           !text.contains(". ") { // Cümle içermiyor
            return text
        }

        return nil
    }

    private func handlePageBreak(sentence: Sentence, context: inout ChunkingContext) {
        if !context.sentences.isEmpty && context.wordCount >= RAGConfig.minChunkSize {
            createAndAppendChunk(context: &context)
        }
        context.startPage = sentence.pageNumber
    }

    private func checkAndCreateChunk(context: inout ChunkingContext) {
        if context.wordCount >= RAGConfig.targetChunkSize {
            if context.wordCount >= RAGConfig.maxChunkSize {
                createAndAppendChunk(context: &context)
            }
        }
    }

    private func createAndAppendChunk(context: inout ChunkingContext) {
        let chunk = createChunk(
            sentences: context.sentences,
            fileId: context.fileId,
            chunkIndex: context.chunkIndex,
            startPage: context.startPage,
            endPage: context.endPage,
            sectionTitle: context.currentHeading,
            contentType: context.contentType,
            containsTable: context.containsTable,
            containsList: context.containsList
        )
        context.chunks.append(chunk)
        context.chunkIndex += 1

        // Overlap
        applyOverlap(context: &context)
    }

    private func applyOverlap(context: inout ChunkingContext) {
        let overlapStart = max(0, context.sentences.count - RAGConfig.overlapSentences)
        context.sentences = Array(context.sentences[overlapStart...])
        context.wordCount = context.sentences.reduce(0) { $0 + $1.wordCount }
        context.startPage = context.sentences.first?.pageNumber

        // P1: Yeni chunk için metadata'yı sıfırla (heading hariç - devam eder)
        context.containsTable = false
        context.containsList = false
        context.contentType = .text
    }

    private func finalizeChunks(context: inout ChunkingContext) {
        if !context.sentences.isEmpty && context.wordCount >= RAGConfig.minChunkSize {
            let chunk = createChunk(
                sentences: context.sentences,
                fileId: context.fileId,
                chunkIndex: context.chunkIndex,
                startPage: context.startPage,
                endPage: context.endPage,
                sectionTitle: context.currentHeading,
                contentType: context.contentType,
                containsTable: context.containsTable,
                containsList: context.containsList
            )
            context.chunks.append(chunk)
        } else if !context.sentences.isEmpty && !context.chunks.isEmpty {
            // Çok kısa - son chunk'a ekle (metadata'yı koru)
            var lastChunk = context.chunks.removeLast()
            let additionalText = context.sentences.map { $0.text }.joined(separator: " ")
            lastChunk = DocumentChunk(
                id: lastChunk.id,
                fileId: lastChunk.fileId,
                chunkIndex: lastChunk.chunkIndex,
                content: lastChunk.content + " " + additionalText,
                pageNumber: lastChunk.pageNumber,
                startPage: lastChunk.startPage,
                endPage: context.endPage,
                sectionTitle: lastChunk.sectionTitle,
                contentType: lastChunk.contentType,
                containsTable: lastChunk.containsTable || context.containsTable,
                containsList: lastChunk.containsList || context.containsList,
                imageReferences: lastChunk.imageReferences
            )
            context.chunks.append(lastChunk)
        }
    }

    /// Metni paragraflara ayırır (P2: Enhanced)
    private func extractParagraphs(from text: String) -> [Paragraph] {
        var paragraphs: [Paragraph] = []
        var currentPageNumber: Int = 1

        // Çift newline'ları paragraf ayırıcı olarak kullan
        let rawParagraphs = text.components(separatedBy: "\n\n")

        for rawParagraph in rawParagraphs {
            let trimmed = rawParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            var sentences: [Sentence] = []

            // P2: Tablo marker'larını özel olarak işle - tablo içeriğini tek parça olarak tut
            if trimmed.contains("[TABLO_BAŞLANGIÇ]") {
                // Tablo içeriğini tek bir cümle olarak ekle (bölünmesin)
                let tableContent = trimmed
                    .replacingOccurrences(of: "[TABLO_BAŞLANGIÇ]", with: "")
                    .replacingOccurrences(of: "[TABLO_BİTİŞ]", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !tableContent.isEmpty {
                    let wordCount = tableContent.split(separator: " ").count
                    sentences.append(Sentence(
                        text: "[TABLO]\n" + tableContent,
                        wordCount: wordCount,
                        isPageBreak: false,
                        pageNumber: currentPageNumber
                    ))
                }

                if !sentences.isEmpty {
                    paragraphs.append(Paragraph(sentences: sentences, pageNumber: currentPageNumber))
                }
                continue
            }

            // P2: Sayfa marker kontrolü (hem "Sayfa X" hem "Sayfa X/Y" formatını destekle)
            if trimmed.hasPrefix("--- Sayfa ") {
                // Sayfa numarasını çıkar (X veya X/Y formatı)
                let scanner = Scanner(string: trimmed)
                _ = scanner.scanString("--- Sayfa ")
                var pageNum: Int = 0
                if scanner.scanInt(&pageNum) {
                    currentPageNumber = pageNum
                    // Sayfa break cümlesi ekle
                    sentences.append(Sentence(
                        text: "",
                        wordCount: 0,
                        isPageBreak: true,
                        pageNumber: pageNum
                    ))
                }

                // Sayfa marker'dan sonraki içeriği al (hem X hem X/Y formatını temizle)
                let remaining = trimmed.replacingOccurrences(
                    of: #"^--- Sayfa \d+(?:/\d+)? ---\n?"#,
                    with: "",
                    options: .regularExpression
                )
                if !remaining.isEmpty {
                    sentences.append(contentsOf: extractSentences(from: remaining, pageNumber: currentPageNumber))
                }
            } else {
                sentences = extractSentences(from: trimmed, pageNumber: currentPageNumber)
            }

            if !sentences.isEmpty {
                paragraphs.append(Paragraph(sentences: sentences, pageNumber: currentPageNumber))
            }
        }

        return paragraphs
    }

    /// Paragrafı cümlelere ayırır
    private func extractSentences(from text: String, pageNumber: Int) -> [Sentence] {
        var sentences: [Sentence] = []

        // Cümle sonu karakterleri: . ! ? : (parantez içi cümleleri koru)
        // Kısaltmaları koru: Dr. Prof. vb.
        let pattern = #"(?<=[.!?:])\s+(?=[A-ZÇĞİÖŞÜ\d"\[])"#

        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(text.startIndex..., in: text)

        var lastEnd = text.startIndex
        let matches = regex?.matches(in: text, options: [], range: range) ?? []

        for match in matches {
            if let matchRange = Range(match.range, in: text) {
                let sentenceText = String(text[lastEnd..<matchRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !sentenceText.isEmpty {
                    let wordCount = sentenceText.split(separator: " ").count
                    sentences.append(Sentence(
                        text: sentenceText,
                        wordCount: wordCount,
                        isPageBreak: false,
                        pageNumber: pageNumber
                    ))
                }
                lastEnd = matchRange.upperBound
            }
        }

        // Son cümle
        let remaining = String(text[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            let wordCount = remaining.split(separator: " ").count
            sentences.append(Sentence(
                text: remaining,
                wordCount: wordCount,
                isPageBreak: false,
                pageNumber: pageNumber
            ))
        }

        return sentences
    }

    /// Cümlelerden chunk oluşturur (P1: Zengin metadata ile)
    private func createChunk(
        sentences: [Sentence],
        fileId: UUID,
        chunkIndex: Int,
        startPage: Int?,
        endPage: Int?,
        sectionTitle: String? = nil,
        contentType: ChunkContentType = .text,
        containsTable: Bool = false,
        containsList: Bool = false,
        imageReferences: [UUID] = []
    ) -> DocumentChunk {
        let content = sentences
            .filter { !$0.isPageBreak }
            .map { $0.text }
            .joined(separator: " ")

        return DocumentChunk(
            fileId: fileId,
            chunkIndex: chunkIndex,
            content: content,
            pageNumber: startPage ?? endPage,
            startPage: startPage,
            endPage: endPage,
            sectionTitle: sectionTitle,
            contentType: contentType,
            containsTable: containsTable,
            containsList: containsList,
            imageReferences: imageReferences
        )
    }
}
