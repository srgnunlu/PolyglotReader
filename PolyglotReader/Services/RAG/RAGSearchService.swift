import Foundation

// MARK: - RAG Search Service
class RAGSearchService {
    static let shared = RAGSearchService()

    private let embeddingService = RAGEmbeddingService.shared

    private init() {}

    // MARK: - Hybrid Search

    /// Vector + BM25 hybrid search (RRF fusion)
    func hybridSearch(query: String, fileId: UUID, topK: Int? = nil) async throws -> [ScoredChunk] {
        let resolvedTopK = topK ?? RAGConfig.topK
        logDebug("RAGSearchService", "Hybrid search başlatılıyor", details: "Query: \(query.prefix(50))...")

        do {
            logDebug("RAGSearchService", "Embedding oluşturuluyor...")
            let queryEmbedding = try await embeddingService.getOrCreateEmbedding(for: query)
            logDebug("RAGSearchService", "Embedding hazır", details: "Dim: \(queryEmbedding.count)")

            logDebug("RAGSearchService", "Vector + BM25 araması başlatılıyor...")
            async let vectorResultsTask = fetchVectorResults(
                fileId: fileId,
                embedding: queryEmbedding,
                topK: resolvedTopK
            )
            async let bm25ResultsTask = fetchBM25Results(
                fileId: fileId,
                query: query,
                topK: resolvedTopK
            )

            let vectorResults = try await vectorResultsTask
            logDebug("RAGSearchService", "Vector sonuçları", details: "\(vectorResults.count) chunk")

            let bm25Results = await bm25ResultsTask
            logDebug("RAGSearchService", "BM25 sonuçları", details: "\(bm25Results.count) chunk")

            let fusedResults = reciprocalRankFusion(
                vectorResults: vectorResults,
                bm25Results: bm25Results
            )
            logInfo("RAGSearchService", "Hybrid search tamamlandı",
                    details: "Vector: \(vectorResults.count), BM25: \(bm25Results.count), Fused: \(fusedResults.count)")

            if fusedResults.isEmpty {
                let fallbackChunks = await fetchBroadChunks(fileId: fileId, limit: resolvedTopK)
                if !fallbackChunks.isEmpty {
                    logWarning(
                        "RAGSearchService",
                        "Arama sonucu yok, fallback kullanılıyor",
                        details: "\(fallbackChunks.count) chunk"
                    )
                    return fallbackChunks.map {
                        ScoredChunk(chunk: $0, vectorScore: 0, bm25Score: 0, rrfScore: 0)
                    }
                }
            }

            return fusedResults
        } catch {
            logError("RAGSearchService", "Hybrid search hatası", error: error)
            throw ErrorHandlingService.mapToAppError(error)
        }
    }

    private func fetchVectorResults(
        fileId: UUID,
        embedding: [Float],
        topK: Int
    ) async throws -> [DocumentChunk] {
        let results = try await SupabaseService.shared.searchSimilarChunks(
            fileId: fileId.uuidString,
            embedding: embedding,
            limit: topK,
            similarityThreshold: RAGConfig.similarityThreshold
        )

        return results.map { result in
            DocumentChunk(
                id: result.id,
                fileId: fileId,
                chunkIndex: 0,
                content: result.content,
                pageNumber: result.pageNumber,
                similarity: result.similarity
            )
        }
    }

    private func fetchBM25Results(
        fileId: UUID,
        query: String,
        topK: Int
    ) async -> [DocumentChunk] {
        do {
            let bm25RawResults = try await SupabaseService.shared.searchChunksBM25(
                fileId: fileId.uuidString,
                query: query,
                limit: topK
            )
            return bm25RawResults.map { result in
                DocumentChunk(
                    id: result.id ?? UUID(),
                    fileId: fileId,
                    chunkIndex: 0,
                    content: result.content,
                    pageNumber: result.pageNumber,
                    similarity: result.score
                )
            }
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            logWarning(
                "RAGSearchService",
                "BM25 araması başarısız",
                details: appError.localizedDescription
            )
            return []
        }
    }

    private func fetchBroadChunks(fileId: UUID, limit: Int) async -> [DocumentChunk] {
        do {
            let totalChunks = try await SupabaseService.shared.getChunkCount(fileId: fileId.uuidString)
            guard totalChunks > 0 else { return [] }

            let sliceSize = max(1, limit / 3)
            var slices: [SupabaseChunkSlice] = []

            let start = try await SupabaseService.shared.fetchChunkSlice(
                fileId: fileId.uuidString,
                offset: 0,
                limit: sliceSize,
                ascending: true
            )
            slices.append(contentsOf: start)

            if totalChunks > sliceSize {
                let middleOffset = max(0, (totalChunks / 2) - (sliceSize / 2))
                let middle = try await SupabaseService.shared.fetchChunkSlice(
                    fileId: fileId.uuidString,
                    offset: middleOffset,
                    limit: sliceSize,
                    ascending: true
                )
                slices.append(contentsOf: middle)
            }

            if totalChunks > sliceSize {
                let endOffset = max(0, totalChunks - sliceSize)
                let end = try await SupabaseService.shared.fetchChunkSlice(
                    fileId: fileId.uuidString,
                    offset: endOffset,
                    limit: sliceSize,
                    ascending: true
                )
                slices.append(contentsOf: end)
            }

            let uniqueByIndex = Dictionary(grouping: slices, by: { $0.chunk_index })
                .compactMap { $0.value.first }
                .sorted { $0.chunk_index < $1.chunk_index }

            return uniqueByIndex.map {
                DocumentChunk(
                    id: $0.id,
                    fileId: fileId,
                    chunkIndex: $0.chunk_index,
                    content: $0.content,
                    pageNumber: $0.page_number
                )
            }
        } catch {
            logWarning(
                "RAGSearchService",
                "Geniş bağlam alınamadı",
                details: error.localizedDescription
            )
            return []
        }
    }

    /// Sadece vektör araması yap
    func search(query: String, fileId: UUID, limit: Int = 5) async throws -> [DocumentChunk] {
        do {
            let embedding = try await embeddingService.getOrCreateEmbedding(for: query)

            let results = try await SupabaseService.shared.searchSimilarChunks(
                fileId: fileId.uuidString,
                embedding: embedding,
                limit: limit,
                similarityThreshold: RAGConfig.similarityThreshold
            )

            return results.map { result in
                DocumentChunk(
                    id: result.id,
                    fileId: fileId,
                    chunkIndex: 0,
                    content: result.content,
                    pageNumber: result.pageNumber,
                    similarity: result.similarity
                )
            }
        } catch {
            throw ErrorHandlingService.mapToAppError(error)
        }
    }

    /// Sadece BM25 araması yap
    func searchBM25(query: String, fileId: UUID, limit: Int = 5) async throws -> [DocumentChunk] {
        do {
            let results = try await SupabaseService.shared.searchChunksBM25(
                fileId: fileId.uuidString,
                query: query,
                limit: limit
            )

            return results.map { result in
                DocumentChunk(
                    id: result.id ?? UUID(),
                    fileId: fileId,
                    chunkIndex: 0,
                    content: result.content,
                    pageNumber: result.pageNumber,
                    similarity: result.score
                )
            }
        } catch {
            throw ErrorHandlingService.mapToAppError(error)
        }
    }

    // MARK: - RRF Fusion

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
}
