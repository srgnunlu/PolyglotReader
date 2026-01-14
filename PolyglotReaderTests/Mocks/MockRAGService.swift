import Foundation
import Combine
@testable import PolyglotReader

/// Mock implementation of RAGService for testing
@MainActor
final class MockRAGService: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isIndexing = false
    @Published var indexingFileId: UUID?
    @Published var indexingProgress: Float = 0
    @Published var currentOperation: String = ""
    
    // MARK: - Mock Data
    
    var mockSearchResults: [DocumentChunk] = []
    var mockScoredChunks: [ScoredChunk] = []
    var mockError: AppError?
    var indexedDocuments: Set<UUID> = []
    
    // MARK: - Call Tracking
    
    var callCount: [String: Int] = [:]
    var lastIndexedText: String?
    var lastSearchQuery: String?
    
    // MARK: - Indexing Methods
    
    func indexDocument(text: String, fileId: UUID) async throws {
        recordCall("indexDocument")
        lastIndexedText = text
        
        if let error = mockError {
            throw error
        }
        
        // Simulate indexing progress
        isIndexing = true
        indexingFileId = fileId
        
        for progress in stride(from: Float(0), through: 1.0, by: 0.2) {
            indexingProgress = progress
            try await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        }
        
        indexedDocuments.insert(fileId)
        isIndexing = false
        indexingProgress = 1.0
    }
    
    func indexDocument(text: String, fileId: UUID, imageMetadata: [PDFImageMetadata]) async throws {
        recordCall("indexDocumentWithImages")
        try await indexDocument(text: text, fileId: fileId)
    }
    
    func isDocumentIndexed(fileId: UUID) async -> Bool {
        recordCall("isDocumentIndexed")
        return indexedDocuments.contains(fileId)
    }
    
    // MARK: - Search Methods
    
    func hybridSearch(query: String, fileId: UUID, topK: Int? = nil) async throws -> [ScoredChunk] {
        recordCall("hybridSearch")
        lastSearchQuery = query
        
        if let error = mockError {
            throw error
        }
        
        return mockScoredChunks
    }
    
    func searchRelevantChunks(query: String, fileId: UUID, topK: Int = 5) async throws -> [DocumentChunk] {
        recordCall("searchRelevantChunks")
        lastSearchQuery = query
        
        if let error = mockError {
            throw error
        }
        
        return Array(mockSearchResults.prefix(topK))
    }
    
    // MARK: - RAG Pipeline
    
    func performRAGQuery(
        query: String,
        fileId: UUID,
        enableRerank: Bool? = nil,
        enableQueryExpansion: Bool? = nil
    ) async throws -> (context: String, chunks: [DocumentChunk]) {
        recordCall("performRAGQuery")
        lastSearchQuery = query
        
        if let error = mockError {
            throw error
        }
        
        let chunks = mockSearchResults
        let context = chunks.map { $0.content }.joined(separator: "\n\n")
        return (context, chunks)
    }
    
    // MARK: - Helper Methods
    
    func reset() {
        isIndexing = false
        indexingFileId = nil
        indexingProgress = 0
        currentOperation = ""
        mockSearchResults.removeAll()
        mockScoredChunks.removeAll()
        mockError = nil
        indexedDocuments.removeAll()
        callCount.removeAll()
        lastIndexedText = nil
        lastSearchQuery = nil
    }
    
    private func recordCall(_ method: String) {
        callCount[method, default: 0] += 1
    }
}

// MARK: - Test Data Helpers

extension MockRAGService {
    
    static func makeMockChunk(
        id: UUID = UUID(),
        fileId: UUID = UUID(),
        content: String = "Sample chunk content for testing",
        pageNumber: Int = 1,
        chunkIndex: Int = 0
    ) -> DocumentChunk {
        DocumentChunk(
            id: id,
            fileId: fileId,
            chunkIndex: chunkIndex,
            content: content,
            pageNumber: pageNumber,
            sectionTitle: nil,
            contentType: .text,
            containsTable: false,
            containsList: false,
            imageReferences: []
        )
    }
    
    static func makeMockScoredChunk(
        chunk: DocumentChunk? = nil,
        vectorScore: Float = 0.85,
        bm25Score: Float = 0.75,
        rrfScore: Float = 0.80
    ) -> ScoredChunk {
        ScoredChunk(
            chunk: chunk ?? makeMockChunk(),
            vectorScore: vectorScore,
            bm25Score: bm25Score,
            rrfScore: rrfScore,
            rerankScore: nil
        )
    }
}
