import Foundation
import Combine

// MARK: - Quiz ViewModel
@MainActor
class QuizViewModel: ObservableObject {
    @Published var questions: [QuizQuestion] = []
    @Published var currentQuestionIndex = 0
    @Published var score = 0
    @Published var selectedAnswer: Int?
    @Published var isAnswered = false
    @Published var showResult = false
    @Published var isLoading = true
    @Published var errorMessage: String?

    private let geminiService = GeminiService.shared
    let textContext: String

    init(textContext: String) {
        self.textContext = textContext
    }

    var currentQuestion: QuizQuestion? {
        guard currentQuestionIndex < questions.count else { return nil }
        return questions[currentQuestionIndex]
    }

    var progress: String {
        "\(currentQuestionIndex + 1) / \(questions.count)"
    }

    var scorePercentage: Int {
        guard !questions.isEmpty else { return 0 }
        return Int((Double(score) / Double(questions.count)) * 100)
    }

    // MARK: - Generate Quiz

    func generateQuiz() async {
        isLoading = true
        defer { isLoading = false }

        do {
            questions = try await geminiService.generateQuiz(context: textContext)
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            errorMessage = appError.localizedDescription
            ErrorHandlingService.shared.handle(
                appError,
                context: .init(
                    source: "QuizViewModel",
                    operation: "GenerateQuiz"
                ) { [weak self] in
                    Task { await self?.generateQuiz() }
                    return
                }
            )
        }
    }

    // MARK: - Answer Question

    func selectAnswer(_ index: Int) {
        guard !isAnswered, let question = currentQuestion else { return }

        selectedAnswer = index
        isAnswered = true

        if index == question.correctAnswerIndex {
            score += 1
        }
    }

    func nextQuestion() {
        if currentQuestionIndex < questions.count - 1 {
            currentQuestionIndex += 1
            selectedAnswer = nil
            isAnswered = false
        } else {
            showResult = true
        }
    }

    func reset() {
        currentQuestionIndex = 0
        score = 0
        selectedAnswer = nil
        isAnswered = false
        showResult = false
    }
}
