import Foundation

// MARK: - RAG & Search Types (Non-isolated)

struct SupabaseRAGSearchParams: Encodable, @unchecked Sendable {
    let query_embedding: [Float]
    let match_threshold: Float
    let match_count: Int
    let file_id: String

    private enum CodingKeys: String, CodingKey {
        case query_embedding, match_threshold, match_count, file_id
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(query_embedding, forKey: .query_embedding)
        try container.encode(match_threshold, forKey: .match_threshold)
        try container.encode(match_count, forKey: .match_count)
        try container.encode(file_id, forKey: .file_id)
    }
}

struct SupabaseRAGSearchResult: Decodable, @unchecked Sendable {
    let id: UUID // Assuming UUID
    let content: String
    let similarity: Float
    let page_number: Int?
}

struct SupabaseBM25Params: Encodable, @unchecked Sendable {
    let search_file_id: String
    let search_query: String
    let match_count: Int

    private enum CodingKeys: String, CodingKey {
        case search_file_id, search_query, match_count
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(search_file_id, forKey: .search_file_id)
        try container.encode(search_query, forKey: .search_query)
        try container.encode(match_count, forKey: .match_count)
    }
}

struct SupabaseBM25Result: Decodable, @unchecked Sendable {
    let id: UUID? // BM25 usually returns id?
    let content: String
    let rank: Float
    let page_number: Int?
}

struct ChunkVectorSearchResult: Sendable {
    let id: UUID
    let content: String
    let similarity: Float
    let pageNumber: Int?
}

struct ChunkBM25SearchResult: Sendable {
    let id: UUID?
    let content: String
    let score: Float
    let pageNumber: Int?
}

struct SupabaseChunkSlice: Decodable, @unchecked Sendable {
    let id: UUID
    let content: String
    let page_number: Int?
    let chunk_index: Int
}

struct SupabaseImageSearchParams: Encodable, Sendable {
    let file_id: String
    let query_embedding: [Float]
    let match_threshold: Float
    let match_count: Int

    private enum CodingKeys: String, CodingKey {
        case file_id = "target_file_id"
        case query_embedding, match_threshold, match_count
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(file_id, forKey: .file_id)
        try container.encode(query_embedding, forKey: .query_embedding)
        try container.encode(match_threshold, forKey: .match_threshold)
        try container.encode(match_count, forKey: .match_count)
    }
}

// MARK: - Reading Progress

struct ReadingProgress: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: String
    let fileId: String
    let page: Int
    let offsetX: Double
    let offsetY: Double
    let zoomScale: Double
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case fileId = "file_id"
        case page
        case offsetX = "offset_x"
        case offsetY = "offset_y"
        case zoomScale = "zoom_scale"
        case updatedAt = "updated_at"
    }
}
