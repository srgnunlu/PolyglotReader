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
    /// Set to the file ID when its most recent indexing attempt failed; cleared when
    /// a new indexing run starts. Lets observers distinguish a failed run from a
    /// successful one (indexing simply stops in both cases).
    @Published var indexingFailedFileId: UUID?

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

        do {
            try await runIndexingPipeline(text: text, fileId: fileId, imageMetadata: imageMetadata)
        } catch {
            indexingFailedFileId = fileId
            throw error
        }
    }

    private func runIndexingPipeline(
        text: String,
        fileId: UUID,
        imageMetadata: [PDFImageMetadata]
    ) async throws {
        // Metin istatistikleri
        let wordCount = text.split(separator: " ").count
        let pageMarkers = text.components(separatedBy: "--- Sayfa ").count - 1
        logInfo("RAGService", "Doküman indexleniyor",
                details: "FileID: \(fileId), ~\(wordCount) kelime, \(pageMarkers) sayfa marker, \(imageMetadata.count) görsel")

        // Chunking
        let chunks = createChunks(from: text, fileId: fileId, imageMetadata: imageMetadata)
        guard !chunks.isEmpty else {
            logWarning("RAGService", "Chunk oluşturulamadı - metin boş olabilir")
            return
        }

        // Chunk istatistikleri
        let pageNumbers = chunks.compactMap { $0.pageNumber }
        let minPage = pageNumbers.min() ?? 0
        let maxPage = pageNumbers.max() ?? 0
        logInfo("RAGService", "Chunking tamamlandı",
                details: "\(chunks.count) chunk oluşturuldu (Sayfa \(minPage)-\(maxPage))")

        // Embedding oluşturma
        let chunksWithEmbeddings = await buildEmbeddings(for: chunks)

        // Doğrulama: Tüm chunk'lar için embedding oluşturuldu mu?
        let successRate = Float(chunksWithEmbeddings.count) / Float(chunks.count) * 100
        if chunksWithEmbeddings.count < chunks.count {
            logWarning("RAGService", "Eksik embedding!",
                       details: "\(chunksWithEmbeddings.count)/\(chunks.count) (%\(Int(successRate)))")
        }

        // Kaydetme
        try await persistEmbeddings(chunksWithEmbeddings, fileId: fileId)
        indexingProgress = 1.0

        // Final rapor
        let embeddedPages = chunksWithEmbeddings.compactMap { $0.chunk.pageNumber }
        let embeddedMinPage = embeddedPages.min() ?? 0
        let embeddedMaxPage = embeddedPages.max() ?? 0
        logInfo("RAGService", "✅ Doküman indexlendi",
                details: "\(chunksWithEmbeddings.count) chunk kaydedildi (Sayfa \(embeddedMinPage)-\(embeddedMaxPage), %\(Int(successRate)) başarı)")
    }

    private func startIndexing(for fileId: UUID) {
        isIndexing = true
        indexingFileId = fileId
        indexingProgress = 0
        currentOperation = "Metin analiz ediliyor..."
        // Clear any previous failure flag for a fresh attempt.
        if indexingFailedFileId == fileId {
            indexingFailedFileId = nil
        }
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
        var failedChunks: [(index: Int, chunk: DocumentChunk)] = []

        logInfo("RAGService", "Embedding oluşturma başlıyor", details: "Toplam \(chunks.count) chunk")

        // Chunk'ları RAGConfig.batchSize'lık paralel gruplara işle. getOrCreateEmbedding
        // alt katmanda zaten ErrorHandlingService.retry ile sarılı; bu yüzden tek tek
        // serial retry döngüsü + chunk başına 100ms sleep yerine grup içi paralellikten
        // faydalanıyoruz (yüzlerce chunk'ta dakikalar yerine saniyeler).
        let service = embeddingService
        let batchSize = max(1, RAGConfig.batchSize)
        let indexedChunks = Array(chunks.enumerated())
        var processed = 0

        for start in stride(from: 0, to: indexedChunks.count, by: batchSize) {
            let batch = Array(indexedChunks[start..<min(start + batchSize, indexedChunks.count)])

            let batchResults: [(index: Int, chunk: DocumentChunk, embedding: [Float]?)] =
                await withTaskGroup(of: (Int, DocumentChunk, [Float]?).self) { group in
                    for (index, chunk) in batch {
                        group.addTask {
                            let embedding = try? await service.getOrCreateEmbedding(for: chunk.content)
                            return (index, chunk, embedding)
                        }
                    }
                    var collected: [(Int, DocumentChunk, [Float]?)] = []
                    for await result in group {
                        collected.append(result)
                    }
                    return collected
                }

            for result in batchResults {
                if let embedding = result.embedding {
                    chunksWithEmbeddings.append((result.chunk, embedding))
                } else {
                    failedChunks.append((result.index, result.chunk))
                    handleEmbeddingError(RAGError.embeddingFailed, index: result.index)
                }
            }

            processed += batch.count
            updateIndexingProgress(currentIndex: processed - 1, total: chunks.count)

            // Rate limiting: Batch'ler arasında bekle (chunk başına değil).
            if start + batchSize < indexedChunks.count {
                try? await Task.sleep(nanoseconds: RAGConfig.rateLimitDelay)
            }
        }

        // Final rapor
        logInfo("RAGService", "Embedding tamamlandı",
                details: "Başarılı: \(chunksWithEmbeddings.count)/\(chunks.count), Başarısız: \(failedChunks.count)")

        // Başarısız chunk'ları tekrar dene (son şans, yine paralel)
        if !failedChunks.isEmpty {
            let recovered = await retryFailedEmbeddings(failedChunks.map { $0.chunk })
            chunksWithEmbeddings.append(contentsOf: recovered)
        }

        return chunksWithEmbeddings
    }

    /// Başarısız chunk'lar için son bir paralel embedding denemesi yapar.
    private func retryFailedEmbeddings(
        _ chunks: [DocumentChunk]
    ) async -> [(chunk: DocumentChunk, embedding: [Float])] {
        logWarning("RAGService", "Başarısız chunk'lar için son deneme", details: "\(chunks.count) chunk")
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 saniye bekle

        let service = embeddingService
        let retryResults: [(chunk: DocumentChunk, embedding: [Float]?)] =
            await withTaskGroup(of: (DocumentChunk, [Float]?).self) { group in
                for chunk in chunks {
                    group.addTask {
                        let embedding = try? await service.getOrCreateEmbedding(for: chunk.content)
                        return (chunk, embedding)
                    }
                }
                var collected: [(DocumentChunk, [Float]?)] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }

        return retryResults.compactMap { result in
            guard let embedding = result.embedding else { return nil }
            return (result.chunk, embedding)
        }
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

        let records = chunksWithEmbeddings.map { item in
            SupabaseChunkInsert(
                content: item.chunk.content,
                embedding: item.embedding,
                pageNumber: item.chunk.pageNumber,
                sectionTitle: item.chunk.sectionTitle,
                contentType: item.chunk.contentType.rawValue,
                containsTable: item.chunk.containsTable,
                containsList: item.chunk.containsList,
                imageRefs: item.chunk.imageReferences.map { $0.uuidString }
            )
        }
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
            // Derin arama = geniş aday havuzu + LLM rerank. Havuz genişlemeden
            // rerank tek başına "derin" bir şey yapmıyordu (aynı 10 aday).
            let isDeepSearch = shouldRerank

            // Deliberately sequential: expansion consumes the translated query,
            // search consumes the final query, rerank consumes search results.
            // Independent work (image-caption search) is parallelized by the
            // caller (ChatViewModel) instead.
            let searchQuery = await resolveSearchQuery(query, enableQueryExpansion: shouldExpandQuery)

            var scoredChunks = try await searchService.hybridSearch(
                query: searchQuery,
                fileId: fileId,
                topK: isDeepSearch ? RAGConfig.deepSearchTopK : RAGConfig.topK
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

            // Dinamik context token limiti — derin modda taban yükselir ki
            // genişleyen aday havuzu bağlama gerçekten sığsın.
            var maxTokens = determineContextTokenLimit(for: query)
            if isDeepSearch {
                maxTokens = max(maxTokens, RAGConfig.deepSearchMinContextTokens)
            }
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
            // NOTE: The HyDE hypothetical-answer embedding was removed here: its
            // result was never consumed, yet it added a serial embedding API
            // call to every expanded query (first-message latency).

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
        guard enableRerank else { return chunks }

        // Skip the extra Gemini call when it cannot change the outcome:
        // with <= rerankTopK candidates, every chunk already enters the context.
        guard chunks.count > RAGConfig.rerankTopK else {
            logInfo(
                "RAGService",
                "Rerank atlandı",
                details: "Aday sayısı (\(chunks.count)) <= rerankTopK (\(RAGConfig.rerankTopK))"
            )
            return chunks
        }

        // A thin candidate pool means hybrid search found little to reorder;
        // the rerank call would add ~1-2s latency for marginal gain.
        guard chunks.count >= RAGConfig.rerankMinCandidates else {
            logInfo(
                "RAGService",
                "Rerank atlandı",
                details: "Aday sayısı (\(chunks.count)) < minimum (\(RAGConfig.rerankMinCandidates))"
            )
            return chunks
        }

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
        // Chunk içeriklerini hazırla. Tüm adaylar puanlanır (derin modda 24'e
        // kadar); 600 karakterlik önizleme tablolu/listeli chunk'ların da
        // adil yargılanmasını sağlar (200 karakter çoğu chunk'ta başlıktan
        // öteye geçemiyordu).
        var chunkTexts = ""
        for (index, scored) in chunks.prefix(RAGConfig.deepSearchTopK).enumerated() {
            let preview = String(scored.chunk.content.prefix(600))
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

        // finalScore = rerankScore ?? rrfScore: Gemini'nin puanlamadığı chunk
        // sıfıra çakılıp kaybolmaz, hybrid arama sırasındaki yerini korur.
        let sorted = rerankedChunks.sorted { $0.finalScore > $1.finalScore }

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
