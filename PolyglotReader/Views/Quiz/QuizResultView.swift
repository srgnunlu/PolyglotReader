import SwiftUI

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
