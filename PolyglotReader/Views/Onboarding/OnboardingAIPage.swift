import SwiftUI

// MARK: - Page 3: "Sor, sına, hatırla"
/// The AI trio — chat, quiz, notebook — introduced as one connected loop.
struct OnboardingAIPage: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var activeIndex = 0
    @State private var cycleTask: Task<Void, Never>?

    private struct Feature {
        let icon: String
        let titleKey: String
        let colors: [Color]
    }

    private let features: [Feature] = [
        Feature(
            icon: "bubble.left.and.bubble.right.fill",
            titleKey: "onboarding.page3.chat",
            colors: [DSColor.brand, DSColor.brandSecondary]
        ),
        Feature(
            icon: "graduationcap.fill",
            titleKey: "onboarding.page3.quiz",
            colors: [DSColor.brandSecondary, DSColor.aiAccent]
        ),
        Feature(
            icon: "bookmark.fill",
            titleKey: "onboarding.page3.notebook",
            colors: [DSColor.aiAccent, DSColor.brand]
        )
    ]

    var body: some View {
        VStack(spacing: DSSpacing.xl) {
            Spacer()

            HStack(spacing: DSSpacing.md) {
                ForEach(features.indices, id: \.self) { index in
                    featureTile(features[index], index: index)
                }
            }
            .accessibilityHidden(true)
            .onboardingParallax()

            VStack(spacing: DSSpacing.sm) {
                Text("onboarding.page3.title".localized)
                    .font(DSFont.displayTitle)
                Text("onboarding.page3.subtitle".localized)
                    .font(DSFont.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DSSpacing.xl)

            Spacer()
            Spacer()
        }
        .onAppear { startIfNeeded() }
        .onChange(of: isActive) { _ in startIfNeeded() }
        .onDisappear { cycleTask?.cancel() }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Tile
    private func featureTile(_ feature: Feature, index: Int) -> some View {
        let isSpotlit = activeIndex == index && !reduceMotion

        return VStack(spacing: DSSpacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: feature.colors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                Image(systemName: feature.icon)
                    .font(DSFont.screenTitle)
                    .foregroundStyle(.white)
            }
            .dsShadow(.card, tint: feature.colors[0])
            .scaleEffect(isSpotlit ? 1.08 : 1.0)

            Text(feature.titleKey.localized)
                .font(DSFont.caption)
                .foregroundStyle(isSpotlit ? .primary : .secondary)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 24)
        .dsAnimation(DSMotion.smooth.delay(Double(index) * 0.12), value: appeared)
        .dsAnimation(DSMotion.snappy, value: activeIndex)
    }

    // MARK: - Choreography
    private func startIfNeeded() {
        guard isActive else {
            cycleTask?.cancel()
            return
        }

        if reduceMotion {
            appeared = true
            return
        }

        withAnimation { appeared = true }

        // Spotlight wanders through the trio — suggests one connected flow.
        cycleTask?.cancel()
        cycleTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(DSMotion.snappy) {
                    activeIndex = (activeIndex + 1) % features.count
                }
            }
        }
    }
}

#Preview {
    OnboardingAIPage(isActive: true)
}
