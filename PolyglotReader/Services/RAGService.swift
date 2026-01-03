import Foundation
import Combine
import CryptoKit

// MARK: - RAG Configuration (Maksimum Doğruluk Modu)
enum RAGConfig {
    // Semantic Chunking Settings
    static let targetChunkSize = 300        // Daha küçük chunk = daha hassas arama
    static let minChunkSize = 40            // Minimum kelime
    static let maxChunkSize = 450           // Maximum kelime
    static let overlapSentences = 3         // Daha fazla overlap = daha iyi bağlam
    
    // Search Settings - PERFORMANS + DOĞRULUK DENGESİ
    static let topK = 8                     // Optimum aday sayısı (hız için düşürüldü)
    static let rerankTopK = 6               // Context'e dahil edilecek chunk
    static let similarityThreshold: Float = 0.30  // Düşük eşik = garantili sonuç
    static let bm25Weight: Float = 0.35     // BM25 biraz artırıldı (keyword matching)
    static let vectorWeight: Float = 0.65   // Vector ağırlığı
    static let rrfK: Float = 60             // RRF k parametresi
    
    // Token Limits - Gemini 1M token destekliyor
    static let maxContextTokens = 20000     // Çok geniş context
    static let tokenMultiplier: Float = 1.3 // Kelime -> token çarpanı
    
    // Cache Settings
    static let cacheMaxSize = 300           // Daha büyük cache
    static let cacheTTL: TimeInterval = 7200 // 2 saat
    
    // API Settings
    static let embeddingModel = "text-embedding-004"
    static let embeddingDimension = 768
    static let rateLimitDelay: UInt64 = 30_000_000 // 30ms (hızlandırıldı)
}

// MARK: - Sentence Structure
private struct Sentence {
    let text: String
    let wordCount: Int
    let isPageBreak: Bool
    let pageNumber: Int?
}

// MARK: - Paragraph Structure
private struct Paragraph {
    let sentences: [Sentence]
    let pageNumber: Int?
    
    var wordCount: Int {
        sentences.reduce(0) { $0 + $1.wordCount }
    }
    
    var text: String {
        sentences.map { $0.text }.joined(separator: " ")
    }
}

// MARK: - Cache Entry
private struct EmbeddingCacheEntry {
    let embedding: [Float]
    let timestamp: Date
    let queryHash: String
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > RAGConfig.cacheTTL
    }
}

// MARK: - Document Chunk Model
struct DocumentChunk: Codable, Identifiable {
    let id: UUID
    var fileId: UUID
    var chunkIndex: Int
    var content: String
    var pageNumber: Int?
    var startPage: Int?   // Chunk birden fazla sayfaya yayılabilir
    var endPage: Int?
    var similarity: Float? // Arama sonucu için
    
    init(id: UUID = UUID(), fileId: UUID, chunkIndex: Int, content: String, 
         pageNumber: Int? = nil, startPage: Int? = nil, endPage: Int? = nil, similarity: Float? = nil) {
        self.id = id
        self.fileId = fileId
        self.chunkIndex = chunkIndex
        self.content = content
        self.pageNumber = pageNumber
        self.startPage = startPage
        self.endPage = endPage
        self.similarity = similarity
    }
}

// MARK: - Search Result with Score
struct ScoredChunk {
    let chunk: DocumentChunk
    var vectorScore: Float
    var bm25Score: Float
    var rrfScore: Float
    var rerankScore: Float?
    
    var finalScore: Float {
        rerankScore ?? rrfScore
    }
}

// MARK: - RAG Service
@MainActor
class RAGService: ObservableObject {
    static let shared = RAGService()
    
    @Published var isIndexing = false
    @Published var indexingProgress: Float = 0
    @Published var currentOperation: String = ""
    
    private let geminiApiKey = Config.geminiApiKey
    
    // MARK: - Embedding Cache (LRU)
    private var embeddingCache: [String: EmbeddingCacheEntry] = [:]
    private var cacheAccessOrder: [String] = []
    
    private init() {
        logInfo("RAGService", "Profesyonel RAG Servisi başlatıldı v2.0")
    }
    
    // MARK: - Faz 1: Semantic Chunking
    
    /// Cümle ve paragraf sınırlarına saygılı akıllı chunking
    func semanticChunkText(_ text: String, fileId: UUID) -> [DocumentChunk] {
        logInfo("RAGService", "Semantic chunking başlatılıyor")
        
        // 1. Metni paragraflara ayır
        let paragraphs = extractParagraphs(from: text)
        
        // 2. Chunk'ları oluştur
        var chunks: [DocumentChunk] = []
        var currentSentences: [Sentence] = []
        var currentWordCount = 0
        var chunkIndex = 0
        var startPage: Int? = nil
        var endPage: Int? = nil
        
        for paragraph in paragraphs {
            for sentence in paragraph.sentences {
                // Sayfa break kontrolü
                if sentence.isPageBreak {
                    // Mevcut chunk'ı kaydet (eğer varsa)
                    if !currentSentences.isEmpty && currentWordCount >= RAGConfig.minChunkSize {
                        let chunk = createChunk(
                            sentences: currentSentences,
                            fileId: fileId,
                            chunkIndex: chunkIndex,
                            startPage: startPage,
                            endPage: endPage
                        )
                        chunks.append(chunk)
                        chunkIndex += 1
                        
                        // Overlap: son N cümleyi sakla
                        let overlapStart = max(0, currentSentences.count - RAGConfig.overlapSentences)
                        currentSentences = Array(currentSentences[overlapStart...])
                        currentWordCount = currentSentences.reduce(0) { $0 + $1.wordCount }
                    }
                    startPage = sentence.pageNumber
                    continue
                }
                
                // İlk sayfa numarasını belirle
                if startPage == nil {
                    startPage = sentence.pageNumber ?? paragraph.pageNumber
                }
                endPage = sentence.pageNumber ?? paragraph.pageNumber ?? endPage
                
                // Cümleyi ekle
                currentSentences.append(sentence)
                currentWordCount += sentence.wordCount
                
                // Hedef boyuta ulaşıldı mı?
                if currentWordCount >= RAGConfig.targetChunkSize {
                    // Maximum aşıldı mı?
                    if currentWordCount >= RAGConfig.maxChunkSize {
                        let chunk = createChunk(
                            sentences: currentSentences,
                            fileId: fileId,
                            chunkIndex: chunkIndex,
                            startPage: startPage,
                            endPage: endPage
                        )
                        chunks.append(chunk)
                        chunkIndex += 1
                        
                        // Overlap
                        let overlapStart = max(0, currentSentences.count - RAGConfig.overlapSentences)
                        currentSentences = Array(currentSentences[overlapStart...])
                        currentWordCount = currentSentences.reduce(0) { $0 + $1.wordCount }
                        startPage = currentSentences.first?.pageNumber
                    }
                }
            }
            
            // Paragraf sonu - uzun chunk'ları paragraf sınırında kes
            if currentWordCount >= RAGConfig.targetChunkSize && !currentSentences.isEmpty {
                let chunk = createChunk(
                    sentences: currentSentences,
                    fileId: fileId,
                    chunkIndex: chunkIndex,
                    startPage: startPage,
                    endPage: endPage
                )
                chunks.append(chunk)
                chunkIndex += 1
                
                // Overlap
                let overlapStart = max(0, currentSentences.count - RAGConfig.overlapSentences)
                currentSentences = Array(currentSentences[overlapStart...])
                currentWordCount = currentSentences.reduce(0) { $0 + $1.wordCount }
                startPage = currentSentences.first?.pageNumber
            }
        }
        
        // Kalan cümleleri son chunk olarak kaydet
        if !currentSentences.isEmpty && currentWordCount >= RAGConfig.minChunkSize {
            let chunk = createChunk(
                sentences: currentSentences,
                fileId: fileId,
                chunkIndex: chunkIndex,
                startPage: startPage,
                endPage: endPage
            )
            chunks.append(chunk)
        } else if !currentSentences.isEmpty && !chunks.isEmpty {
            // Çok kısa - son chunk'a ekle
            var lastChunk = chunks.removeLast()
            let additionalText = currentSentences.map { $0.text }.joined(separator: " ")
            lastChunk = DocumentChunk(
                id: lastChunk.id,
                fileId: lastChunk.fileId,
                chunkIndex: lastChunk.chunkIndex,
                content: lastChunk.content + " " + additionalText,
                pageNumber: lastChunk.pageNumber,
                startPage: lastChunk.startPage,
                endPage: endPage
            )
            chunks.append(lastChunk)
        }
        
        logInfo("RAGService", "Semantic chunking tamamlandı", details: "\(chunks.count) chunk oluşturuldu")
        return chunks
    }
    
    /// Metni paragraflara ayırır
    private func extractParagraphs(from text: String) -> [Paragraph] {
        var paragraphs: [Paragraph] = []
        var currentPageNumber: Int = 1
        
        // Çift newline'ları paragraf ayırıcı olarak kullan
        let rawParagraphs = text.components(separatedBy: "\n\n")
        
        for rawParagraph in rawParagraphs {
            let trimmed = rawParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            var sentences: [Sentence] = []
            
            // Sayfa marker kontrolü
            if trimmed.hasPrefix("--- Sayfa ") {
                // Sayfa numarasını çıkar
                let scanner = Scanner(string: trimmed)
                scanner.scanString("--- Sayfa ", into: nil)
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
                
                // Sayfa marker'dan sonraki içeriği al
                let remaining = trimmed.replacingOccurrences(
                    of: "^--- Sayfa \\d+ ---\\n?",
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
    
    /// Cümlelerden chunk oluşturur
    private func createChunk(sentences: [Sentence], fileId: UUID, chunkIndex: Int, 
                            startPage: Int?, endPage: Int?) -> DocumentChunk {
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
            endPage: endPage
        )
    }
    
    // MARK: - Faz 4: Embedding Cache
    
    /// Cache hash oluşturur
    private func cacheKey(for text: String) -> String {
        let data = Data(text.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Cache'ten embedding al veya oluştur
    func getOrCreateEmbedding(for text: String) async throws -> [Float] {
        let key = cacheKey(for: text)
        
        // Cache hit kontrolü
        if let entry = embeddingCache[key], !entry.isExpired {
            logDebug("RAGService", "Embedding cache hit")
            updateCacheAccess(key: key)
            return entry.embedding
        }
        
        // Cache miss - yeni embedding oluştur
        logDebug("RAGService", "Embedding cache miss, oluşturuluyor...")
        let embedding = try await createEmbeddingFromAPI(for: text)
        
        // Cache'e ekle
        addToCache(key: key, embedding: embedding)
        
        return embedding
    }
    
    /// Cache'e embedding ekler (LRU eviction ile)
    private func addToCache(key: String, embedding: [Float]) {
        // Önce eski key'i kaldır (varsa)
        if embeddingCache[key] != nil {
            cacheAccessOrder.removeAll { $0 == key }
        }
        
        // LRU eviction
        while embeddingCache.count >= RAGConfig.cacheMaxSize {
            if let oldestKey = cacheAccessOrder.first {
                embeddingCache.removeValue(forKey: oldestKey)
                cacheAccessOrder.removeFirst()
            } else {
                break
            }
        }
        
        // Yeni entry ekle
        embeddingCache[key] = EmbeddingCacheEntry(
            embedding: embedding,
            timestamp: Date(),
            queryHash: key
        )
        cacheAccessOrder.append(key)
    }
    
    /// Cache erişim sırasını günceller
    private func updateCacheAccess(key: String) {
        cacheAccessOrder.removeAll { $0 == key }
        cacheAccessOrder.append(key)
    }
    
    /// Cache'i temizler
    func clearCache() {
        embeddingCache.removeAll()
        cacheAccessOrder.removeAll()
        logInfo("RAGService", "Embedding cache temizlendi")
    }
    
    // MARK: - Embedding Generation (API)
    
    /// Gemini API'den embedding oluşturur
    private func createEmbeddingFromAPI(for text: String) async throws -> [Float] {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(RAGConfig.embeddingModel):embedContent?key=\(geminiApiKey)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": "models/\(RAGConfig.embeddingModel)",
            "content": [
                "parts": [
                    ["text": text]
                ]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            if let httpResponse = response as? HTTPURLResponse {
                logError("RAGService", "Embedding API hatası - Status: \(httpResponse.statusCode)")
            }
            throw RAGError.embeddingFailed
        }
        
        struct EmbeddingResponse: Decodable {
            struct Embedding: Decodable {
                let values: [Float]
            }
            let embedding: Embedding
        }
        
        let result = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
        return result.embedding.values
    }
    
    // MARK: - Backward Compatibility
    
    /// Eski chunkText metodu (semantic chunking'e yönlendir)
    func chunkText(_ text: String, fileId: UUID) -> [DocumentChunk] {
        return semanticChunkText(text, fileId: fileId)
    }
    
    /// Eski createEmbedding metodu (cache ile)
    func createEmbedding(for text: String) async throws -> [Float] {
        return try await getOrCreateEmbedding(for: text)
    }
    
    // MARK: - Document Indexing
    
    /// PDF dokümanını indexler (semantic chunk'lar + embedding'ler)
    func indexDocument(text: String, fileId: UUID) async throws {
        isIndexing = true
        indexingProgress = 0
        currentOperation = "Metin analiz ediliyor..."
        defer { 
            isIndexing = false 
            indexingProgress = 1
            currentOperation = ""
        }
        
        logInfo("RAGService", "Doküman indexleniyor", details: "FileID: \(fileId)")
        
        // 1. Semantic chunking
        currentOperation = "Semantic chunking..."
        let chunks = semanticChunkText(text, fileId: fileId)
        
        guard !chunks.isEmpty else {
            logWarning("RAGService", "Chunk oluşturulamadı")
            return
        }
        
        // 2. Her chunk için embedding oluştur
        currentOperation = "Embedding oluşturuluyor..."
        var chunksWithEmbeddings: [(chunk: DocumentChunk, embedding: [Float])] = []
        
        for (index, chunk) in chunks.enumerated() {
            do {
                let embedding = try await getOrCreateEmbedding(for: chunk.content)
                chunksWithEmbeddings.append((chunk, embedding))
                
                indexingProgress = Float(index + 1) / Float(chunks.count) * 0.9 // %90'a kadar
                
            } catch {
                logWarning("RAGService", "Chunk \(index) için embedding hatası", details: error.localizedDescription)
            }
            
            // Rate limiting
            if index < chunks.count - 1 {
                try? await Task.sleep(nanoseconds: RAGConfig.rateLimitDelay)
            }
        }
        
        // 3. Supabase'e kaydet
        currentOperation = "Veritabanına kaydediliyor..."
        try await SupabaseService.shared.saveDocumentChunks(chunksWithEmbeddings)
        
        indexingProgress = 1.0
        logInfo("RAGService", "Doküman indexlendi", details: "\(chunksWithEmbeddings.count) chunk kaydedildi")
    }
    
    // MARK: - Faz 3: Hybrid Search
    
    /// Vector + BM25 hybrid search (RRF fusion)
    func hybridSearch(query: String, fileId: UUID, topK: Int = RAGConfig.topK) async throws -> [ScoredChunk] {
        logInfo("RAGService", "Hybrid search başlatılıyor")
        
        // 1. Query için embedding oluştur (cache'li)
        let queryEmbedding = try await getOrCreateEmbedding(for: query)
        
        // 2. Paralel olarak vector ve BM25 araması yap
        async let vectorResultsTask = SupabaseService.shared.searchSimilarChunks(
            embedding: queryEmbedding,
            fileId: fileId,
            limit: topK,
            similarityThreshold: RAGConfig.similarityThreshold
        )
        
        // BM25 araması (Supabase full-text search)
        async let bm25ResultsTask = SupabaseService.shared.searchChunksBM25(
            query: query,
            fileId: fileId,
            limit: topK
        )
        
        let vectorResults = try await vectorResultsTask
        let bm25Results = (try? await bm25ResultsTask) ?? []
        
        logDebug("RAGService", "Vector sonuçları: \(vectorResults.count), BM25 sonuçları: \(bm25Results.count)")
        
        // 3. RRF Fusion
        let fusedResults = reciprocalRankFusion(
            vectorResults: vectorResults,
            bm25Results: bm25Results
        )
        
        logInfo("RAGService", "Hybrid search tamamlandı", details: "\(fusedResults.count) sonuç")
        return fusedResults
    }
    
    /// Reciprocal Rank Fusion algoritması
    private func reciprocalRankFusion(vectorResults: [DocumentChunk], bm25Results: [DocumentChunk]) -> [ScoredChunk] {
        var scoreMap: [UUID: ScoredChunk] = [:]
        
        // Vector sonuçlarını skorla
        for (rank, chunk) in vectorResults.enumerated() {
            let vectorScore = 1.0 / (RAGConfig.rrfK + Float(rank + 1))
            
            if var existing = scoreMap[chunk.id] {
                existing.vectorScore = vectorScore * RAGConfig.vectorWeight
                existing.rrfScore += vectorScore * RAGConfig.vectorWeight
                scoreMap[chunk.id] = existing
            } else {
                scoreMap[chunk.id] = ScoredChunk(
                    chunk: chunk,
                    vectorScore: vectorScore * RAGConfig.vectorWeight,
                    bm25Score: 0,
                    rrfScore: vectorScore * RAGConfig.vectorWeight
                )
            }
        }
        
        // BM25 sonuçlarını skorla
        for (rank, chunk) in bm25Results.enumerated() {
            let bm25Score = 1.0 / (RAGConfig.rrfK + Float(rank + 1))
            
            if var existing = scoreMap[chunk.id] {
                existing.bm25Score = bm25Score * RAGConfig.bm25Weight
                existing.rrfScore += bm25Score * RAGConfig.bm25Weight
                scoreMap[chunk.id] = existing
            } else {
                scoreMap[chunk.id] = ScoredChunk(
                    chunk: chunk,
                    vectorScore: 0,
                    bm25Score: bm25Score * RAGConfig.bm25Weight,
                    rrfScore: bm25Score * RAGConfig.bm25Weight
                )
            }
        }
        
        // Skora göre sırala
        return scoreMap.values.sorted { $0.rrfScore > $1.rrfScore }
    }
    
    // MARK: - Faz 2: Token-Aware Context Building
    
    /// Token limitine göre context oluşturur
    func buildContextWithTokenLimit(from scoredChunks: [ScoredChunk], 
                                    maxTokens: Int = RAGConfig.maxContextTokens) -> String {
        var context = "İlgili doküman bölümleri:\n\n"
        var currentTokens = estimateTokens(context)
        var includedCount = 0
        
        for scored in scoredChunks {
            let chunk = scored.chunk
            let pageInfo: String
            if let start = chunk.startPage, let end = chunk.endPage, start != end {
                pageInfo = " (Sayfa \(start)-\(end))"
            } else if let page = chunk.pageNumber ?? chunk.startPage {
                pageInfo = " (Sayfa \(page))"
            } else {
                pageInfo = ""
            }
            
            let chunkText = "[\(includedCount + 1)]\(pageInfo):\n\(chunk.content)\n\n"
            let chunkTokens = estimateTokens(chunkText)
            
            // Token limiti kontrolü
            if currentTokens + chunkTokens > maxTokens {
                logDebug("RAGService", "Token limiti aşıldı, \(includedCount) chunk dahil edildi")
                break
            }
            
            context += chunkText
            currentTokens += chunkTokens
            includedCount += 1
        }
        
        logInfo("RAGService", "Context oluşturuldu", details: "\(includedCount) chunk, ~\(currentTokens) token")
        return context
    }
    
    /// Token tahmini (kelime * multiplier)
    private func estimateTokens(_ text: String) -> Int {
        let wordCount = text.split(separator: " ").count
        return Int(Float(wordCount) * RAGConfig.tokenMultiplier)
    }
    
    // MARK: - Backward Compatible buildContext
    
    func buildContext(from chunks: [DocumentChunk]) -> String {
        let scoredChunks = chunks.map { ScoredChunk(chunk: $0, vectorScore: 1.0, bm25Score: 0, rrfScore: 1.0) }
        return buildContextWithTokenLimit(from: scoredChunks)
    }
    
    // MARK: - Similarity Search (Backward Compatible)
    
    /// Kullanıcı sorusuna en alakalı chunk'ları bulur (hybrid search kullanır)
    func searchRelevantChunks(query: String, fileId: UUID, topK: Int = RAGConfig.topK) async throws -> [DocumentChunk] {
        let scoredChunks = try await hybridSearch(query: query, fileId: fileId, topK: topK)
        return scoredChunks.prefix(topK).map { $0.chunk }
    }
    
    // MARK: - Full RAG Pipeline

    /// Tam RAG pipeline: Query Expansion -> Hybrid Search -> Rerank -> Token Limit -> Context
    /// NOT: Reranking varsayılan olarak kapalı (Gemini API çağrısı ~10 saniye ekliyor)
    func performRAGQuery(
        query: String,
        fileId: UUID,
        enableRerank: Bool = false,  // Varsayılan KAPALI - çok yavaş
        enableQueryExpansion: Bool = false
    ) async throws -> (context: String, chunks: [DocumentChunk]) {
        logInfo("RAGService", "Full RAG pipeline başlatılıyor")

        var searchQuery = query
        
        // 0. CROSS-LINGUAL: Türkçe sorguyu İngilizce'ye çevir (İngilizce dokümanlar için)
        // Bu adım embedding benzerliğini dramatik şekilde artırır
        do {
            let translatedQuery = try await GeminiService.shared.translateQueryForSearch(query)
            if translatedQuery != query {
                searchQuery = translatedQuery
                logInfo("RAGService", "Query çevrildi", 
                       details: "TR: \(query.prefix(40))... → EN: \(translatedQuery.prefix(40))...")
            }
        } catch {
            logWarning("RAGService", "Query çevirisi atlandı", details: error.localizedDescription)
        }

        // 1. Query Expansion (opsiyonel - kısa sorgular için faydalı)
        if enableQueryExpansion && searchQuery.split(separator: " ").count <= 5 {
            do {
                let expanded = try await GeminiService.shared.expandQuery(searchQuery)
                searchQuery = expanded.expanded

                // HyDE: Varsayımsal cevap için de embedding oluştur
                if let hydeAnswer = expanded.hypotheticalAnswer {
                    let hydeEmbedding = try await getOrCreateEmbedding(for: hydeAnswer)
                    // HyDE embedding'i ile ek arama yap
                    let hydeResults = try await SupabaseService.shared.searchSimilarChunks(
                        embedding: hydeEmbedding,
                        fileId: fileId,
                        limit: 4,
                        similarityThreshold: RAGConfig.similarityThreshold
                    )

                    if !hydeResults.isEmpty {
                        logDebug("RAGService", "HyDE ek sonuçlar", details: "\(hydeResults.count) chunk")
                    }
                }

                logDebug("RAGService", "Query expansion tamamlandı",
                        details: "Orijinal: \(query.prefix(30))... -> Expanded: \(searchQuery.prefix(30))...")
            } catch {
                logWarning("RAGService", "Query expansion atlandı", details: error.localizedDescription)
                // searchQuery zaten çevrilmiş halde, devam et
            }
        }

        // 1. Hybrid search
        var scoredChunks = try await hybridSearch(query: searchQuery, fileId: fileId, topK: RAGConfig.topK)

        guard !scoredChunks.isEmpty else {
            logWarning("RAGService", "Alakalı chunk bulunamadı")
            return ("", [])
        }

        // 2. Reranking (opsiyonel)
        if enableRerank && scoredChunks.count > RAGConfig.rerankTopK {
            do {
                scoredChunks = try await rerankChunks(scoredChunks, query: query) // Orijinal query ile rerank
            } catch {
                logWarning("RAGService", "Reranking atlandı", details: error.localizedDescription)
            }
        }

        // 3. Token-aware context building
        let context = buildContextWithTokenLimit(from: scoredChunks)
        let chunks = scoredChunks.prefix(RAGConfig.rerankTopK).map { $0.chunk }

        return (context, chunks)
    }

    /// Kısa sorgular için query expansion ile RAG
    func performRAGQueryWithExpansion(
        query: String,
        fileId: UUID
    ) async throws -> (context: String, chunks: [DocumentChunk]) {
        return try await performRAGQuery(
            query: query,
            fileId: fileId,
            enableRerank: true,
            enableQueryExpansion: true
        )
    }
    
    // MARK: - Faz 5: Reranking
    
    /// Gemini ile chunk'ları yeniden sıralar
    func rerankChunks(_ chunks: [ScoredChunk], query: String) async throws -> [ScoredChunk] {
        logDebug("RAGService", "Reranking başlatılıyor", details: "\(chunks.count) chunk")
        
        // Chunk içeriklerini hazırla
        var chunkTexts = ""
        for (index, scored) in chunks.prefix(RAGConfig.topK).enumerated() {
            let preview = String(scored.chunk.content.prefix(200))
            chunkTexts += "[\(index)]: \(preview)...\n\n"
        }
        
        // Gemini'ye gönder
        let rerankResult = try await GeminiService.shared.rerankChunks(
            query: query,
            chunks: chunkTexts
        )
        
        // Sonuçları uygula
        var rerankedChunks = chunks
        for item in rerankResult {
            if item.index < rerankedChunks.count {
                rerankedChunks[item.index].rerankScore = item.score
            }
        }
        
        // Rerank skoruna göre sırala
        let sorted = rerankedChunks.sorted { ($0.rerankScore ?? 0) > ($1.rerankScore ?? 0) }
        
        logDebug("RAGService", "Reranking tamamlandı")
        return sorted
    }
    
    // MARK: - Check Index Status
    
    func isDocumentIndexed(fileId: UUID) async -> Bool {
        do {
            let count = try await SupabaseService.shared.getChunkCount(fileId: fileId)
            return count > 0
        } catch {
            return false
        }
    }
    
    // MARK: - Cache Stats
    
    func getCacheStats() -> (size: Int, maxSize: Int, hitRate: Float) {
        return (embeddingCache.count, RAGConfig.cacheMaxSize, 0) // TODO: Track hit rate
    }
}

// MARK: - RAG Errors
enum RAGError: Error, LocalizedError {
    case embeddingFailed
    case searchFailed
    case notIndexed
    case rerankFailed
    case tokenLimitExceeded
    case hybridSearchFailed
    
    var errorDescription: String? {
        switch self {
        case .embeddingFailed:
            return "Embedding oluşturulamadı"
        case .searchFailed:
            return "Arama başarısız oldu"
        case .notIndexed:
            return "Doküman henüz indexlenmemiş"
        case .rerankFailed:
            return "Reranking başarısız oldu"
        case .tokenLimitExceeded:
            return "Token limiti aşıldı"
        case .hybridSearchFailed:
            return "Hybrid search başarısız oldu"
        }
    }
}
