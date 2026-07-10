import SwiftUI

// MARK: - Onboarding Container
/// First-launch introduction: three swipeable pages that end in AuthView.
/// Shown once — `hasSeenOnboarding` gates it from ContentView.
struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var currentPage = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pageCount = 3

    var body: some View {
        ZStack {
            AnimatedMeshBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                skipBar

                TabView(selection: $currentPage) {
                    OnboardingReadPage(isActive: currentPage == 0)
                        .tag(0)
                    OnboardingTranslatePage(isActive: currentPage == 1)
                        .tag(1)
                    OnboardingAIPage(isActive: currentPage == 2)
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageIndicator
                    .padding(.bottom, DSSpacing.lg)

                continueButton
                    .padding(.horizontal, DSSpacing.lg)
                    .padding(.bottom, DSSpacing.xl)
            }
        }
        .dsHaptic(.selection, trigger: currentPage)
    }

    // MARK: - Skip
    private var skipBar: some View {
        HStack {
            Spacer()
            if currentPage < pageCount - 1 {
                Button {
                    finish()
                } label: {
                    Text("onboarding.skip".localized)
                        .font(DSFont.cardTitle)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, DSSpacing.md)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityIdentifier("onboarding_skip_button")
            }
        }
        .padding(.horizontal, DSSpacing.xs)
        .frame(height: 44)
        .dsAnimation(DSMotion.smooth, value: currentPage)
    }

    // MARK: - Page Dots
    private var pageIndicator: some View {
        HStack(spacing: DSSpacing.xs) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? DSColor.brand : Color.secondary.opacity(0.3))
                    .frame(width: index == currentPage ? 24 : 8, height: 8)
            }
        }
        .dsAnimation(DSMotion.snappy, value: currentPage)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("onboarding.accessibility.page".localized(with: currentPage + 1, pageCount))
    }

    // MARK: - Continue / Start
    private var isLastPage: Bool { currentPage == pageCount - 1 }

    private var continueButton: some View {
        Button {
            if isLastPage {
                finish()
            } else {
                withAnimation(DSMotion.resolved(DSMotion.smooth, reduceMotion: reduceMotion)) {
                    currentPage += 1
                }
            }
        } label: {
            Text((isLastPage ? "onboarding.start" : "onboarding.continue").localized)
                .font(DSFont.cardTitle)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background {
                    Capsule().fill(DSColor.brandGradient)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .dsShadow(.card, tint: DSColor.brand)
        .accessibilityIdentifier("onboarding_continue_button")
    }

    private func finish() {
        hasSeenOnboarding = true
    }
}

#Preview {
    OnboardingView()
}
