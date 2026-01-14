import Foundation
import Combine
@testable import PolyglotReader

/// Mock implementation of GeminiService for testing
@MainActor
final class MockGeminiService: ObservableObject {
    
    // MARK: - Published State (mimics real service)
    
    @Published var isProcessing = false
    @Published var lastError: GeminiError?
    
    // MARK: - Mock Configuration
    
    var mockResponse: String = "Mock AI response"
    var mockError: GeminiError?
    var responseDelay: TimeInterval = 0
    var callCount: [String: Int] = [:]
    var lastMessages: [String] = []
    
    // MARK: - Chat Methods
    
    func sendMessage(_ message: String) async throws -> String {
        recordCall("sendMessage")
        lastMessages.append(message)
        
        isProcessing = true
        defer { isProcessing = false }
        
        if responseDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(responseDelay * 1_000_000_000))
        }
        
        if let error = mockError {
            lastError = error
            throw mapError(error)
        }
        
        return mockResponse
    }
    
    func sendMessageWithContext(_ message: String, context: String) async throws -> String {
        recordCall("sendMessageWithContext")
        lastMessages.append(message)
        
        isProcessing = true
        defer { isProcessing = false }
        
        if responseDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(responseDelay * 1_000_000_000))
        }
        
        if let error = mockError {
            lastError = error
            throw mapError(error)
        }
        
        return mockResponse
    }
    
    func sendMessageStream(_ message: String) async throws -> AsyncThrowingStream<String, Error> {
        recordCall("sendMessageStream")
        lastMessages.append(message)
        
        return AsyncThrowingStream { continuation in
            Task {
                if let error = self.mockError {
                    continuation.finish(throwing: self.mapError(error))
                    return
                }
                
                // Simulate streaming by splitting response into words
                let words = self.mockResponse.split(separator: " ")
                for word in words {
                    continuation.yield(String(word) + " ")
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                continuation.finish()
            }
        }
    }
    
    // MARK: - Analysis Methods
    
    func generateSmartNote(_ text: String) async throws -> String {
        recordCall("generateSmartNote")
        
        if let error = mockError {
            throw mapError(error)
        }
        
        return "Smart note for: \(text.prefix(50))..."
    }
    
    func generateDocumentSummary(_ text: String) async throws -> String {
        recordCall("generateDocumentSummary")
        
        if let error = mockError {
            throw mapError(error)
        }
        
        return "Summary of document with \(text.count) characters"
    }
    
    func suggestTags(_ text: String, existingTags: [String]) async throws -> [String] {
        recordCall("suggestTags")
        
        if let error = mockError {
            throw mapError(error)
        }
        
        return ["MockTag1", "MockTag2"]
    }
    
    // MARK: - Image Methods
    
    func askAboutImage(_ imageData: Data, question: String) async throws -> String {
        recordCall("askAboutImage")
        
        if let error = mockError {
            throw mapError(error)
        }
        
        return "Image analysis result for: \(question)"
    }
    
    func generateImageCaption(_ imageData: Data, context: String? = nil) async throws -> String {
        recordCall("generateImageCaption")
        
        if let error = mockError {
            throw mapError(error)
        }
        
        return "Caption for image (\(imageData.count) bytes)"
    }
    
    // MARK: - Helper Methods
    
    func startNewChat() {
        recordCall("startNewChat")
        lastMessages.removeAll()
    }
    
    func reset() {
        mockResponse = "Mock AI response"
        mockError = nil
        responseDelay = 0
        callCount.removeAll()
        lastMessages.removeAll()
        isProcessing = false
        lastError = nil
    }
    
    private func recordCall(_ method: String) {
        callCount[method, default: 0] += 1
    }
    
    private func mapError(_ error: GeminiError) -> AppError {
        switch error {
        case .noResponse:
            return .ai(reason: .noResponse)
        case .rateLimitExceeded:
            return .ai(reason: .rateLimited)
        case .quotaExhausted:
            return .ai(reason: .quotaExceeded)
        case .networkUnavailable:
            return .ai(reason: .unavailable)
        default:
            return .ai(reason: .noResponse)
        }
    }
}

// MARK: - Test Assertions

extension MockGeminiService {
    
    func assertCalled(_ method: String, times: Int = 1, file: StaticString = #file, line: UInt = #line) {
        let count = callCount[method] ?? 0
        assert(count == times, "Expected \(method) to be called \(times) times, but was called \(count) times")
    }
    
    func assertNotCalled(_ method: String, file: StaticString = #file, line: UInt = #line) {
        let count = callCount[method] ?? 0
        assert(count == 0, "Expected \(method) not to be called, but was called \(count) times")
    }
}
