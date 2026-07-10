import SwiftUI

struct QuizView: View {
    @StateObject private var viewModel: QuizViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingReview = false

    init(textContext: String) {
        _viewModel = StateObject(wrappedValue: QuizViewModel(textContext: textContext))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if viewModel.isLoading {
                    LoadingQuizView()
                } else if viewModel.questions.isEmpty {
                    ErrorQuizView(
                        onRetry: { Task { await viewModel.generateQuiz() } },
                        onClose: { dismiss() }
                    )
                } else if viewModel.showResult {
                    QuizResultView(
                        score: viewModel.score,
                        total: viewModel.questions.count,
                        percentage: viewModel.scorePercentage,
                        incorrectCount: viewModel.incorrectQuestionIndices.count,
                        onReview: { showingReview = true },
                        onRetry: { viewModel.reset() },
                        onClose: { dismiss() }
                    )
                    .transition(.opacity)
                } else if let question = viewModel.currentQuestion {
                    QuestionView(
                        viewModel: viewModel,
                        question: question
                    )
                    // Yeni soru kartı sağdan kayar, eski soru solarak çekilir.
                    .id(viewModel.currentQuestionIndex)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .dsAnimation(DSMotion.smooth, value: viewModel.currentQuestionIndex)
            .dsAnimation(DSMotion.smooth, value: viewModel.showResult)
            .navigationTitle("quiz.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingReview) {
                QuizReviewView(viewModel: viewModel)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("common.close".localized)
                    .accessibilityIdentifier("close_quiz_button")
                }
            }
        }
        .task {
            await viewModel.generateQuiz()
        }
    }
}

// MARK: - Loading View
struct LoadingQuizView: View {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(DSColor.brand.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "brain")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(DSColor.brand)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 1).repeatForever(),
                        value: isAnimating
                    )
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("quiz.loading.title".localized)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Text("quiz.preparing_questions".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("quiz.loading.title".localized)
        .onAppear { isAnimating = true }
    }
}

// MARK: - Error View
struct ErrorQuizView: View {
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(DSColor.danger)
                .accessibilityHidden(true)

            Text("quiz.error.title".localized)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 12) {
                Button(action: onRetry) {
                    Label("quiz.retry".localized, systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("retry_quiz_button")

                Button("common.close".localized, action: onClose)
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("close_error_button")
            }
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - Question View
struct QuestionView: View {
    @ObservedObject var viewModel: QuizViewModel
    let question: QuizQuestion

    var body: some View {
        VStack(spacing: 24) {
            // Progress
            HStack {
                Text("quiz.question_progress".localized(with: viewModel.currentQuestionIndex + 1, viewModel.questions.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("quiz.score".localized(with: viewModel.score))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .accessibilityElement(children: .combine)

            // Question
            Text(question.question)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding()
                .accessibilityAddTraits(.isHeader)

            // Options
            VStack(spacing: 12) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    OptionButton(
                        text: option,
                        index: index,
                        isSelected: viewModel.selectedAnswer == index,
                        isCorrect: index == question.correctAnswerIndex,
                        isAnswered: viewModel.isAnswered
                    ) { viewModel.selectAnswer(index) }
                }
            }
            .padding(.horizontal)

            // Explanation
            if viewModel.isAnswered, let explanation = question.explanation {
                VStack(alignment: .leading, spacing: 8) {
                    Label("quiz.explanation".localized, systemImage: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(DSColor.brand)

                    Text(explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DSColor.brand.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
            }

            Spacer()

            // Next Button
            if viewModel.isAnswered {
                Button {
                    viewModel.nextQuestion()
                } label: {
                    HStack {
                        Text(viewModel.currentQuestionIndex == viewModel.questions.count - 1
                             ? "common.finish".localized
                             : "common.next".localized)
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .frame(minHeight: 44)
                    .background(DSColor.brand)
                    .cornerRadius(16)
                }
                .buttonStyle(DSPressableButtonStyle())
                .padding()
                .accessibilityLabel(
                    viewModel.currentQuestionIndex == viewModel.questions.count - 1
                        ? "quiz.accessibility.finish".localized
                        : "quiz.accessibility.next".localized
                )
                .accessibilityIdentifier("next_question_button")
            }
        }
        .padding(.vertical)
    }
}

// MARK: - Option Button
struct OptionButton: View {
    let text: String
    let index: Int
    let isSelected: Bool
    let isCorrect: Bool
    let isAnswered: Bool
    let action: () -> Void

    /// Yanlış seçilen şık için tek seferlik sarsıntı sayacı.
    @State private var wrongShakes: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var backgroundColor: Color {
        guard isAnswered else {
            return isSelected ? DSColor.brand.opacity(0.1) : Color(.secondarySystemBackground)
        }

        if isCorrect {
            return DSColor.success.opacity(0.15)
        } else if isSelected {
            return DSColor.danger.opacity(0.15)
        } else {
            return Color(.secondarySystemBackground).opacity(0.5)
        }
    }

    var borderColor: Color {
        guard isAnswered else {
            return isSelected ? DSColor.brand : Color.clear
        }

        if isCorrect {
            return DSColor.success
        } else if isSelected {
            return DSColor.danger
        } else {
            return Color.clear
        }
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(.subheadline)
                    .multilineTextAlignment(.leading)

                Spacer()

                if isAnswered {
                    if isCorrect {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DSColor.success)
                    } else if isSelected {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DSColor.danger)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
            .background(backgroundColor)
            .foregroundStyle(.primary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 2)
            )
        }
        .disabled(isAnswered)
        // Doğru cevap bouncy bir vurguyla hafifçe büyür; yanlış seçim sarsılır.
        .scaleEffect(isAnswered && isCorrect ? 1.02 : 1.0)
        .dsAnimation(DSMotion.celebrate, value: isAnswered)
        .modifier(HorizontalShakeEffect(animatableData: wrongShakes))
        .dsHaptic(.success, trigger: isAnswered) { old, new in
            !old && new && isSelected && isCorrect
        }
        .dsHaptic(.error, trigger: isAnswered) { old, new in
            !old && new && isSelected && !isCorrect
        }
        .onChange(of: isAnswered) {
            guard isAnswered, isSelected, !isCorrect, !reduceMotion else { return }
            withAnimation(.linear(duration: 0.35)) {
                wrongShakes += 1
            }
        }
        .accessibilityLabel(text)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(
            isAnswered
                ? (isCorrect ? "quiz.accessibility.correct".localized : (isSelected ? "quiz.accessibility.incorrect".localized : ""))
                : ""
        )
        .accessibilityIdentifier("option_\(index)")
    }
}

// MARK: - Horizontal Shake Effect
/// Yanlış cevap sarsıntısı: animatableData her +1 arttığında 3 tam salınım.
private struct HorizontalShakeEffect: GeometryEffect {
    var amplitude: CGFloat = 7
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amplitude * sin(animatableData * .pi * 2 * shakesPerUnit)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

// MARK: - Result View
struct QuizResultView: View {
    let score: Int
    let total: Int
    let percentage: Int
    let incorrectCount: Int
    let onReview: () -> Void
    let onRetry: () -> Void
    let onClose: () -> Void

    /// KeyframeAnimator tetikleyicisi: görünür olunca koreografi bir kez oynar.
    @State private var revealed = false
    /// %80+ skorda tek seferlik konfeti — kazanılmış kutlama, ambient değil.
    @State private var celebrationFired = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var earnedCelebration: Bool { percentage >= 80 }

    var body: some View {
        VStack(spacing: 32) {
            scoreRing
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(percentage)%")

            VStack(spacing: 8) {
                Text("quiz.complete.title".localized)
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)

                Text("quiz.score_summary".localized(with: total, score))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                if incorrectCount > 0 {
                    Button(action: onReview) {
                        Label("quiz.review.button".localized, systemImage: "list.bullet.clipboard")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .frame(minHeight: 44)
                            .background(DSColor.brand)
                            .cornerRadius(16)
                    }
                    .accessibilityIdentifier("review_answers_button")
                }

                Button(action: onRetry) {
                    Label("quiz.retry".localized, systemImage: "arrow.clockwise")
                        .font(.headline)
                        .foregroundStyle(DSColor.brand)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .frame(minHeight: 44)
                        .background(DSColor.brand.opacity(0.12))
                        .cornerRadius(16)
                }
                .accessibilityIdentifier("retry_result_button")

                Button(action: onClose) {
                    Text("common.close".localized)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("close_result_button")
            }
            .padding(.horizontal, 40)
        }
        .padding()
        .overlay {
            if celebrationFired {
                ConfettiBurstView()
            }
        }
        .onAppear { runChoreography() }
    }

    // MARK: - Score Ring Choreography
    /// Tek koreografi değeri hem halkayı çizer hem sayacı saydırır:
    /// kısa bir bekleme → halka 0'dan skora dolar → (%80+) konfeti.
    private var scoreRing: some View {
        KeyframeAnimator(initialValue: 0.0, trigger: revealed) { progress in
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                    .frame(width: 150, height: 150)

                Circle()
                    .trim(from: 0, to: CGFloat(progress) * CGFloat(percentage) / 100)
                    .stroke(DSColor.brand, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(-90))

                Text("%\(Int(progress * Double(percentage)))")
                    .font(.largeTitle.bold())
                    .foregroundStyle(DSColor.brand)
                    .contentTransition(.numericText(value: progress * Double(percentage)))
            }
        } keyframes: { _ in
            KeyframeTrack {
                // Nefes payı: ekran otursun, sonra halka aksın.
                LinearKeyframe(0.0, duration: 0.25)
                CubicKeyframe(1.0, duration: 0.9)
            }
        }
    }

    private func runChoreography() {
        guard !revealed else { return }

        if reduceMotion {
            // Hareketsiz: koreografi yok, değerler dolu başlasın diye
            // trigger'ı hemen çeviriyoruz; KeyframeAnimator süreyi yine
            // işletir ama görsel fark minimum kalır. Konfeti hiç yok.
            revealed = true
            return
        }

        revealed = true

        // Konfeti + başarı haptic'i halka dolduktan hemen sonra (kazanılmış an).
        if earnedCelebration {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                celebrationFired = true
                DSHaptics.success()
            }
        }
    }
}

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

#Preview {
    QuizView(textContext: "Sample text for quiz generation")
}
