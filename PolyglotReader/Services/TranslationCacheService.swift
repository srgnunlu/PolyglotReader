import CryptoKit
import Foundation

// MARK: - Cache Key

/// Builds translation cache keys for both legacy and literal policies.
///
/// The unversioned path stays byte-identical to the web implementation
/// (`text.trim().replace(/\s+/g, ' ')` + SHA-256 hex of
/// `"<targetLang>::<normalized>"`). The versioned literal policy deliberately
/// preserves internal whitespace so differently structured source text cannot
/// reuse a translation produced for another layout.
/// `nonisolated` is required because the project defaults to `MainActor`
/// isolation while these helpers are called synchronously from the cache actor.
nonisolated enum TranslationCacheKey {
    /// Trims leading/trailing whitespace and collapses every internal
    /// whitespace run (spaces, tabs, newlines) into a single space.
    /// The text is intentionally NOT lowercased — casing can change meaning.
    static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Lowercase SHA-256 hex digest of the UTF-8 cache payload. An optional
    /// policy namespace invalidates results produced under an older prompt
    /// contract without deleting users' history rows.
    static func hash(sourceText: String, targetLang: String, policyVersion: String? = nil) -> String {
        let namespace = policyVersion.map { "\($0)::" } ?? ""
        let preparedSource = policyVersion == TranslationPromptBuilder.policyVersion
            ? literalSource(sourceText)
            : normalize(sourceText)
        let payload = "\(namespace)\(targetLang)::\(preparedSource)"
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Literal translations retain internal whitespace because line breaks and
    /// table layout are part of the requested output contract.
    private static func literalSource(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - In-Memory LRU

/// Minimal LRU cache for translated strings.
/// Plain struct (no actor) so the eviction logic is unit-testable synchronously.
nonisolated struct TranslationLRUCache {
    let capacity: Int

    private var storage: [String: String] = [:]
    /// Keys ordered least-recently-used first. O(n) bookkeeping is fine at ~200 entries.
    private var recency: [String] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    var count: Int { storage.count }

    mutating func value(forKey key: String) -> String? {
        guard let value = storage[key] else { return nil }
        markUsed(key)
        return value
    }

    mutating func insert(_ value: String, forKey key: String) {
        storage[key] = value
        markUsed(key)
        while storage.count > capacity, let oldest = recency.first {
            recency.removeFirst()
            storage.removeValue(forKey: oldest)
        }
    }

    private mutating func markUsed(_ key: String) {
        if let index = recency.firstIndex(of: key) {
            recency.remove(at: index)
        }
        recency.append(key)
    }
}

// MARK: - Translation Cache Service

/// Two-layer translation cache: in-memory LRU (instant) + Supabase
/// `translation_cache` table (shared across iOS devices). Legacy, unversioned
/// keys remain compatible with the web app; literal-policy keys are namespaced.
///
/// Every remote failure degrades to a cache miss — translation must never
/// fail because of the cache, and remote errors are logged only once.
actor TranslationCacheService {
    static let shared = TranslationCacheService()

    /// The popup always caches under Turkish; matches the table default.
    static let defaultTargetLanguage = "tr"
    static let policyVersion = TranslationPromptBuilder.policyVersion

    private var memory: TranslationLRUCache
    private var hasLoggedRemoteFailure = false

    init(memoryCapacity: Int = 200) {
        self.memory = TranslationLRUCache(capacity: memoryCapacity)
    }

    /// Returns a cached translation, checking memory first, then Supabase.
    /// A remote hit warms the memory layer and bumps `last_used_at` in the background.
    func cachedTranslation(
        for sourceText: String,
        targetLang: String = TranslationCacheService.defaultTargetLanguage
    ) async -> String? {
        let key = TranslationCacheKey.hash(
            sourceText: sourceText,
            targetLang: targetLang,
            policyVersion: Self.policyVersion
        )
        if let hit = memory.value(forKey: key) {
            return hit
        }

        do {
            guard let row = try await SupabaseService.shared.fetchCachedTranslation(sourceHash: key) else {
                return nil
            }
            memory.insert(row.translatedText, forKey: key)
            // Fire-and-forget usage bump; never block or fail the caller.
            Task { try? await SupabaseService.shared.touchCachedTranslation(sourceHash: key) }
            return row.translatedText
        } catch {
            logRemoteFailureOnce(error)
            return nil
        }
    }

    /// Write-through: fills memory immediately and upserts to Supabase.
    /// Callers should invoke this fire-and-forget after a successful Gemini translation.
    func store(
        sourceText: String,
        translatedText: String,
        targetLang: String = TranslationCacheService.defaultTargetLanguage
    ) async {
        let normalized = TranslationCacheKey.normalize(sourceText)
        guard !normalized.isEmpty, !translatedText.isEmpty else { return }

        let key = TranslationCacheKey.hash(
            sourceText: sourceText,
            targetLang: targetLang,
            policyVersion: Self.policyVersion
        )
        memory.insert(translatedText, forKey: key)

        do {
            try await SupabaseService.shared.upsertCachedTranslation(
                sourceHash: key,
                sourceText: normalized,
                translatedText: translatedText,
                targetLang: targetLang
            )
        } catch {
            logRemoteFailureOnce(error)
        }
    }

    // MARK: - Private

    /// Logs the first remote failure only (e.g. migration not yet applied).
    /// Never logs source or translated text — it may contain sensitive content.
    private func logRemoteFailureOnce(_ error: Error) {
        guard !hasLoggedRemoteFailure else { return }
        hasLoggedRemoteFailure = true
        logWarning(
            "TranslationCache",
            "Uzak çeviri önbelleği kullanılamıyor, çeviri Gemini ile devam edecek",
            details: String(describing: type(of: error))
        )
    }
}
