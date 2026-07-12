import Foundation
import Combine
import GoogleGenerativeAI
import Network

// MARK: - Gemini Service Facade
@MainActor
class GeminiService: ObservableObject {
    static let shared = GeminiService()

    // Sub-services
    private let chatService = GeminiChatService()
    private let analysisService = GeminiAnalysisService()
    private let ragService = GeminiRAGService()

    // State
    @Published var isProcessing = false
    @Published var lastError: GeminiError?

    // Type Aliases for readability and backward compatibility
    typealias RerankResult = GeminiRAGService.RerankResult
    typealias ExpandedQuery = GeminiRAGService.ExpandedQuery

    // Shared Types
    struct AITagResult: Decodable {
        let tags: [String]
        let category: String
    }

    private init() {
        // Initialize logging or monitoring if needed
        Task {
            // Check network initially
            if !GeminiNetworkMonitor.shared.isConnected {
                logWarning("GeminiService", "İnternet bağlantısı yok (Başlangıç)")
            }
        }
    }

    // MARK: - Translation

    func translateText(_ text: String, context: String? = nil) async throws -> TranslationResult {
        try await executeServiceCall {
            try await analysisService.translateText(text, context: context)
        }
    }

    /// Depth layer of the quick-translation popup: contextual translation + alternatives.
    func translateTextDetailed(_ text: String, context: String? = nil) async throws -> DetailedTranslationResult {
        try await executeServiceCall {
            try await analysisService.translateTextDetailed(text, context: context)
        }
    }

    // MARK: - Smart Note

    func generateSmartNote(_ text: String) async throws -> String {
        try await executeServiceCall {
            try await analysisService.generateSmartNote(text)
        }
    }

    // MARK: - Document Summary

    func generateDocumentSummary(_ text: String) async throws -> String {
        try await executeServiceCall {
            try await analysisService.generateDocumentSummary(text)
        }
    }

    // MARK: - Tags

    func generateTags(_ text: String, existingTags: [String] = []) async throws -> AITagResult {
        try await executeServiceCall {
            try await analysisService.generateTags(text, existingTags: existingTags)
        }
    }

    // MARK: - Quiz

    func generateQuiz(context: String) async throws -> [QuizQuestion] {
        try await executeServiceCall {
            try await analysisService.generateQuiz(context: context)
        }
    }

    // MARK: - Chat Session

    func initChatSession(fileId: String, pdfContent: String? = nil) {
        chatService.initChatSession(fileId: fileId, pdfContent: pdfContent)
    }

    func resetChatSession(fileId: String) {
        chatService.resetChatSession(fileId: fileId)
    }

    func seedPersistedChatHistory(fileId: String, turns: [(role: String, text: String)]) {
        chatService.seedPersistedHistory(fileId: fileId, turns: turns)
    }

    func sendMessage(_ message: String) async throws -> String {
        try await executeServiceCall {
            try await chatService.sendMessage(message)
        }
    }

    func sendMessageWithContext(_ message: String, context: String, fileId: String) async throws -> String {
        try await executeServiceCall {
            try await chatService.sendMessageWithContext(message, context: context, fileId: fileId)
        }
    }

    func sendMessageStream(_ message: String, fileId: String) async throws -> AsyncThrowingStream<String, Error> {
        isProcessing = true
        lastError = nil

        let stream = chatService.sendMessageStream(message, fileId: fileId)
        return wrapStream(stream)
    }

    func sendMessageStreamWithContext(
        _ message: String,
        context: String,
        fileId: String
    ) async throws -> AsyncThrowingStream<String, Error> {
        isProcessing = true
        lastError = nil

        let stream = chatService.sendMessageStreamWithContext(message, context: context, fileId: fileId)
        return wrapStream(stream)
    }

    func sendLibraryMessageStream(
        _ message: String,
        context: String
    ) -> AsyncThrowingStream<String, Error> {
        isProcessing = true
        lastError = nil

        let stream = chatService.sendLibraryMessageStream(message, context: context)
        return wrapStream(stream)
    }

    func resetLibraryChatSession() {
        chatService.resetLibrarySession()
    }

    /// Re-emits a chat stream while mapping failures to AppError and keeping
    /// `isProcessing` accurate. Consumer cancellation is forwarded to the
    /// underlying stream so the network request is torn down promptly.
    private func wrapStream(_ stream: AsyncThrowingStream<String, Error>) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                    self.isProcessing = false
                } catch {
                    let appError = self.handleGeminiFailure(error)
                    continuation.finish(throwing: appError)
                    self.isProcessing = false
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Image Analysis

    func analyzeImage(_ imageData: Data, prompt: String? = nil) async throws -> String {
        try await executeServiceCall {
            try await analysisService.analyzeImage(imageData, prompt: prompt)
        }
    }

    func askAboutImage(_ imageData: Data, question: String, fileId: String) async throws -> String {
        try await executeServiceCall {
            try await chatService.askAboutImage(imageData, question: question, fileId: fileId)
        }
    }

    func generateImageCaption(_ imageData: Data, context: String? = nil) async throws -> String {
        try await executeServiceCall {
            try await analysisService.generateImageCaption(imageData, context: context)
        }
    }

    func batchAnalyzeImages(_ requests: [ImageAnalysisRequest]) async -> [ImageAnalysisResult] {
        // No throw, so just call
        await analysisService.batchAnalyzeImages(requests)
    }

    func askWithPageImages(
        _ question: String,
        images: [(data: Data, caption: String?)],
        pageNumber: Int,
        fileId: String
    ) async throws -> String {
        try await executeServiceCall {
            try await chatService.askWithPageImages(question, images: images, pageNumber: pageNumber, fileId: fileId)
        }
    }

    // MARK: - RAG / Embedding

    func rerankChunks(query: String, chunks: String) async throws -> [RerankResult] {
        try await executeServiceCall {
            try await ragService.rerankChunks(query: query, chunks: chunks)
        }
    }

    func expandQuery(_ query: String, documentContext: String? = nil) async throws -> ExpandedQuery {
        try await executeServiceCall {
            try await ragService.expandQuery(query, documentContext: documentContext)
        }
    }

    func translateQueryForSearch(_ query: String) async throws -> String {
        try await executeServiceCall {
            try await ragService.translateQueryForSearch(query)
        }
    }

    // MARK: - Helper
    private func executeServiceCall<T>(_ operation: () async throws -> T) async throws -> T {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        do {
            return try await operation()
        } catch {
            let appError = handleGeminiFailure(error)
            throw appError
        }
    }

    private func handleGeminiFailure(_ error: Error) -> AppError {
        updateLastError(from: error)
        return ErrorHandlingService.mapToAppError(error)
    }

    private func updateLastError(from error: Error) {
        if let geminiError = error as? GeminiError {
            lastError = geminiError
            return
        }

        if let appError = error as? AppError {
            if case .ai(let reason, _) = appError {
                lastError = mapAIReasonToGeminiError(reason)
                return
            }
            if case .network = appError {
                lastError = .networkUnavailable
                return
            }
        }

        lastError = .noResponse
    }

    private func mapAIReasonToGeminiError(_ reason: AppError.AIReason) -> GeminiError {
        switch reason {
        case .noResponse:
            return .noResponse
        case .parseFailed:
            return .parseError
        case .rateLimited:
            return .rateLimitExceeded
        case .quotaExceeded:
            return .quotaExhausted
        case .unavailable:
            return .networkUnavailable
        }
    }
}
