import Foundation

extension SupabaseService {
    // MARK: - Tag Delegation

    func listTags() async throws -> [Tag] {
        guard let userId = currentUser?.id else {
            throw authenticationRequiredError()
        }
        return try await perform(category: .database) {
            try await database.listTags(userId: userId)
        }
    }

    // MARK: - Folder Delegation

    func getFolders(parentId: UUID? = nil) async throws -> [Folder] {
        guard let userId = currentUser?.id else {
            throw authenticationRequiredError()
        }
        return try await perform(category: .database) {
            try await database.getFolders(userId: userId, parentId: parentId)
        }
    }

    // Alias for compatibility
    func listFolders(parentId: UUID? = nil) async throws -> [Folder] {
        try await getFolders(parentId: parentId)
    }

    func createFolder(name: String, color: String? = nil, parentId: UUID? = nil) async throws -> Folder {
        guard let userId = currentUser?.id else {
            throw authenticationRequiredError()
        }
        return try await perform(category: .database) {
            try await database.createFolder(name: name, userId: userId, color: color, parentId: parentId)
        }
    }

    func deleteFolder(id: String) async throws {
        try await perform(category: .database) {
            try await database.deleteFolder(id: id)
        }
    }

    // MARK: - Tag Operations

    func getFileTags(fileId: String) async throws -> [Tag] {
        try await perform(category: .database) {
            try await database.getFileTags(fileId: fileId)
        }
    }

    /// Batch load tags for multiple files in a single query
    /// Use this instead of calling getFileTags in a loop to avoid N+1 queries
    func getFileTagsBatch(fileIds: [String]) async throws -> [String: [Tag]] {
        try await perform(category: .database) {
            try await database.getFileTagsBatch(fileIds: fileIds)
        }
    }

    func getOrCreateTag(name: String) async throws -> Tag {
        guard let userId = currentUser?.id else {
            throw authenticationRequiredError()
        }
        return try await perform(category: .database) {
            try await database.getOrCreateTag(name: name, userId: userId)
        }
    }

    func addTagsToFile(fileId: String, tagIds: [UUID]) async throws {
        try await perform(category: .database) {
            try await database.addTagsToFile(fileId: fileId, tagIds: tagIds)
        }
    }

    func cleanupUnusedTags() async throws {
        try await perform(category: .database) {
            try await database.cleanupUnusedTags()
        }
    }
}
