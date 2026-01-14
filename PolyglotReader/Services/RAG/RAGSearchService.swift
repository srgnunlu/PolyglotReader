import Foundation

// MARK: - RAG Search Service
class RAGSearchService {
    static let shared = RAGSearchService()

    private let embeddingService = RAGEmbeddingService.shared

    private init() {}

    // MARK: - Query Analysis

    /// Sorgudan sayfa numarası, figure/table referansı çıkar
    private struct QueryAnalysis {
        var pageNumbers: [Int] = []
        var figureReferences: [String] = []
        var tableReferences: [String] = []
        var simplifiedQuery: String = ""

        var hasPageReference: Bool { !pageNumbers.isEmpty }
        var hasFigureReference: Bool { !figureReferences.isEmpty }
        var hasTableReference: Bool { !tableReferences.isEmpty }
        var hasSpecificReference: Bool { hasPageReference || hasFigureReference || hasTableReference }
    }

    private func analyzeQuery(_ query: String) -> QueryAnalysis {
        var analysis = QueryAnalysis()

        // Sayfa numarası tespiti: "sayfa 45", "page 45", "s.45", "p.45"
        let pagePatterns = [
            #"(?:sayfa|page|s\.|p\.)\s*(\d+)"#,
            #"(\d+)\.\s*sayfa"#,
            #"(\d+)(?:st|nd|rd|th)\s*page"#
        ]

        for pattern in pagePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: query, range: NSRange(query.startIndex..., in: query))
                for match in matches {
                    if let range = Range(match.range(at: 1), in: query),
                       let pageNum = Int(query[range]) {
                        analysis.pageNumbers.append(pageNum)
                    }
                }
            }
        }

        // Figure referansı: "Figure 2-1", "Fig. 2.1", "Şekil 2-1"
        let figurePatterns = [
            #"(?:figure|fig\.?|şekil)\s*(\d+[-.\s]?\d*)"#
        ]

        for pattern in figurePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: query, range: NSRange(query.startIndex..., in: query))
                for match in matches {
                    if let range = Range(match.range(at: 1), in: query) {
                        analysis.figureReferences.append(String(query[range]))
                    }
                }
            }
        }

        // Table referansı: "Table 2-1", "Tablo 2"
        let tablePatterns = [
            #"(?:table|tablo)\s*(\d+[-.\s]?\d*)"#
        ]

        for pattern in tablePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let matches = regex.matches(in: query, range: NSRange(query.startIndex..., in: query))
                for match in matches {
                    if let range = Range(match.range(at: 1), in: query) {
                        analysis.tableReferences.append(String(query[range]))
                    }
                }
            }
        }

        // BM25 için basitleştirilmiş sorgu (önemli kelimeleri çıkar)
        let stopWords = Set(["the", "a", "an", "is", "are", "was", "were", "what", "which", "who",
                             "ne", "nedir", "nasıl", "hangi", "bu", "şu", "için", "ile", "ve", "veya",
                             "summarize", "explain", "describe", "tell", "about", "anlat", "açıkla", "özetle"])

        let words = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        analysis.simplifiedQuery = words.prefix(5).joined(separator: " ")

        return analysis
    }

    // MARK: - Hybrid Search

    /// Vector + BM25 hybrid search (RRF fusion)
    // swiftlint:disable:next function_body_length
    func hybridSearch(query: String, fileId: UUID, topK: Int? = nil) async throws -> [ScoredChunk] {
        let resolvedTopK = topK ?? RAGConfig.topK
        logDebug("RAGSearchService", "Hybrid search başlatılıyor", details: "Query: \(query.prefix(50))...")

        let analysis = analyzeQuery(query)
        if analysis.hasSpecificReference {
            logInfo("RAGSearchService", "Spesifik referans tespit edildi",
                    details: "Pages: \(analysis.pageNumbers), Figures: \(analysis.figureReferences), Tables: \(analysis.tableReferences)")
        }

        do {
            // Sayfa ve referans bazlı sonuçları al
            let (pageBasedResults, referenceResults) = try await fetchSpecificResults(
                analysis: analysis, fileId: fileId, topK: resolvedTopK
            )

            // Vector ve BM25 sonuçlarını al
            let (vectorResults, bm25Results) = try await fetchSemanticResults(
                query: query, analysis: analysis, fileId: fileId, topK: resolvedTopK
            )

            // RRF fusion uygula
            let fusedResults = reciprocalRankFusionEnhanced(
                pageBasedResults: pageBasedResults,
                referenceResults: referenceResults,
                vectorResults: vectorResults,
                bm25Results: bm25Results
            )

            logInfo("RAGSearchService", "Hybrid search tamamlandı",
                    details: "Page: \(pageBasedResults.count), Ref: \(referenceResults.count), Vector: \(vectorResults.count), BM25: \(bm25Results.count), Fused: \(fusedResults.count)")

            return fusedResults.isEmpty
                ? await fetchFallbackResults(fileId: fileId, limit: resolvedTopK)
                : fusedResults
        } catch {
            logError("RAGSearchService", "Hybrid search hatası", error: error)
            throw ErrorHandlingService.mapToAppError(error)
        }
    }

    /// Sayfa ve referans bazlı sonuçları getir
    private func fetchSpecificResults(
        analysis: QueryAnalysis, fileId: UUID, topK: Int
    ) async throws -> (pageResults: [DocumentChunk], refResults: [DocumentChunk]) {
        var pageBasedResults: [DocumentChunk] = []
        var referenceResults: [DocumentChunk] = []

        if analysis.hasPageReference {
            pageBasedResults = try await fetchChunksByPageNumbers(
                fileId: fileId, pageNumbers: analysis.pageNumbers, limit: topK
            )
            logInfo("RAGSearchService", "Sayfa bazlı sonuçlar", details: "\(pageBasedResults.count) chunk")
        }

        if analysis.hasFigureReference || analysis.hasTableReference {
            referenceResults = try await fetchChunksByContentMatch(
                fileId: fileId, figures: analysis.figureReferences, tables: analysis.tableReferences, limit: topK
            )
            logInfo("RAGSearchService", "Referans bazlı sonuçlar", details: "\(referenceResults.count) chunk")
        }

        return (pageBasedResults, referenceResults)
    }

    /// Vector ve BM25 sonuçlarını getir
    private func fetchSemanticResults(
        query: String, analysis: QueryAnalysis, fileId: UUID, topK: Int
    ) async throws -> (vectorResults: [DocumentChunk], bm25Results: [DocumentChunk]) {
        logDebug("RAGSearchService", "Embedding oluşturuluyor...")
        let queryEmbedding = try await embeddingService.getOrCreateEmbedding(for: query)
        logDebug("RAGSearchService", "Embedding hazır", details: "Dim: \(queryEmbedding.count)")

        let bm25Query = analysis.simplifiedQuery.isEmpty ? query : analysis.simplifiedQuery

        async let vectorTask = fetchVectorResults(fileId: fileId, embedding: queryEmbedding, topK: topK)
        async let bm25Task = fetchBM25Results(fileId: fileId, query: bm25Query, topK: topK)

        let vectorResults = try await vectorTask
        logDebug("RAGSearchService", "Vector sonuçları", details: "\(vectorResults.count) chunk")

        let bm25Results = await bm25Task
        logDebug("RAGSearchService", "BM25 sonuçları", details: "\(bm25Results.count) chunk")

        return (vectorResults, bm25Results)
    }

    /// Fallback sonuçları getir
    private func fetchFallbackResults(fileId: UUID, limit: Int) async -> [ScoredChunk] {
        let fallbackChunks = await fetchBroadChunks(fileId: fileId, limit: limit)
        if !fallbackChunks.isEmpty {
            logWarning("RAGSearchService", "Arama sonucu yok, fallback kullanılıyor",
                       details: "\(fallbackChunks.count) chunk")
            return fallbackChunks.map { ScoredChunk(chunk: $0, vectorScore: 0, bm25Score: 0, rrfScore: 0) }
        }
        return []
    }

    // MARK: - Page & Reference Based Search

    /// Belirli sayfa numaralarındaki chunk'ları getir
    private func fetchChunksByPageNumbers(
        fileId: UUID,
        pageNumbers: [Int],
        limit: Int
    ) async throws -> [DocumentChunk] {
        guard !pageNumbers.isEmpty else { return [] }

        let results = try await SupabaseService.shared.fetchChunksByPageNumbers(
            fileId: fileId.uuidString,
            pageNumbers: pageNumbers,
            limit: limit
        )

        return results.map { result in
            DocumentChunk(
                id: result.id,
                fileId: fileId,
                chunkIndex: result.chunk_index,
                content: result.content,
                pageNumber: result.page_number,
                similarity: 1.0 // Sayfa bazlı eşleşme tam skor
            )
        }
    }

    /// Figure/Table referanslarını içeren chunk'ları getir
    private func fetchChunksByContentMatch(
        fileId: UUID,
        figures: [String],
        tables: [String],
        limit: Int
    ) async throws -> [DocumentChunk] {
        var searchTerms: [String] = []

        for fig in figures {
            searchTerms.append("Figure \(fig)")
            searchTerms.append("Fig. \(fig)")
            searchTerms.append("Şekil \(fig)")
        }

        for tbl in tables {
            searchTerms.append("Table \(tbl)")
            searchTerms.append("Tablo \(tbl)")
        }

        guard !searchTerms.isEmpty else { return [] }

        let results = try await SupabaseService.shared.fetchChunksByContentSearch(
            fileId: fileId.uuidString,
            searchTerms: searchTerms,
            limit: limit
        )

        return results.map { result in
            DocumentChunk(
                id: result.id,
                fileId: fileId,
                chunkIndex: result.chunk_index,
                content: result.content,
                pageNumber: result.page_number,
                similarity: 0.95 // Referans bazlı eşleşme yüksek skor
            )
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

    /// Enhanced Reciprocal Rank Fusion - sayfa ve referans bazlı sonuçları önceliklendirir
    private func reciprocalRankFusionEnhanced(
        pageBasedResults: [DocumentChunk],
        referenceResults: [DocumentChunk],
        vectorResults: [DocumentChunk],
        bm25Results: [DocumentChunk]
    ) -> [ScoredChunk] {
        var scoreMap: [UUID: ScoredChunk] = [:]

        // Sayfa bazlı sonuçlar EN YÜKSEK öncelik (1.5x boost)
        let pageBoost: Float = 1.5
        for (rank, chunk) in pageBasedResults.enumerated() {
            let score = pageBoost / (RAGConfig.rrfK + Float(rank + 1))

            scoreMap[chunk.id] = ScoredChunk(
                chunk: chunk,
                vectorScore: score,
                bm25Score: 0,
                rrfScore: score
            )
        }

        // Referans bazlı sonuçlar YÜKSEK öncelik (1.3x boost)
        let refBoost: Float = 1.3
        for (rank, chunk) in referenceResults.enumerated() {
            let score = refBoost / (RAGConfig.rrfK + Float(rank + 1))

            if var existing = scoreMap[chunk.id] {
                existing.rrfScore += score
                scoreMap[chunk.id] = existing
            } else {
                scoreMap[chunk.id] = ScoredChunk(
                    chunk: chunk,
                    vectorScore: score,
                    bm25Score: 0,
                    rrfScore: score
                )
            }
        }

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

    /// Reciprocal Rank Fusion algoritması (eski versiyon - uyumluluk için)
    private func reciprocalRankFusion(vectorResults: [DocumentChunk], bm25Results: [DocumentChunk]) -> [ScoredChunk] {
        return reciprocalRankFusionEnhanced(
            pageBasedResults: [],
            referenceResults: [],
            vectorResults: vectorResults,
            bm25Results: bm25Results
        )
    }
}
