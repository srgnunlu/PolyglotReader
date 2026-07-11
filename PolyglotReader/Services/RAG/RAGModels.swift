import Foundation

// MARK: - Sentence Structure
struct Sentence {
    let text: String
    let wordCount: Int
    let isPageBreak: Bool
    let pageNumber: Int?
}

// MARK: - Paragraph Structure
struct Paragraph {
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
struct EmbeddingCacheEntry {
    let embedding: [Float]
    let timestamp: Date
    let queryHash: String

    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > RAGConfig.cacheTTL
    }
}

// MARK: - Chunk Content Type (P1)
enum ChunkContentType: String, Codable {
    case text           // Normal metin
    case table          // Tablo içeriği
    case list           // Liste içeriği
    case mixed          // Karma içerik
    case heading        // Başlık/bölüm başlangıcı
}

// MARK: - Document Chunk Model (Enhanced P1)
struct DocumentChunk: Codable, Identifiable {
    let id: UUID
    var fileId: UUID
    var chunkIndex: Int
    var content: String
    var pageNumber: Int?
    var startPage: Int?   // Chunk birden fazla sayfaya yayılabilir
    var endPage: Int?
    var similarity: Float? // Arama sonucu için

    // MARK: - P1: Zengin Metadata
    var sectionTitle: String?          // "2.1 Yöntemler", "Giriş" vb.
    var contentType: ChunkContentType  // İçerik tipi
    var containsTable: Bool            // Tablo içeriyor mu
    var containsList: Bool             // Liste içeriyor mu
    var imageReferences: [UUID]        // İlgili görsel ID'leri

    /// Chunk için özet bilgi (context builder için)
    var metadataSummary: String {
        var parts: [String] = []
        if let section = sectionTitle {
            parts.append("Bölüm: \(section)")
        }
        if containsTable {
            parts.append("📊 Tablo içeriyor")
        }
        if containsList {
            parts.append("📝 Liste içeriyor")
        }
        if !imageReferences.isEmpty {
            parts.append("🖼️ \(imageReferences.count) görsel")
        }
        return parts.isEmpty ? "" : "[\(parts.joined(separator: " | "))]"
    }

    init(
        id: UUID = UUID(),
        fileId: UUID,
        chunkIndex: Int,
        content: String,
        pageNumber: Int? = nil,
        startPage: Int? = nil,
        endPage: Int? = nil,
        similarity: Float? = nil,
        sectionTitle: String? = nil,
        contentType: ChunkContentType = .text,
        containsTable: Bool = false,
        containsList: Bool = false,
        imageReferences: [UUID] = []
    ) {
        self.id = id
        self.fileId = fileId
        self.chunkIndex = chunkIndex
        self.content = content
        self.pageNumber = pageNumber
        self.startPage = startPage
        self.endPage = endPage
        self.similarity = similarity
        self.sectionTitle = sectionTitle
        self.contentType = contentType
        self.containsTable = containsTable
        self.containsList = containsList
        self.imageReferences = imageReferences
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
        // rerankScore is on the LLM's 0-10 scale, rrfScore on RRF's ~0.01-0.05
        // scale. Normalizing rerank to 0-1 keeps partial reranks on one scale:
        // a chunk the LLM scored 0 (irrelevant) now sorts BELOW an unranked
        // chunk's RRF score instead of tying with it, while any chunk scored
        // >= 1/10 still outranks all unranked ones.
        if let rerankScore { return rerankScore / 10.0 }
        return rrfScore
    }
}
