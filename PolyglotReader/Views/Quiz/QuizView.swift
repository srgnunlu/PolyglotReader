import SwiftUI

struct QuizView: View {
    @StateObject private var viewModel: QuizViewModel
    @Environment(\.dismiss) private var dismiss
    
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
                    ErrorQuizView(onClose: { dismiss() })
                } else if viewModel.showResult {
                    QuizResultView(
                        score: viewModel.score,
                        total: viewModel.questions.count,
                        percentage: viewModel.scorePercentage,
                        onClose: { dismiss() }
                    )
                } else if let question = viewModel.currentQuestion {
                    QuestionView(
                        viewModel: viewModel,
                        question: question
                    )
                }
            }
            .navigationTitle("AI Quiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
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
    
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "brain")
                    .font(.system(size: 40))
                    .foregroundStyle(.indigo)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 1).repeatForever(), value: isAnimating)
            }
            
            VStack(spacing: 8) {
                Text("Quiz Oluşturuluyor...")
                    .font(.headline)
                
                Text("Doküman analiz ediliyor ve sorular hazırlanıyor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .onAppear { isAnimating = true }
    }
}

// MARK: - Error View
struct ErrorQuizView: View {
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundStyle(.red)
            
            Text("Quiz oluşturulamadı")
                .font(.headline)
            
            Button("Kapat", action: onClose)
                .buttonStyle(.bordered)
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
                Text("Soru \(viewModel.currentQuestionIndex + 1) / \(viewModel.questions.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("Puan: \(viewModel.score)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            
            // Question
            Text(question.question)
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .padding()
            
            // Options
            VStack(spacing: 12) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    OptionButton(
                        text: option,
                        index: index,
                        isSelected: viewModel.selectedAnswer == index,
                        isCorrect: index == question.correctAnswerIndex,
                        isAnswered: viewModel.isAnswered,
                        action: { viewModel.selectAnswer(index) }
                    )
                }
            }
            .padding(.horizontal)
            
            // Explanation
            if viewModel.isAnswered, let explanation = question.explanation {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Açıklama", systemImage: "lightbulb.fill")
                        .font(.caption)
                        .foregroundStyle(.indigo)
                    
                    Text(explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.indigo.opacity(0.1))
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
                        Text(viewModel.currentQuestionIndex == viewModel.questions.count - 1 ? "Bitir" : "Sonraki")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.indigo)
                    .cornerRadius(16)
                }
                .padding()
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
    
    var backgroundColor: Color {
        guard isAnswered else {
            return isSelected ? Color.indigo.opacity(0.1) : Color(.secondarySystemBackground)
        }
        
        if isCorrect {
            return Color.green.opacity(0.15)
        } else if isSelected {
            return Color.red.opacity(0.15)
        } else {
            return Color(.secondarySystemBackground).opacity(0.5)
        }
    }
    
    var borderColor: Color {
        guard isAnswered else {
            return isSelected ? Color.indigo : Color.clear
        }
        
        if isCorrect {
            return Color.green
        } else if isSelected {
            return Color.red
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
                            .foregroundStyle(.green)
                    } else if isSelected {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .foregroundStyle(.primary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 2)
            )
        }
        .disabled(isAnswered)
    }
}

// MARK: - Result View
struct QuizResultView: View {
    let score: Int
    let total: Int
    let percentage: Int
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                    .frame(width: 150, height: 150)
                
                Circle()
                    .trim(from: 0, to: CGFloat(percentage) / 100)
                    .stroke(Color.indigo, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .frame(width: 150, height: 150)
                    .rotationEffect(.degrees(-90))
                
                Text("%\(percentage)")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.indigo)
            }
            
            VStack(spacing: 8) {
                Text("Quiz Tamamlandı!")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("\(total) sorudan \(score) tanesini doğru cevapladınız.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: onClose) {
                Text("Kapat")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.indigo)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }
}

#Preview {
    QuizView(textContext: "Sample text for quiz generation")
}
