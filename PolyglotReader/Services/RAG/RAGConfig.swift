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
    // NOT: topK / rerankTopK / similarityThreshold web ile eşitlendi
    // (web/src/lib/rag.ts RAG_CONFIG) — iki platform aynı soruya aynı chunk
    // setini getirsin. Birini değiştirirsen diğerini de değiştir.
    static let topK = 12                    // 10→12: web (15) ile orta noktada eşitlendi
    /// Derin arama aday havuzu: geniş havuz + LLM rerank = gerçek "derin" mod.
    /// Normal modda 12 aday yeterli; derin modda 24 aday çekilip yeniden sıralanır.
    static let deepSearchTopK = 24
    static let rerankTopK = 8               // 6→8: Context'e dahil edilecek chunk (web ile aynı)
    static let similarityThreshold: Float = 0.35  // 0.45→0.35: cross-lingual (TR soru↔EN doküman) recall
    static let minAnswerSimilarity: Float = 0.55  // 0.50→0.55: Daha yüksek güven eşiği
    static let bm25Weight: Float = 0.35     // Keyword matching ağırlığı
    static let vectorWeight: Float = 0.65   // Semantic search ağırlığı
    static let rrfK: Float = 60             // RRF k parametresi (standart)

    // MARK: - Token Limits (Dynamic Context)
    // Gemini 1.5 Pro: 1M token destekliyor, daha agresif kullan
    static let maxContextTokens = 30000     // 20k→30k: Daha zengin bağlam
    static let shortQueryContextTokens = 12000  // Kısa sorular için optimize
    static let comparisonContextTokens = 50000  // Karşılaştırma sorguları için
    /// Derin aramada bağlam tabanı: sorgu tipi ne olursa olsun en az bu kadar
    /// token'lık bağlam kurulur — geniş aday havuzu boşa gitmesin.
    static let deepSearchMinContextTokens = 40000
    static let tokenMultiplier: Float = 1.3 // Kelime → token çarpanı

    // MARK: - Cache Settings (Extended)
    static let cacheMaxSize = 500           // 300→500: Daha büyük cache
    static let cacheTTL: TimeInterval = 14400 // 2→4 saat (7200→14400)

    // MARK: - API Settings
    // text-embedding-004 emekli (404). gemini-embedding-001 varsayılanı 3072
    // boyut; DB şeması vector(768) olduğundan istek gövdesinde
    // outputDimensionality=768 kesilmesi yapılır (RAGEmbeddingService).
    // Kesilmiş vektörler normalize değildir — arama cosine kullandığı için
    // sıralama etkilenmez.
    static let embeddingModel = "gemini-embedding-001"
    static let embeddingDimension = 768
    static let rateLimitDelay: UInt64 = 100_000_000 // 100ms - Rate limit koruması
    static let batchSize = 5                         // Batch embedding boyutu
    static let maxRetryAttempts = 3                  // Hata durumunda retry sayısı
    static let retryDelayBase: UInt64 = 500_000_000  // 500ms - Exponential backoff başlangıç

    // MARK: - Query Enhancement
    static let enableQueryExpansionForShortQueries = true  // < 5 kelime için otomatik
    /// NOT: ChatViewModel her çağrıda bayrağı açıkça geçtiği için bu default
    /// yalnız doğrudan performRAGQuery çağrılarında devreye girer — pratikte
    /// rerank yalnızca Derin Arama modunda çalışır.
    static let enableDefaultReranking = true
    static let shortQueryThreshold = 5                     // Kısa sorgu kelime limiti
    /// Minimum candidate count for the extra Gemini rerank call. rerankTopK'nın
    /// biraz üstü: az-aday senaryolarında (küçük doküman, örtüşen sonuçlar)
    /// rerank sessizce devre dışı kalmasın — sıralama yine de önemli.
    static let rerankMinCandidates = 8
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
