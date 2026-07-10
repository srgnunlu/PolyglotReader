import SwiftUI

// MARK: - Page 2: "Seç, anında anla"
/// Live demo of the killer feature: a selection sweep over a real sentence,
/// then the ACTUAL translation popup chrome (not a mockup) springs in and
/// completes — Readlang-speed promise, shown not told.
struct OnboardingTranslatePage: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum DemoStep {
        case idle
        case selecting
        case popupLoading
        case popupTranslated
    }

    @State private var step: DemoStep = .idle
    @State private var selectionProgress: CGFloat = 0
    @State private var playedHaptics = false

    private var sampleText: String { "onboarding.page2.sample".localized }
    private var sampleTranslation: String { "onboarding.page2.sample_translation".localized }

    var body: some View {
        VStack(spacing: DSSpacing.xl) {
            Spacer()

            demoStage
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            VStack(spacing: DSSpacing.sm) {
                Text("onboarding.page2.title".localized)
                    .font(DSFont.displayTitle)
                Text("onboarding.page2.subtitle".localized)
                    .font(DSFont.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DSSpacing.xl)

            Spacer()
            Spacer()
        }
        .task(id: isActive) { await runDemo() }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Stage
    private var demoStage: some View {
        VStack(spacing: DSSpacing.md) {
            sentenceCard
            popup
        }
        .frame(height: 280, alignment: .top)
    }

    /// The "PDF paragraph" being selected.
    private var sentenceCard: some View {
        Text(sampleText)
            .font(DSFont.translation)
            .multilineTextAlignment(.leading)
            .padding(DSSpacing.md)
            .background(alignment: .leading) {
                // Selection sweep — grows left-to-right like a finger drag.
                RoundedRectangle(cornerRadius: DSRadius.small, style: .continuous)
                    .fill(DSColor.brand.opacity(0.22))
                    .scaleEffect(x: max(selectionProgress, 0.001), anchor: .leading)
            }
            .background {
                RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
                    .fill(DSColor.surfaceCard)
            }
            .dsShadow(.subtle)
            .frame(maxWidth: 320)
    }

    private var popupVisible: Bool { step == .popupLoading || step == .popupTranslated }

    private var popupPhase: TranslationPopupPhase {
        step == .popupTranslated ? .translated(sampleTranslation) : .loading
    }

    /// Real popup chrome: same drag handle, glass background and content area
    /// the reader uses.
    private var popup: some View {
        VStack(spacing: 0) {
            TranslationPopupDragHandle()
            TranslationPopupContentArea(phase: popupPhase, maxHeight: 150)
        }
        .frame(width: 300)
        .translationPopupSurface()
        .scaleEffect(popupVisible ? 1 : 0.92, anchor: .top)
        .opacity(popupVisible ? 1 : 0)
        .dsAnimation(DSMotion.snappy, value: popupVisible)
        .dsAnimation(DSMotion.smooth, value: step)
    }

    // MARK: - Choreography
    private func runDemo() async {
        guard isActive else {
            step = .idle
            selectionProgress = 0
            return
        }

        // Reduce Motion: show the finished moment statically.
        if reduceMotion {
            selectionProgress = 1
            step = .popupTranslated
            return
        }

        while !Task.isCancelled {
            step = .idle
            selectionProgress = 0
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.7)) { selectionProgress = 1 }
            step = .selecting
            try? await Task.sleep(nanoseconds: 850_000_000)
            guard !Task.isCancelled else { return }

            step = .popupLoading
            if !playedHaptics { DSHaptics.lightImpact() }
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            guard !Task.isCancelled else { return }

            step = .popupTranslated
            if !playedHaptics {
                DSHaptics.softImpact()
                playedHaptics = true
            }
            try? await Task.sleep(nanoseconds: 3_400_000_000)
        }
    }
}

#Preview {
    OnboardingTranslatePage(isActive: true)
}
