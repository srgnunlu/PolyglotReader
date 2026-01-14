import Foundation
import Combine
@testable import PolyglotReader

/// Mock implementation of SupabaseService for testing
@MainActor
final class MockSupabaseService: ObservableObject {
    
    // MARK: - Published State
    
    @Published var currentUser: User?
    @Published var isLoading = false
    
    // MARK: - Mock Data Storage
    
    var mockUser: User?
    var mockError: AppError?
    var storedAnnotations: [String: [Annotation]] = [:]  // fileId -> annotations
    var storedMessages: [String: [ChatMessage]] = [:]    // fileId -> messages
    var storedFiles: [PDFDocumentMetadata] = []
    var storedFolders: [Folder] = []
    var storedTags: [Tag] = []
    
    // MARK: - Call Tracking
    
    var callCount: [String: Int] = [:]
    
    // MARK: - Auth Methods
    
    func getSession() async -> User? {
        recordCall("getSession")
        return mockUser
    }
    
    func signInWithOAuth(provider: String) async throws {
        recordCall("signInWithOAuth")
        
        if let error = mockError {
            throw error
        }
        
        currentUser = mockUser
    }
    
    func signInWithApple(idToken: String, nonce: String) async throws {
        recordCall("signInWithApple")
        
        if let error = mockError {
            throw error
        }
        
        currentUser = mockUser
    }
    
    func signInWithGoogle(idToken: String, accessToken: String) async throws {
        recordCall("signInWithGoogle")
        
        if let error = mockError {
            throw error
        }
        
        currentUser = mockUser
    }
    
    func signOut() async throws {
        recordCall("signOut")
        
        if let error = mockError {
            throw error
        }
        
        currentUser = nil
        mockUser = nil
    }
    
    // MARK: - File Methods
    
    func getUserFiles() async throws -> [PDFDocumentMetadata] {
        recordCall("getUserFiles")
        
        if let error = mockError {
            throw error
        }
        
        return storedFiles
    }
    
    func getFileURL(storagePath: String) async throws -> URL {
        recordCall("getFileURL")
        
        if let error = mockError {
            throw error
        }
        
        return URL(string: "https://example.com/\(storagePath)")!
    }
    
    func uploadFile(data: Data, fileName: String, contentType: String) async throws -> PDFDocumentMetadata {
        recordCall("uploadFile")
        
        if let error = mockError {
            throw error
        }
        
        let metadata = TestDataFactory.makePDFMetadata(name: fileName)
        storedFiles.append(metadata)
        return metadata
    }
    
    func deleteFile(fileId: String) async throws {
        recordCall("deleteFile")
        
        if let error = mockError {
            throw error
        }
        
        storedFiles.removeAll { $0.id == fileId }
    }
    
    // MARK: - Annotation Methods
    
    func getAnnotations(fileId: String) async throws -> [Annotation] {
        recordCall("getAnnotations")
        
        if let error = mockError {
            throw error
        }
        
        return storedAnnotations[fileId] ?? []
    }
    
    func saveAnnotation(_ annotation: Annotation) async throws {
        recordCall("saveAnnotation")
        
        if let error = mockError {
            throw error
        }
        
        var annotations = storedAnnotations[annotation.fileId] ?? []
        if let index = annotations.firstIndex(where: { $0.id == annotation.id }) {
            annotations[index] = annotation
        } else {
            annotations.append(annotation)
        }
        storedAnnotations[annotation.fileId] = annotations
    }
    
    func updateAnnotation(_ annotation: Annotation) async throws {
        recordCall("updateAnnotation")
        try await saveAnnotation(annotation)
    }
    
    func deleteAnnotation(_ annotationId: String, fileId: String) async throws {
        recordCall("deleteAnnotation")
        
        if let error = mockError {
            throw error
        }
        
        storedAnnotations[fileId]?.removeAll { $0.id == annotationId }
    }
    
    // MARK: - Chat Methods
    
    func getChatHistory(fileId: String) async throws -> [ChatMessage] {
        recordCall("getChatHistory")
        
        if let error = mockError {
            throw error
        }
        
        return storedMessages[fileId] ?? []
    }
    
    func saveChatMessage(_ message: ChatMessage, fileId: String) async throws {
        recordCall("saveChatMessage")
        
        if let error = mockError {
            throw error
        }
        
        var messages = storedMessages[fileId] ?? []
        messages.append(message)
        storedMessages[fileId] = messages
    }
    
    // MARK: - Folder Methods
    
    func getFolders() async throws -> [Folder] {
        recordCall("getFolders")
        
        if let error = mockError {
            throw error
        }
        
        return storedFolders
    }
    
    func createFolder(_ folder: Folder) async throws {
        recordCall("createFolder")
        
        if let error = mockError {
            throw error
        }
        
        storedFolders.append(folder)
    }
    
    // MARK: - Tag Methods
    
    func getTags() async throws -> [Tag] {
        recordCall("getTags")
        
        if let error = mockError {
            throw error
        }
        
        return storedTags
    }
    
    // MARK: - Reading Progress
    
    var storedReadingProgress: [String: (page: Int, scrollPosition: CGPoint, scale: CGFloat)] = [:]
    
    func getReadingProgress(fileId: String) async throws -> (page: Int, scrollPosition: CGPoint, scale: CGFloat)? {
        recordCall("getReadingProgress")
        
        if let error = mockError {
            throw error
        }
        
        return storedReadingProgress[fileId]
    }
    
    func saveReadingProgress(fileId: String, page: Int, scrollPosition: CGPoint, scale: CGFloat) async throws {
        recordCall("saveReadingProgress")
        
        if let error = mockError {
            throw error
        }
        
        storedReadingProgress[fileId] = (page, scrollPosition, scale)
    }
    
    // MARK: - Helper Methods
    
    func reset() {
        currentUser = nil
        mockUser = nil
        mockError = nil
        isLoading = false
        storedAnnotations.removeAll()
        storedMessages.removeAll()
        storedFiles.removeAll()
        storedFolders.removeAll()
        storedTags.removeAll()
        storedReadingProgress.removeAll()
        callCount.removeAll()
    }
    
    private func recordCall(_ method: String) {
        callCount[method, default: 0] += 1
    }
}

// MARK: - Test Assertions

extension MockSupabaseService {
    
    func assertCalled(_ method: String, times: Int = 1) {
        let count = callCount[method] ?? 0
        assert(count == times, "Expected \(method) to be called \(times) times, but was called \(count) times")
    }
    
    func assertNotCalled(_ method: String) {
        let count = callCount[method] ?? 0
        assert(count == 0, "Expected \(method) not to be called, but was called \(count) times")
    }
}
