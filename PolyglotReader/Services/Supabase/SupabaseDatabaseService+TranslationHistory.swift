import Foundation
import Supabase
import PostgREST

// MARK: - Translation History Operations
/// Kept in an extension so the main service type stays inside the lint
/// type-body budget; same client, same patterns.
extension SupabaseDatabaseService {
    // MARK: - Translation History Operations

    func saveTranslationHistory(
        fileId: String,
        userId: String,
        sourceText: String,
        translatedText: String
    ) async throws {
        struct HistoryInsert: Encodable {
            let file_id: String
            let user_id: String
            let source_text: String
            let translated_text: String
        }

        do {
            try await client
                .from("translation_history")
                .insert(HistoryInsert(
                    file_id: fileId,
                    user_id: userId,
                    source_text: sourceText,
                    translated_text: translatedText
                ))
                .execute()
        } catch let error as PostgrestError where error.code == "23505" {
            // Unique dedup: the same selection was already saved for this
            // file (e.g. cache-hit re-translation) — silently done.
            return
        }
    }

    func getTranslationHistory(userId: String) async throws -> [TranslationHistoryEntry] {
        struct HistoryRecord: Decodable {
            let id: String
            let file_id: String
            let source_text: String
            let translated_text: String
            let created_at: String
            let files: FileName?

            struct FileName: Decodable {
                let name: String
            }
        }

        let records: [HistoryRecord] = try await client
            .from("translation_history")
            .select("id, file_id, source_text, translated_text, created_at, files(name)")
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(500)
            .execute()
            .value

        return records.map { record in
            TranslationHistoryEntry(
                id: record.id,
                fileId: record.file_id,
                fileName: record.files?.name ?? "Unknown Document",
                sourceText: record.source_text,
                translatedText: record.translated_text,
                createdAt: DateFormatting.date(from: record.created_at)
            )
        }
    }

    func deleteTranslationHistory(id: String, userId: String) async throws {
        try await client
            .from("translation_history")
            .delete()
            .eq("id", value: id)
            .eq("user_id", value: userId)
            .execute()
    }
}
