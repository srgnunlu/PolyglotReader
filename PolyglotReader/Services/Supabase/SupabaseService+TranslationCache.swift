import Foundation
import Supabase

// MARK: - Translation Cache Row

/// Read model for the shared `translation_cache` table (also written by the web app).
struct CachedTranslationRow: Decodable {
    let translatedText: String

    enum CodingKeys: String, CodingKey {
        case translatedText = "translated_text"
    }
}

// MARK: - Translation Cache Access

extension SupabaseService {
    /// Looks up a cached translation for the current user by source hash.
    /// Returns nil when signed out or when no row exists.
    func fetchCachedTranslation(sourceHash: String) async throws -> CachedTranslationRow? {
        guard let userId = currentUser?.id else { return nil }

        let rows: [CachedTranslationRow] = try await perform(category: .database) {
            try await client
                .from("translation_cache")
                .select("translated_text")
                .eq("user_id", value: userId)
                .eq("source_hash", value: sourceHash)
                .limit(1)
                .execute()
                .value
        }
        return rows.first
    }

    /// Bumps `last_used_at` so rarely-used rows can be pruned server-side later.
    func touchCachedTranslation(sourceHash: String) async throws {
        guard let userId = currentUser?.id else { return }

        try await perform(category: .database) {
            _ = try await client
                .from("translation_cache")
                .update(["last_used_at": Self.isoTimestampNow()])
                .eq("user_id", value: userId)
                .eq("source_hash", value: sourceHash)
                .execute()
        }
    }

    /// Upserts a translation keyed by (user_id, source_hash) — matches the
    /// UNIQUE constraint in migration 20260704090000_add_translation_cache.sql.
    func upsertCachedTranslation(
        sourceHash: String,
        sourceText: String,
        translatedText: String,
        targetLang: String
    ) async throws {
        guard let userId = currentUser?.id else { return }

        let row = TranslationCacheUpsert(
            userId: userId,
            sourceHash: sourceHash,
            sourceText: sourceText,
            translatedText: translatedText,
            targetLang: targetLang,
            lastUsedAt: Self.isoTimestampNow()
        )

        try await perform(category: .database) {
            _ = try await client
                .from("translation_cache")
                .upsert(row, onConflict: "user_id,source_hash")
                .execute()
        }
    }

    private static func isoTimestampNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

// MARK: - Upsert Payload

private struct TranslationCacheUpsert: Encodable {
    let userId: String
    let sourceHash: String
    let sourceText: String
    let translatedText: String
    let targetLang: String
    let lastUsedAt: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case sourceHash = "source_hash"
        case sourceText = "source_text"
        case translatedText = "translated_text"
        case targetLang = "target_lang"
        case lastUsedAt = "last_used_at"
    }
}
