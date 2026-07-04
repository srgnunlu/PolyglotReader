import XCTest
import GoogleGenerativeAI
@testable import PolyglotReader

/// Unit tests for GeminiChatService history budgeting (token-capped trimming).
@MainActor
final class GeminiChatServiceHistoryTests: XCTestCase {
    // MARK: - Helpers

    /// Builds a user/model turn pair whose texts carry a unique marker.
    private func makeTurnPair(marker: String, wordsPerMessage: Int) -> [ModelContent] {
        let text = Array(repeating: marker, count: wordsPerMessage).joined(separator: " ")
        return [
            ModelContent(role: "user", parts: [.text(text)]),
            ModelContent(role: "model", parts: [.text(text)])
        ]
    }

    private func firstText(of content: ModelContent) -> String? {
        for part in content.parts {
            if case .text(let text) = part {
                return text
            }
        }
        return nil
    }

    // MARK: - Token Estimation

    func testEstimatedTokensUsesWordCountMultiplier() {
        let content = ModelContent(role: "user", parts: [.text("bir iki üç dört")])
        let expected = Int(Float(4) * RAGConfig.tokenMultiplier)
        XCTAssertEqual(GeminiChatService.estimatedTokens(of: content), expected)
    }

    // MARK: - Trimming

    func testShortHistoryIsNotTrimmed() {
        let history = makeTurnPair(marker: "context", wordsPerMessage: 10)
            + makeTurnPair(marker: "turn1", wordsPerMessage: 10)

        let trimmed = GeminiChatService.trimmedHistory(history, maxTokens: 5)

        // Preserved pair + latest pair is the minimum, even over budget.
        XCTAssertEqual(trimmed.count, history.count)
    }

    func testHistoryUnderBudgetIsUntouched() {
        let history = makeTurnPair(marker: "context", wordsPerMessage: 10)
            + makeTurnPair(marker: "turn1", wordsPerMessage: 10)
            + makeTurnPair(marker: "turn2", wordsPerMessage: 10)

        let trimmed = GeminiChatService.trimmedHistory(history, maxTokens: 100_000)

        XCTAssertEqual(trimmed.count, history.count)
    }

    func testLongHistoryDropsOldestPairsAndPreservesContextPair() {
        var history = makeTurnPair(marker: "context", wordsPerMessage: 10)
        for index in 1...5 {
            history += makeTurnPair(marker: "turn\(index)", wordsPerMessage: 1_000)
        }

        // Budget that fits the context pair plus roughly two turn pairs.
        let trimmed = GeminiChatService.trimmedHistory(history, maxTokens: 6_000)

        XCTAssertLessThan(trimmed.count, history.count, "Over-budget history should be trimmed")
        XCTAssertEqual(
            firstText(of: trimmed[0])?.hasPrefix("context"),
            true,
            "Initial context user message must survive trimming"
        )
        XCTAssertEqual(
            firstText(of: trimmed[1])?.hasPrefix("context"),
            true,
            "Initial context model message must survive trimming"
        )
        XCTAssertEqual(
            firstText(of: trimmed[trimmed.count - 1])?.hasPrefix("turn5"),
            true,
            "Most recent turn must survive trimming"
        )
        // The oldest conversational turn is the first to go.
        let remainingTexts = trimmed.compactMap { firstText(of: $0) }
        XCTAssertFalse(
            remainingTexts.contains { $0.hasPrefix("turn1") },
            "Oldest turn pair should be dropped first"
        )
    }

    func testTrimmingKeepsAlternatingRoles() {
        var history = makeTurnPair(marker: "context", wordsPerMessage: 10)
        for index in 1...6 {
            history += makeTurnPair(marker: "turn\(index)", wordsPerMessage: 800)
        }

        let trimmed = GeminiChatService.trimmedHistory(history, maxTokens: 4_000)

        XCTAssertEqual(trimmed.count % 2, 0, "Pairs must be removed whole")
        for (index, content) in trimmed.enumerated() {
            let expectedRole = index % 2 == 0 ? "user" : "model"
            XCTAssertEqual(content.role, expectedRole, "Role alternation must be preserved")
        }
    }

    func testTrimmingAlwaysKeepsPreservedAndLatestPair() {
        var history = makeTurnPair(marker: "context", wordsPerMessage: 5_000)
        history += makeTurnPair(marker: "turn1", wordsPerMessage: 5_000)
        history += makeTurnPair(marker: "turn2", wordsPerMessage: 5_000)

        // Budget far below even a single pair: trimming must still stop at
        // context pair + most recent pair.
        let trimmed = GeminiChatService.trimmedHistory(history, maxTokens: 10)

        XCTAssertEqual(trimmed.count, 4)
        XCTAssertEqual(firstText(of: trimmed[0])?.hasPrefix("context"), true)
        XCTAssertEqual(firstText(of: trimmed[3])?.hasPrefix("turn2"), true)
    }
}
