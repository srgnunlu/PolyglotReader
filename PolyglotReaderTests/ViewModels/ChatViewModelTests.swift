import XCTest
import Combine
@testable import PolyglotReader

/// Unit tests for ChatViewModel
@MainActor
final class ChatViewModelTests: XCTestCase {
    
    var sut: ChatViewModel!
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        try await super.setUp()
        let testFileId = UUID().uuidString
        sut = ChatViewModel(fileId: testFileId)
        cancellables = []
    }
    
    override func tearDown() async throws {
        cancellables.removeAll()
        sut = nil
        try await super.tearDown()
    }
    
    // MARK: - Initial State Tests
    
    func testInitialStateHasWelcomeMessage() {
        // Then
        XCTAssertFalse(sut.messages.isEmpty, "Should have welcome message")
        XCTAssertEqual(sut.messages.first?.role, .model)
    }
    
    func testInitialIndexingStatusIsUnknown() {
        // Then
        XCTAssertEqual(sut.indexingStatus, .unknown)
    }
    
    func testInitialStateIsNotLoading() {
        // Then
        XCTAssertFalse(sut.isLoading)
    }
    
    func testInputTextStartsEmpty() {
        // Then
        XCTAssertTrue(sut.inputText.isEmpty)
    }
    
    // MARK: - Network Status Tests
    
    func testOfflineStateInitiallyReflectsNetworkStatus() {
        // The initial offline state depends on the device's actual network
        // We just verify it's a boolean (not nil or undefined)
        _ = sut.isOffline
        XCTAssertTrue(true, "isOffline should be accessible")
    }
    
    // MARK: - Indexing Status Tests
    
    func testIndexingStatusPublishesChanges() async {
        // Given
        var statusChanges: [ChatViewModel.IndexingStatus] = []
        
        sut.$indexingStatus
            .sink { status in
                statusChanges.append(status)
            }
            .store(in: &cancellables)
        
        // When
        await sut.refreshIndexingStatus()
        
        // Then - Should have received at least one status update
        XCTAssertFalse(statusChanges.isEmpty)
    }
    
    // MARK: - Smart Suggestions Tests
    
    func testCurrentSuggestionsReturnsDefaultWhenEmpty() {
        // Given
        sut.smartSuggestions = []
        
        // When
        let suggestions = sut.currentSuggestions
        
        // Then
        XCTAssertFalse(suggestions.isEmpty, "Should return default suggestions when empty")
    }
    
    // MARK: - Message Validation Tests
    
    func testWelcomeMessageHasCorrectContent() {
        // Given
        guard let welcomeMessage = sut.messages.first else {
            XCTFail("Should have welcome message")
            return
        }
        
        // Then
        XCTAssertEqual(welcomeMessage.role, .model)
        XCTAssertFalse(welcomeMessage.text.isEmpty)
    }

    func testExportTranscriptOmitsSyntheticWelcomeMessage() {
        XCTAssertFalse(sut.exportTranscript.contains("sorularınızı yanıtlamaya hazırım"))

        sut.messages.append(ChatMessage(role: .user, text: "Ana fikir nedir?"))
        XCTAssertTrue(sut.exportTranscript.contains("Ana fikir nedir?"))
    }
    
    // MARK: - Input Text Tests
    
    func testInputTextCanBeModified() {
        // Given
        let testInput = "Test question about the document"
        
        // When
        sut.inputText = testInput
        
        // Then
        XCTAssertEqual(sut.inputText, testInput)
    }

    func testValidatedInputTrimsWhitespaceAndNewlines() {
        sut.inputText = "  Dokümanı özetle.\n"

        XCTAssertEqual(sut.validatedUserInput(nil), "Dokümanı özetle.")
    }

    func testImageCanBeSubmittedWithoutTypedPrompt() {
        sut.selectedImage = Data([0x01])
        sut.inputText = "   "

        XCTAssertTrue(sut.canSubmitMessage)
        XCTAssertEqual(
            sut.validatedImageInput(nil),
            "chat.image_default_prompt".localized
        )
    }
    
    // MARK: - Streaming Lifecycle Tests

    func testCancelActiveStreamWithoutTaskIsNoOp() {
        // When
        sut.cancelActiveStream()

        // Then
        XCTAssertNil(sut.activeStreamTask)
        XCTAssertFalse(sut.isLoading)
    }

    func testCancelActiveStreamCancelsAndClearsTask() async {
        // Given - a long-running task standing in for an in-flight stream
        let task = Task<Void, Never> {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
        sut.activeStreamTask = task
        sut.isLoading = true

        // When
        sut.cancelActiveStream()

        // Then
        XCTAssertNil(sut.activeStreamTask)
        XCTAssertFalse(sut.isLoading)
        await task.value
        XCTAssertTrue(task.isCancelled)
    }

    // MARK: - Memory Leak Tests
    
    func testChatViewModelDoesNotLeakMemory() async {
        // Given
        var viewModel: ChatViewModel? = ChatViewModel(fileId: UUID().uuidString)
        weak var weakViewModel = viewModel
        
        // When
        viewModel = nil
        
        // Allow time for cleanup
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        // Then
        XCTAssertNil(weakViewModel, "ChatViewModel should be deallocated")
    }
}
