import SwiftUI

// MARK: - Review View
struct QuizReviewView: View {
    @ObservedObject var viewModel: QuizViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(viewModel.questions.enumerated()), id: \.offset) { index, question in
                        ReviewQuestionCard(
                            number: index + 1,
                            question: question,
                            userAnswer: viewModel.userAnswers[index]
                        )
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("quiz.review.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.close".localized) { dismiss() }
                        .accessibilityIdentifier("close_review_button")
                }
            }
        }
    }
}

// MARK: - Review Question Card
struct ReviewQuestionCard: View {
    let number: Int
    let question: QuizQuestion
    let userAnswer: Int?

    private var isCorrect: Bool {
        userAnswer == question.correctAnswerIndex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isCorrect ? .green : .red)

                Text("\(number). \(question.question)")
                    .font(.subheadline.weight(.semibold))
            }

            VStack(spacing: 8) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { optionIndex, option in
                    reviewOption(optionIndex: optionIndex, option: option)
                }
            }

            if let explanation = question.explanation, !explanation.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("quiz.explanation".localized, systemImage: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(DSColor.brand)
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func reviewOption(optionIndex: Int, option: String) -> some View {
        let isAnswer = optionIndex == question.correctAnswerIndex
        let isUserWrong = optionIndex == userAnswer && !isCorrect

        HStack(spacing: 8) {
            Image(systemName: isAnswer ? "checkmark" : (isUserWrong ? "xmark" : "circle"))
                .font(.caption2)
                .foregroundStyle(isAnswer ? .green : (isUserWrong ? .red : .secondary))
                .frame(width: 16)

            Text(option)
                .font(.caption)
                .foregroundStyle(isAnswer ? .green : (isUserWrong ? .red : .primary))

            Spacer()

            if isUserWrong {
                Text("quiz.review.your_answer".localized)
                    .font(.caption2)
                    .foregroundStyle(.red)
            } else if isAnswer {
                Text("quiz.review.correct_answer".localized)
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            (isAnswer ? Color.green.opacity(0.1) : (isUserWrong ? Color.red.opacity(0.1) : Color.clear))
        )
        .cornerRadius(8)
    }
}
