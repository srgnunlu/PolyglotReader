import Foundation

// MARK: - RAG Configuration (Profesyonel PDF Chat Modu v3.0)
enum RAGConfig {
    // MARK: - Semantic Chunking Settings (NotebookLM Optimized)
    // Araştırma: 500-600 kelime optimal bağlam koruması sağlıyor
    // Kaynak: https://www.firecrawl.dev/blog/best-chunking-strategies-rag-2025
    static let targetChunkSize = 500        // 300→500: Daha iyi bağlam, daha az parçalanma
    static let minChunkSize = 60            // 40→60: Çok kısa chunk'ları engelle
    static let maxChunkSize = 750           // 450→750: Büyük paragrafları koru
    static let overlapSentences = 2         // 3→2: Büyük chunk = daha az overlap gerekli

    // MARK: - Search Settings (Precision-Focused)
    static let topK = 10                    // 8→10: Daha fazla aday, reranking ile filtrelenir
    static let rerankTopK = 6               // Context'e dahil edilecek chunk sayısı
    static let similarityThreshold: Float = 0.45  // 0.30→0.45: Alakasız chunk'ları filtrele
    static let minAnswerSimilarity: Float = 0.55  // 0.50→0.55: Daha yüksek güven eşiği
    static let bm25Weight: Float = 0.35     // Keyword matching ağırlığı
    static let vectorWeight: Float = 0.65   // Semantic search ağırlığı
    static let rrfK: Float = 60             // RRF k parametresi (standart)

    // MARK: - Token Limits (Dynamic Context)
    // Gemini 1.5 Pro: 1M token destekliyor, daha agresif kullan
    static let maxContextTokens = 30000     // 20k→30k: Daha zengin bağlam
    static let shortQueryContextTokens = 12000  // Kısa sorular için optimize
    static let comparisonContextTokens = 50000  // Karşılaştırma sorguları için
    static let tokenMultiplier: Float = 1.3 // Kelime → token çarpanı

    // MARK: - Cache Settings (Extended)
    static let cacheMaxSize = 500           // 300→500: Daha büyük cache
    static let cacheTTL: TimeInterval = 14400 // 2→4 saat (7200→14400)

    // MARK: - API Settings
    static let embeddingModel = "text-embedding-004"
    static let embeddingDimension = 768
    static let rateLimitDelay: UInt64 = 25_000_000 // 30→25ms (daha hızlı)

    // MARK: - Query Enhancement (Always Active)
    static let enableQueryExpansionForShortQueries = true  // < 5 kelime için otomatik
    static let enableDefaultReranking = true               // Her zaman rerank yap
    static let shortQueryThreshold = 5                     // Kısa sorgu kelime limiti
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
