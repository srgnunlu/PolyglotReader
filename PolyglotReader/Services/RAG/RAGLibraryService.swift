import Foundation

// MARK: - Library RAG (multi-document search)

/// Kütüphane geneli RAG: tek dosyalık pipeline'ın hafif eşleniği.
/// Sorgu çevirisi → vector + BM25 (tek RPC, tüm seçili dosyalar) →
/// RRF füzyonu → dosya adı + sayfa etiketli bağlam.
@MainActor
final class RAGLibraryService {
    static let shared = RAGLibraryService()

    private let embeddingService = RAGEmbeddingService.shared

    private init() {}

    struct LibraryFile {
        let id: UUID
        let name: String
    }

    struct LibraryChunk {
        let id: UUID
        let fileId: UUID
        let fileName: String
        let content: String
        let pageNumber: Int?
        var rrfScore: Float
    }

    /// Çok dokümanlı aramada aday havuzu tek dosyadan geniş tutulur;
    /// bağlam yine token bütçesiyle sınırlanır.
    private let topK = 16
    private let maxContextTokens = 30_000

    func performLibraryQuery(
        query: String,
        files: [LibraryFile]
    ) async throws -> (context: String, chunks: [LibraryChunk]) {
        guard !files.isEmpty else { return ("", []) }

        let nameByFile = Dictionary(files.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let fileIds = files.map { $0.id.uuidString }

        // Cross-lingual: tek doküman akışıyla aynı çeviri adımı.
        let searchQuery = await translateIfNeeded(query)
        let language = searchQuery.range(of: "[çğıöşüÇĞİÖŞÜ]", options: .regularExpression) != nil
            ? "turkish"
            : "english"

        let embedding = try await embeddingService.getOrCreateEmbedding(for: searchQuery)

        async let vectorTask = SupabaseService.shared.searchLibraryChunksVector(
            fileIds: fileIds,
            embedding: embedding,
            limit: topK,
            similarityThreshold: RAGConfig.similarityThreshold
        )
        async let bm25Task = SupabaseService.shared.searchLibraryChunksBM25(
            fileIds: fileIds,
            query: searchQuery,
            limit: topK,
            language: language
        )

        // Bir bacağın düşmesi aramayı düşürmez; ikisi de boşsa bağlam boş döner
        // ve ViewModel "dokümanlarda yok" yoluna gider.
        let vectorResults = (try? await vectorTask) ?? []
        let bm25Results = (try? await bm25Task) ?? []

        let fused = fuse(
            vectorResults: vectorResults,
            bm25Results: bm25Results,
            nameByFile: nameByFile
        )
        guard !fused.isEmpty else { return ("", []) }

        return buildContext(from: fused)
    }

    // MARK: - Fusion & Context

    private func fuse(
        vectorResults: [SupabaseLibraryVectorResult],
        bm25Results: [SupabaseLibraryBM25Result],
        nameByFile: [UUID: String]
    ) -> [LibraryChunk] {
        var fused: [UUID: LibraryChunk] = [:]

        for (rank, result) in vectorResults.enumerated() {
            let score = RAGConfig.vectorWeight / (RAGConfig.rrfK + Float(rank + 1))
            fused[result.id] = LibraryChunk(
                id: result.id,
                fileId: result.file_id,
                fileName: nameByFile[result.file_id] ?? "Doküman",
                content: result.content,
                pageNumber: result.page_number,
                rrfScore: score
            )
        }

        for (rank, result) in bm25Results.enumerated() {
            let score = RAGConfig.bm25Weight / (RAGConfig.rrfK + Float(rank + 1))
            if var existing = fused[result.id] {
                existing.rrfScore += score
                fused[result.id] = existing
            } else {
                fused[result.id] = LibraryChunk(
                    id: result.id,
                    fileId: result.file_id,
                    fileName: nameByFile[result.file_id] ?? "Doküman",
                    content: result.content,
                    pageNumber: result.page_number,
                    rrfScore: score
                )
            }
        }

        return fused.values.sorted { $0.rrfScore > $1.rrfScore }
    }

    private func buildContext(
        from chunks: [LibraryChunk]
    ) -> (context: String, chunks: [LibraryChunk]) {
        var blocks: [String] = []
        var usedChunks: [LibraryChunk] = []
        var tokens = 0

        for (index, chunk) in chunks.enumerated() {
            let pageLabel = chunk.pageNumber.map { ", Sayfa \($0)" } ?? ""
            let block = "[\(index + 1)] (\(chunk.fileName)\(pageLabel))\n\(chunk.content)"
            let blockTokens = Int(Float(block.split(separator: " ").count) * RAGConfig.tokenMultiplier)
            if tokens + blockTokens > maxContextTokens { break }
            tokens += blockTokens
            blocks.append(block)
            usedChunks.append(chunk)
        }

        return (blocks.joined(separator: "\n\n---\n\n"), usedChunks)
    }

    private func translateIfNeeded(_ query: String) async -> String {
        (try? await GeminiService.shared.translateQueryForSearch(query)) ?? query
    }
}
