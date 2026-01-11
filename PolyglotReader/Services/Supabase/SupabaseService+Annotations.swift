import Foundation

extension SupabaseService {
    // MARK: - Annotation Delegation

    func saveAnnotation(_ annotation: Annotation) async throws {
        guard let userId = currentUser?.id else {
            throw authenticationRequiredError()
        }
        try await perform(category: .database) {
            try await annotations.saveAnnotation(annotation, userId: userId)
        }
    }

    func saveAnnotations(_ annotationList: [Annotation]) async throws -> Int {
        guard let userId = currentUser?.id else {
            throw authenticationRequiredError()
        }
        return try await perform(category: .database) {
            try await annotations.saveAnnotations(annotationList, userId: userId)
        }
    }

    func getAnnotations(fileId: String) async throws -> [Annotation] {
        try await perform(category: .database) {
            try await annotations.getAnnotations(fileId: fileId)
        }
    }

    func deleteAnnotation(id: String) async throws {
        try await perform(category: .database) {
            try await annotations.deleteAnnotation(id: id)
        }
    }

    func getAllAnnotations() async throws -> [SupabaseAnnotationService.AnnotationResult] {
        guard let userId = currentUser?.id else {
            throw authenticationRequiredError()
        }
        return try await perform(category: .database) {
            try await annotations.getAllAnnotations(userId: userId)
        }
    }

    func getAllAnnotations(userId: String) async throws -> [SupabaseAnnotationService.AnnotationResult] {
        try await perform(category: .database) {
            try await annotations.getAllAnnotations(userId: userId)
        }
    }

    func getAnnotationStats() async throws -> AnnotationStats {
        guard let userId = currentUser?.id else {
            throw authenticationRequiredError()
        }
        return try await perform(category: .database) {
            try await annotations.getAnnotationStats(userId: userId)
        }
    }

    func getAnnotationStats(userId: String) async throws -> AnnotationStats {
        try await perform(category: .database) {
            try await annotations.getAnnotationStats(userId: userId)
        }
    }

    func getFileAnnotationCounts() async throws -> [String: Int] {
        guard let userId = currentUser?.id else {
            throw authenticationRequiredError()
        }
        return try await perform(category: .database) {
            try await annotations.getFileAnnotationCounts(userId: userId)
        }
    }

    func getFileAnnotationCounts(userId: String) async throws -> [String: Int] {
        try await perform(category: .database) {
            try await annotations.getFileAnnotationCounts(userId: userId)
        }
    }

    func toggleAnnotationFavorite(id: String) async throws -> Bool {
        try await perform(category: .database) {
            try await annotations.toggleAnnotationFavorite(id: id)
        }
    }

    func updateAnnotation(id: String, note: String? = nil, color: String? = nil) async throws {
        try await perform(category: .database) {
            try await annotations.updateAnnotation(id: id, note: note, color: color)
        }
    }
}
