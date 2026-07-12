import Foundation

extension SupabaseService {
    // MARK: - Chat Delegation

    func saveChat(fileId: String, userId: String, role: String, content: String) async throws {
        try await perform(category: .database) {
            try await database.saveChat(
                fileId: fileId,
                userId: userId,
                role: role,
                content: content
            )
        }
    }

    // Alias for compatibility
    func saveChatMessage(fileId: String, role: String, content: String) async throws {
        guard let userId = currentUser?.id else { throw authenticationRequiredError() }
        try await perform(category: .database) {
            try await database.saveChat(fileId: fileId, userId: userId, role: role, content: content)
        }
    }

    func getChats(fileId: String) async throws -> [ChatMessage] {
        try await perform(category: .database) {
            try await database.getChats(fileId: fileId)
        }
    }

    // Alias for compatibility
    func getChatHistory(fileId: String) async throws -> [ChatMessage] {
        try await getChats(fileId: fileId)
    }

    func deleteChats(fileId: String) async throws {
        try await perform(category: .database) {
            try await database.deleteChats(fileId: fileId)
        }
    }

    // MARK: - Library Chat (multi-document)

    func saveLibraryChatMessage(role: String, content: String) async throws {
        guard let userId = currentUser?.id else { throw authenticationRequiredError() }
        try await perform(category: .database) {
            try await database.saveLibraryChat(userId: userId, role: role, content: content)
        }
    }

    func getLibraryChatHistory() async throws -> [ChatMessage] {
        guard let userId = currentUser?.id else { throw authenticationRequiredError() }
        return try await perform(category: .database) {
            try await database.getLibraryChats(userId: userId)
        }
    }

    func deleteLibraryChats() async throws {
        guard let userId = currentUser?.id else { throw authenticationRequiredError() }
        try await perform(category: .database) {
            try await database.deleteLibraryChats(userId: userId)
        }
    }
}
