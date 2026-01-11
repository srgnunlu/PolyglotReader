import Foundation
import PostgREST
import Supabase

extension SupabaseService {
    // MARK: - RAG & Search (Legacy Support)

    func saveDocumentChunks(
        fileId: String,
        chunks: [(content: String, embedding: [Float], pageNumber: Int?)]
    ) async throws {
        try await perform(category: .database) {
            try await database.saveDocumentChunks(fileId: fileId, chunks: chunks)
        }
    }

    func searchSimilarChunks(
        fileId: String,
        embedding: [Float],
        limit: Int,
        similarityThreshold: Float
    ) async throws -> [ChunkVectorSearchResult] {
        let results = try await perform(category: .database) {
            try await executeMatchChunks(
                fileId: fileId,
                embedding: embedding,
                limit: limit,
                threshold: similarityThreshold
            )
        }

        return results.map {
            ChunkVectorSearchResult(
                id: $0.id,
                content: $0.content,
                similarity: $0.similarity,
                pageNumber: $0.page_number
            )
        }
    }

    func searchChunksBM25(
        fileId: String,
        query: String,
        limit: Int
    ) async throws -> [ChunkBM25SearchResult] {
        let results = try await perform(category: .database) {
            try await executeBM25Search(
                fileId: fileId,
                query: query,
                limit: limit
            )
        }

        return results.map {
            ChunkBM25SearchResult(
                id: $0.id,
                content: $0.content,
                score: $0.rank,
                pageNumber: $0.page_number
            )
        }
    }

    func getChunkCount(fileId: String) async throws -> Int {
        let response = try await perform(category: .database) {
            try await client
                .from("document_chunks")
                .select("id", head: true, count: .exact)
                .eq("file_id", value: fileId)
                .execute()
        }

        // HEAD responses have no body; count is returned via Content-Range.
        return response.count ?? 0
    }

    func fetchChunkSlice(
        fileId: String,
        offset: Int,
        limit: Int,
        ascending: Bool
    ) async throws -> [SupabaseChunkSlice] {
        try await perform(category: .database) {
            try await database.fetchChunkSlice(
                fileId: fileId,
                offset: offset,
                limit: limit,
                ascending: ascending
            )
        }
    }

    // MARK: - Private Helpers

    private func executeMatchChunks(
        fileId: String,
        embedding: [Float],
        limit: Int,
        threshold: Float
    ) async throws -> [SupabaseRAGSearchResult] {
        let params = SupabaseRAGSearchParams(
            query_embedding: embedding,
            match_threshold: threshold,
            match_count: limit,
            file_id: fileId
        )

        return try await client
            .rpc("match_chunks", params: params)
            .execute()
            .value
    }

    private func executeBM25Search(
        fileId: String,
        query: String,
        limit: Int
    ) async throws -> [SupabaseBM25Result] {
        let params = SupabaseBM25Params(
            search_file_id: fileId,
            search_query: query,
            match_count: limit
        )

        return try await client
            .rpc("search_chunks_bm25", params: params)
            .execute()
            .value
    }
}
