import SwiftUI

// MARK: - Page 1: "Oku"
/// A layered mini document rises into place with depth — the reading promise.
struct OnboardingReadPage: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: DSSpacing.xl) {
            Spacer()

            documentStack
                .accessibilityHidden(true)

            VStack(spacing: DSSpacing.sm) {
                Text("onboarding.page1.title".localized)
                    .font(DSFont.displayTitle)
                Text("onboarding.page1.subtitle".localized)
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
        .accessibilityElement(children: .combine)
    }

    private func startIfNeeded() {
        guard isActive else { return }
        if reduceMotion {
            appeared = true
        } else {
            withAnimation(DSMotion.smooth.delay(0.15)) { appeared = true }
        }
    }

    // MARK: - Layered Document
    private var documentStack: some View {
        ZStack {
            // Depth layers — further sheets sit higher and dimmer.
            documentSheet(scale: 0.86, tint: DSColor.brandSecondary.opacity(0.12))
                .offset(y: appeared ? -36 : 12)
                .opacity(appeared ? 1 : 0)

            documentSheet(scale: 0.93, tint: DSColor.brand.opacity(0.10))
                .offset(y: appeared ? -18 : 6)
                .opacity(appeared ? 1 : 0)

            frontSheet
                .offset(y: appeared ? 0 : 24)
                .opacity(appeared ? 1 : 0)
        }
        .dsAnimation(DSMotion.smooth, value: appeared)
        .frame(width: 220, height: 280)
    }

    private func documentSheet(scale: CGFloat, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
            .fill(DSColor.surfaceCard)
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
                    .fill(tint)
            }
            .frame(width: 220 * scale, height: 280 * scale)
            .dsShadow(.subtle)
    }

    /// The front "PDF page": text line placeholders with one highlighted line —
    /// a quiet nod to the annotation feature.
    private var frontSheet: some View {
        RoundedRectangle(cornerRadius: DSRadius.medium, style: .continuous)
            .fill(DSColor.surfaceCard)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    Capsule()
                        .fill(Color.primary.opacity(0.55))
                        .frame(width: 120, height: 10)
                        .padding(.bottom, DSSpacing.xxs)

                    textLine(width: 172)
                    textLine(width: 160)

                    Capsule()
                        .fill(DSColor.Highlight.yellow.color)
                        .overlay { textLine(width: 148).opacity(0.6) }
                        .frame(width: 148, height: 8)

                    textLine(width: 166)
                    textLine(width: 120)
                    textLine(width: 158)
                    textLine(width: 92)
                }
                .padding(DSSpacing.lg)
            }
            .frame(width: 220, height: 280)
            .dsShadow(.floating)
    }

    private func textLine(width: CGFloat) -> some View {
        Capsule()
            .fill(Color.secondary.opacity(0.28))
            .frame(width: width, height: 8)
    }
}

#Preview {
    OnboardingReadPage(isActive: true)
}
