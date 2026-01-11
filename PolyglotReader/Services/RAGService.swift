import Foundation
import Combine
import CryptoKit

// MARK: - RAG Service Facade
@MainActor
class RAGService: ObservableObject {
    static let shared = RAGService()

    @Published var isIndexing = false
    @Published var indexingFileId: UUID?
    @Published var indexingProgress: Float = 0
    @Published var currentOperation: String = ""

    // Sub-services
    private let chunker = RAGChunker.shared
    private let embeddingService = RAGEmbeddingService.shared
    private let searchService = RAGSearchService.shared
    private let contextBuilder = RAGContextBuilder.shared
    private var activeIndexingTask: Task<Void, Error>?
    private var activeIndexingFileId: UUID?

    private init() {
        logInfo("RAGService", "Profesyonel RAG Servisi başlatıldı v2.0 (Facade)")
    }

    // MARK: - Document Indexing

    /// PDF dokümanını indexler (semantic chunk'lar + embedding'ler)
    func indexDocument(text: String, fileId: UUID) async throws {
        try await indexDocument(text: text, fileId: fileId, imageMetadata: [])
    }

    /// P1.2: Görsel metadata ile zenginleştirilmiş indexleme
    func indexDocument(text: String, fileId: UUID, imageMetadata: [PDFImageMetadata]) async throws {
        if let activeIndexingTask {
            if activeIndexingFileId == fileId {
                try await activeIndexingTask.value
                return
            }
            try await activeIndexingTask.value
        }

        let indexingTask = Task { @MainActor in
            try await self.performIndexing(
                text: text,
                fileId: fileId,
                imageMetadata: imageMetadata
            )
        }

        activeIndexingTask = indexingTask
        activeIndexingFileId = fileId
        defer {
            activeIndexingTask = nil
            activeIndexingFileId = nil
        }

        try await indexingTask.value
    }

    private func performIndexing(
        text: String,
        fileId: UUID,
        imageMetadata: [PDFImageMetadata]
    ) async throws {
        startIndexing(for: fileId)
        defer { finishIndexing(for: fileId) }
        logInfo("RAGService", "Doküman indexleniyor", details: "FileID: \(fileId), Images: \(imageMetadata.count)")

        let chunks = createChunks(from: text, fileId: fileId, imageMetadata: imageMetadata)
        guard !chunks.isEmpty else {
            logWarning("RAGService", "Chunk oluşturulamadı")
            return
        }

        let chunksWithEmbeddings = await buildEmbeddings(for: chunks)
        try await persistEmbeddings(chunksWithEmbeddings, fileId: fileId)
        indexingProgress = 1.0
        logInfo("RAGService", "Doküman indexlendi", details: "\(chunksWithEmbeddings.count) chunk kaydedildi")
    }

    private func startIndexing(for fileId: UUID) {
        isIndexing = true
        indexingFileId = fileId
        indexingProgress = 0
        currentOperation = "Metin analiz ediliyor..."
    }

    private func finishIndexing(for fileId: UUID) {
        isIndexing = false
        indexingProgress = max(indexingProgress, 1.0)
        if indexingFileId == fileId {
            indexingFileId = nil
        }
        currentOperation = ""
    }

    private func createChunks(from text: String, fileId: UUID, imageMetadata: [PDFImageMetadata] = []) -> [DocumentChunk] {
        currentOperation = "Semantic chunking..."
        return chunker.semanticChunkText(text, fileId: fileId, imageMetadata: imageMetadata)
    }

    private func buildEmbeddings(
        for chunks: [DocumentChunk]
    ) async -> [(chunk: DocumentChunk, embedding: [Float])] {
        currentOperation = "Embedding oluşturuluyor..."
        var chunksWithEmbeddings: [(chunk: DocumentChunk, embedding: [Float])] = []

        for (index, chunk) in chunks.enumerated() {
            do {
                let embedding = try await embeddingService.getOrCreateEmbedding(for: chunk.content)
                chunksWithEmbeddings.append((chunk, embedding))
                updateIndexingProgress(currentIndex: index, total: chunks.count)
            } catch {
                handleEmbeddingError(error, index: index)
            }

            if index < chunks.count - 1 {
                try? await Task.sleep(nanoseconds: RAGConfig.rateLimitDelay)
            }
        }

        return chunksWithEmbeddings
    }

    private func updateIndexingProgress(currentIndex: Int, total: Int) {
        guard total > 0 else { return }
        let progress = Float(currentIndex + 1) / Float(total) * 0.9
        indexingProgress = max(indexingProgress, progress)
    }

    private func handleEmbeddingError(_ error: Error, index: Int) {
        let appError = ErrorHandlingService.mapToAppError(error)
        logWarning(
            "RAGService",
            "Chunk \(index) için embedding hatası",
            details: appError.localizedDescription
        )
        ErrorHandlingService.shared.handle(
            appError,
            context: .silent(source: "RAGService", operation: "Embedding")
        )
    }

    private func persistEmbeddings(
        _ chunksWithEmbeddings: [(chunk: DocumentChunk, embedding: [Float])],
        fileId: UUID
    ) async throws {
        currentOperation = "Veritabanına kaydediliyor..."
        guard !chunksWithEmbeddings.isEmpty else {
            throw AppError.ai(reason: .unavailable, underlying: RAGError.embeddingFailed)
        }

        let records = chunksWithEmbeddings.map { ($0.chunk.content, $0.embedding, $0.chunk.pageNumber) }
        do {
            try await SupabaseService.shared.saveDocumentChunks(fileId: fileId.uuidString, chunks: records)
        } catch {
            throw ErrorHandlingService.mapToAppError(error)
        }
    }

    // MARK: - Search

    func hybridSearch(query: String, fileId: UUID, topK: Int? = nil) async throws -> [ScoredChunk] {
        let resolvedTopK = topK ?? RAGConfig.topK
        do {
            return try await searchService.hybridSearch(
                query: query,
                fileId: fileId,
                topK: resolvedTopK
            )
        } catch {
            throw ErrorHandlingService.mapToAppError(error)
        }
    }

    func search(query: String, fileId: UUID, limit: Int = 5) async throws -> [DocumentChunk] {
        do {
            return try await searchService.search(query: query, fileId: fileId, limit: limit)
        } catch {
            throw ErrorHandlingService.mapToAppError(error)
        }
    }

    func searchBM25(query: String, fileId: UUID, limit: Int = 5) async throws -> [DocumentChunk] {
        do {
            return try await searchService.searchBM25(query: query, fileId: fileId, limit: limit)
        } catch {
            throw ErrorHandlingService.mapToAppError(error)
        }
    }

    func searchRelevantChunks(query: String, fileId: UUID, topK: Int? = nil) async throws -> [DocumentChunk] {
        let resolvedTopK = topK ?? RAGConfig.topK
        let scoredChunks = try await hybridSearch(
            query: query,
            fileId: fileId,
            topK: resolvedTopK
        )
        return scoredChunks.prefix(resolvedTopK).map { $0.chunk }
    }

    // MARK: - Full RAG Pipeline

    /// Tam RAG pipeline: Query Enhancement -> Hybrid Search -> Rerank -> Token Limit -> Context
    /// v3.0: Reranking ve Query Expansion varsayılan olarak aktif
    func performRAGQuery(
        query: String,
        fileId: UUID,
        enableRerank: Bool? = nil,
        enableQueryExpansion: Bool? = nil
    ) async throws -> (context: String, chunks: [DocumentChunk]) {
        logInfo("RAGService", "Full RAG pipeline v3.0 başlatılıyor")
        do {
            // Smart defaults: Config'den al veya parametreden override
            let shouldRerank = enableRerank ?? RAGConfig.enableDefaultReranking
            let shouldExpandQuery = enableQueryExpansion ?? shouldAutoExpandQuery(query)

            let searchQuery = await resolveSearchQuery(query, enableQueryExpansion: shouldExpandQuery)

            var scoredChunks = try await searchService.hybridSearch(
                query: searchQuery,
                fileId: fileId,
                topK: RAGConfig.topK
            )

            guard !scoredChunks.isEmpty else {
                logWarning("RAGService", "Alakalı chunk bulunamadı")
                return ("", [])
            }

            // Reranking artık varsayılan olarak aktif
            scoredChunks = await rerankChunksIfNeeded(scoredChunks, query: query, enableRerank: shouldRerank)
            scoredChunks = filterLowConfidenceChunks(scoredChunks, query: searchQuery)

            guard !scoredChunks.isEmpty else {
                logWarning(
                    "RAGService",
                    "Düşük benzerlik nedeniyle bağlam boş bırakıldı",
                    details: "Query: \(searchQuery.prefix(40))..."
                )
                return ("", [])
            }

            // Dinamik context token limiti
            let maxTokens = determineContextTokenLimit(for: query)
            let context = contextBuilder.buildContextWithTokenLimit(from: scoredChunks, maxTokens: maxTokens)
            let chunks = scoredChunks.prefix(RAGConfig.rerankTopK).map { $0.chunk }

            logInfo("RAGService", "RAG pipeline tamamlandı",
                    details: "Rerank: \(shouldRerank), Expansion: \(shouldExpandQuery), Chunks: \(chunks.count)")

            return (context, chunks)
        } catch {
            throw ErrorHandlingService.mapToAppError(error)
        }
    }

    /// Kısa sorgular için otomatik query expansion
    private func shouldAutoExpandQuery(_ query: String) -> Bool {
        guard RAGConfig.enableQueryExpansionForShortQueries else { return false }
        let wordCount = query.split(separator: " ").count
        return wordCount <= RAGConfig.shortQueryThreshold
    }

    /// Sorgu tipine göre dinamik context token limiti
    private func determineContextTokenLimit(for query: String) -> Int {
        let lowercased = query.lowercased()

        // Karşılaştırma sorguları daha fazla context gerektirir
        let comparisonKeywords = ["karşılaştır", "fark", "benzerlik", "arasında", "vs", "versus", "compare"]
        if comparisonKeywords.contains(where: { lowercased.contains($0) }) {
            return RAGConfig.comparisonContextTokens
        }

        // Kısa/basit sorular daha az context
        if query.split(separator: " ").count <= 4 {
            return RAGConfig.shortQueryContextTokens
        }

        return RAGConfig.maxContextTokens
    }

    func performRAGQueryWithExpansion(
        query: String,
        fileId: UUID
    ) async throws -> (context: String, chunks: [DocumentChunk]) {
        try await performRAGQuery(
            query: query,
            fileId: fileId,
            enableRerank: true,
            enableQueryExpansion: true
        )
    }

    // MARK: - Query Preparation

    private func resolveSearchQuery(_ query: String, enableQueryExpansion: Bool) async -> String {
        let translatedQuery = await translateQueryIfNeeded(query)
        guard enableQueryExpansion, translatedQuery.split(separator: " ").count <= 5 else {
            return translatedQuery
        }
        return await expandQueryIfNeeded(translatedQuery, originalQuery: query)
    }

    private func translateQueryIfNeeded(_ query: String) async -> String {
        do {
            let translatedQuery = try await GeminiService.shared.translateQueryForSearch(query)
            if translatedQuery != query {
                logInfo(
                    "RAGService",
                    "Query çevrildi",
                    details: "TR: \(query.prefix(40))... → EN: \(translatedQuery.prefix(40))..."
                )
                return translatedQuery
            }
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            logWarning("RAGService", "Query çevirisi atlandı", details: appError.localizedDescription)
        }
        return query
    }

    private func expandQueryIfNeeded(_ query: String, originalQuery: String) async -> String {
        do {
            let expanded = try await GeminiService.shared.expandQuery(query)

            if let hydeAnswer = expanded.hypotheticalAnswer {
                _ = try await embeddingService.getOrCreateEmbedding(for: hydeAnswer)
                logDebug("RAGService", "HyDE embedding oluşturuldu (Kullanım dışı)")
            }

            logDebug(
                "RAGService",
                "Query expansion tamamlandı",
                details: "Orijinal: \(originalQuery.prefix(30))... -> Expanded: \(expanded.expanded.prefix(30))..."
            )
            return expanded.expanded
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            logWarning("RAGService", "Query expansion atlandı", details: appError.localizedDescription)
            return query
        }
    }

    private func rerankChunksIfNeeded(
        _ chunks: [ScoredChunk],
        query: String,
        enableRerank: Bool
    ) async -> [ScoredChunk] {
        guard enableRerank, chunks.count > RAGConfig.rerankTopK else { return chunks }

        do {
            return try await rerankChunksHelper(chunks, query: query)
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            logWarning("RAGService", "Reranking atlandı", details: appError.localizedDescription)
            return chunks
        }
    }

    // MARK: - Reranking Helper

    private func rerankChunksHelper(_ chunks: [ScoredChunk], query: String) async throws -> [ScoredChunk] {
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
        for item in rerankResult where item.index < rerankedChunks.count {
            rerankedChunks[item.index].rerankScore = item.score
        }

        // Rerank skoruna göre sırala
        let sorted = rerankedChunks.sorted { ($0.rerankScore ?? 0) > ($1.rerankScore ?? 0) }

        return sorted
    }

    // MARK: - Relevance Filtering

    private func filterLowConfidenceChunks(_ chunks: [ScoredChunk], query: String) -> [ScoredChunk] {
        let keywords = extractKeywords(from: query)

        let filtered = chunks.filter { scored in
            if let similarity = scored.chunk.similarity, similarity >= RAGConfig.minAnswerSimilarity {
                return true
            }
            if scored.bm25Score > 0 {
                return true
            }
            guard !keywords.isEmpty else { return true }
            return containsAnyKeyword(in: scored.chunk.content, keywords: keywords)
        }

        return filtered
    }

    private func extractKeywords(from query: String) -> [String] {
        let stopwords: Set<String> = [
            "what", "are", "the", "about", "regarding", "with", "from", "this", "that",
            "nedir", "nasıl", "ne", "hangi", "ile", "ve", "bir", "bu", "şu", "ilgili"
        ]

        return query
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0) }
            .filter { $0.count >= 4 && !stopwords.contains($0) }
    }

    private func containsAnyKeyword(in text: String, keywords: [String]) -> Bool {
        let haystack = text.lowercased()
        return keywords.contains { haystack.contains($0) }
    }

    // MARK: - Backward Compatibility & Helpers

    func chunkText(_ text: String, fileId: UUID, imageMetadata: [PDFImageMetadata] = []) -> [DocumentChunk] {
        chunker.semanticChunkText(text, fileId: fileId, imageMetadata: imageMetadata)
    }

    func createEmbedding(for text: String) async throws -> [Float] {
        do {
            return try await embeddingService.getOrCreateEmbedding(for: text)
        } catch {
            throw ErrorHandlingService.mapToAppError(error)
        }
    }

    func buildContext(from chunks: [DocumentChunk]) -> String {
        contextBuilder.buildContext(from: chunks)
    }

    func isDocumentIndexed(fileId: UUID) async -> Bool {
        do {
            let count = try await SupabaseService.shared.getChunkCount(fileId: fileId.uuidString)
            return count > 0
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            ErrorHandlingService.shared.handle(
                appError,
                context: .silent(source: "RAGService", operation: "ChunkCount")
            )
            return false
        }
    }

    func clearCache() {
        embeddingService.clearCache()
    }

    /// P3.2: Enhanced cache stats
    func getCacheStats() -> (size: Int, maxSize: Int, hitRate: Float, diskHits: Int) {
        embeddingService.getCacheStats()
    }

    /// P3.2: Disk cache temizleme
    func cleanupDiskCache() {
        embeddingService.cleanupDiskCache()
    }
}
