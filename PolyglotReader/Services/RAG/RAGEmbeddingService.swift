import Foundation
import CryptoKit

// MARK: - RAG Embedding Service (P3 Enhanced)
class RAGEmbeddingService {
    static let shared = RAGEmbeddingService()

    private let geminiApiKey = Config.geminiApiKey

    // MARK: - Embedding Cache (LRU + Disk)
    private var embeddingCache: [String: EmbeddingCacheEntry] = [:]
    private var cacheAccessOrder: [String] = []

    // MARK: - P3.2: Cache Statistics
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    private var diskCacheHits: Int = 0

    // MARK: - P3.2: Disk Cache
    private let diskCacheEnabled = true
    private lazy var diskCacheURL: URL? = {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let embeddingDir = cacheDir.appendingPathComponent("EmbeddingCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: embeddingDir, withIntermediateDirectories: true)
        return embeddingDir
    }()

    private init() {
        loadDiskCacheIndex()
    }

    // MARK: - Cache Operations

    /// Cache hash oluşturur
    private func cacheKey(for text: String) -> String {
        let data = Data(text.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Cache'ten embedding al veya oluştur (P3.2: Disk cache + stats)
    func getOrCreateEmbedding(for text: String) async throws -> [Float] {
        let key = cacheKey(for: text)

        // 1. Memory cache kontrolü
        if let entry = embeddingCache[key], !entry.isExpired {
            cacheHits += 1
            updateCacheAccess(key: key)
            return entry.embedding
        }

        // 2. Disk cache kontrolü (P3.2)
        if diskCacheEnabled, let embedding = loadFromDiskCache(key: key) {
            diskCacheHits += 1
            addToCache(key: key, embedding: embedding) // Memory cache'e de ekle
            return embedding
        }

        // 3. Cache miss - yeni embedding oluştur
        cacheMisses += 1
        let embedding = try await ErrorHandlingService.retry {
            try await createEmbeddingFromAPI(for: text)
        }

        // 4. Her iki cache'e de ekle
        addToCache(key: key, embedding: embedding)
        saveToDiskCache(key: key, embedding: embedding)

        return embedding
    }

    // MARK: - P3.2: Batch Embedding (API rate limit aware)

    /// Birden fazla metin için embedding oluşturur (paralel, rate limit aware)
    func getBatchEmbeddings(for texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        let batchSize = 5 // Gemini rate limit için güvenli batch boyutu

        for batch in texts.chunked(into: batchSize) {
            let batchResults = try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
                for (index, text) in batch.enumerated() {
                    group.addTask {
                        let embedding = try await self.getOrCreateEmbedding(for: text)
                        return (index, embedding)
                    }
                }

                var ordered: [(Int, [Float])] = []
                for try await result in group {
                    ordered.append(result)
                }
                return ordered.sorted { $0.0 < $1.0 }.map { $0.1 }
            }
            results.append(contentsOf: batchResults)

            // Rate limit için bekle (batch'ler arası)
            if batch.count == batchSize {
                try? await Task.sleep(nanoseconds: RAGConfig.rateLimitDelay * 2)
            }
        }

        return results
    }

    /// Cache'e embedding ekler (LRU eviction ile)
    private func addToCache(key: String, embedding: [Float]) {
        // Önce eski key'i kaldır (varsa)
        if embeddingCache[key] != nil {
            cacheAccessOrder.removeAll { $0 == key }
        }

        // LRU eviction
        while embeddingCache.count >= RAGConfig.cacheMaxSize {
            if let oldestKey = cacheAccessOrder.first {
                embeddingCache.removeValue(forKey: oldestKey)
                cacheAccessOrder.removeFirst()
            } else {
                break
            }
        }

        // Yeni entry ekle
        embeddingCache[key] = EmbeddingCacheEntry(
            embedding: embedding,
            timestamp: Date(),
            queryHash: key
        )
        cacheAccessOrder.append(key)
    }

    /// Cache erişim sırasını günceller
    private func updateCacheAccess(key: String) {
        cacheAccessOrder.removeAll { $0 == key }
        cacheAccessOrder.append(key)
    }

    /// Cache'i temizler
    func clearCache() {
        embeddingCache.removeAll()
        cacheAccessOrder.removeAll()
        logInfo("RAGEmbeddingService", "Embedding cache temizlendi")
    }

    /// P3.2: Enhanced cache stats with hit rate
    func getCacheStats() -> (size: Int, maxSize: Int, hitRate: Float, diskHits: Int) {
        let totalRequests = cacheHits + cacheMisses
        let hitRate = totalRequests > 0 ? Float(cacheHits + diskCacheHits) / Float(totalRequests) : 0
        return (embeddingCache.count, RAGConfig.cacheMaxSize, hitRate, diskCacheHits)
    }

    // MARK: - P3.2: Disk Cache Operations

    private func loadDiskCacheIndex() {
        // Uygulama başlangıcında disk cache'i kontrol et
        guard diskCacheEnabled, let cacheDir = diskCacheURL else { return }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.creationDateKey])
            logInfo("RAGEmbeddingService", "Disk cache yüklendi", details: "\(files.count) embedding bulundu")
        } catch {
            logWarning("RAGEmbeddingService", "Disk cache index yüklenemedi", details: error.localizedDescription)
        }
    }

    private func loadFromDiskCache(key: String) -> [Float]? {
        guard let cacheDir = diskCacheURL else { return nil }
        let fileURL = cacheDir.appendingPathComponent("\(key).emb")

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)

            // TTL kontrolü - dosya oluşturma tarihine bak
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            if let creationDate = attributes[.creationDate] as? Date {
                let age = Date().timeIntervalSince(creationDate)
                if age > RAGConfig.cacheTTL {
                    // Süresi dolmuş - sil
                    try? FileManager.default.removeItem(at: fileURL)
                    return nil
                }
            }

            // Float array'e dönüştür
            let floats = data.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self))
            }

            return floats.isEmpty ? nil : floats
        } catch {
            return nil
        }
    }

    private func saveToDiskCache(key: String, embedding: [Float]) {
        guard diskCacheEnabled, let cacheDir = diskCacheURL else { return }
        let fileURL = cacheDir.appendingPathComponent("\(key).emb")

        // Float array'i Data'ya dönüştür
        let data = embedding.withUnsafeBufferPointer { buffer in
            Data(buffer: buffer)
        }

        do {
            try data.write(to: fileURL)
        } catch {
            logWarning("RAGEmbeddingService", "Disk cache yazılamadı", details: error.localizedDescription)
        }
    }

    /// Disk cache'i temizler (eski dosyaları siler)
    func cleanupDiskCache(olderThan interval: TimeInterval = RAGConfig.cacheTTL) {
        guard let cacheDir = diskCacheURL else { return }

        do {
            let files = try FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.creationDateKey])
            var deletedCount = 0

            for file in files {
                let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                if let creationDate = attributes[.creationDate] as? Date {
                    if Date().timeIntervalSince(creationDate) > interval {
                        try FileManager.default.removeItem(at: file)
                        deletedCount += 1
                    }
                }
            }

            if deletedCount > 0 {
                logInfo("RAGEmbeddingService", "Disk cache temizlendi", details: "\(deletedCount) eski dosya silindi")
            }
        } catch {
            logWarning("RAGEmbeddingService", "Disk cache temizleme hatası", details: error.localizedDescription)
        }
    }

    // MARK: - API Calls

    /// Gemini API'den embedding oluşturur
    private func createEmbeddingFromAPI(for text: String) async throws -> [Float] {
        let request = try buildEmbeddingRequest(text: text)
        let (data, response) = try await SecurityManager.shared.secureSession.data(for: request)
        let httpResponse = try validateEmbeddingResponse(response)
        try handleEmbeddingStatus(httpResponse.statusCode)
        return try decodeEmbedding(from: data)
    }

    private func buildEmbeddingRequest(text: String) throws -> URLRequest {
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/"
        let path = "\(RAGConfig.embeddingModel):embedContent?key=\(geminiApiKey)"
        guard let url = URL(string: endpoint + path) else {
            throw AppError.ai(reason: .unavailable, underlying: RAGError.embeddingFailed)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: buildEmbeddingBody(text: text))
        return request
    }

    private func buildEmbeddingBody(text: String) -> [String: Any] {
        [
            "model": "models/\(RAGConfig.embeddingModel)",
            "content": [
                "parts": [
                    ["text": text]
                ]
            ]
        ]
    }

    private func validateEmbeddingResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.network(reason: .invalidResponse, underlying: RAGError.embeddingFailed)
        }
        return httpResponse
    }

    private func handleEmbeddingStatus(_ statusCode: Int) throws {
        guard (200...299).contains(statusCode) else {
            logError("RAGEmbeddingService", "Embedding API hatası - Status: \(statusCode)")
            switch statusCode {
            case 401, 403:
                throw AppError.authentication(reason: .forbidden, underlying: RAGError.embeddingFailed)
            case 429:
                throw AppError.ai(reason: .rateLimited, underlying: RAGError.embeddingFailed)
            case 500...599:
                throw AppError.ai(reason: .unavailable, underlying: RAGError.embeddingFailed)
            default:
                throw AppError.network(
                    reason: .server(statusCode: statusCode),
                    underlying: RAGError.embeddingFailed
                )
            }
        }
    }

    private func decodeEmbedding(from data: Data) throws -> [Float] {
        struct EmbeddingResponse: Decodable {
            struct Embedding: Decodable {
                let values: [Float]
            }
            let embedding: Embedding
        }

        do {
            let result = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
            return result.embedding.values
        } catch {
            throw AppError.ai(reason: .parseFailed, underlying: error)
        }
    }
}

// MARK: - P3.2: Array Extension for Batching
private extension Array {
    /// Array'i belirtilen boyutta parçalara böler
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
