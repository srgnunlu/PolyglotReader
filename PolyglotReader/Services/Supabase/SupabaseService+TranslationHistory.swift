import Foundation

extension SupabaseService {
    // MARK: - Translation History Delegation

    /// Persists a completed quick-translation for the Notebook's
    /// Çeviriler category. Duplicate (user, file, source) rows are
    /// deduped at the database layer.
    func saveTranslationToHistory(
        fileId: String,
        sourceText: String,
        translatedText: String
    ) async throws {
        guard let userId = currentUser?.id else { throw authenticationRequiredError() }
        try await perform(category: .database) {
            try await database.saveTranslationHistory(
                fileId: fileId,
                userId: userId,
                sourceText: sourceText,
                translatedText: translatedText
            )
        }
    }

    func getTranslationHistory() async throws -> [TranslationHistoryEntry] {
        guard let userId = currentUser?.id else { throw authenticationRequiredError() }
        return try await perform(category: .database) {
            try await database.getTranslationHistory(userId: userId)
        }
    }

    func deleteTranslationHistory(id: String) async throws {
        guard let userId = currentUser?.id else { throw authenticationRequiredError() }
        try await perform(category: .database) {
            try await database.deleteTranslationHistory(id: id, userId: userId)
        }
    }
}
