import SwiftUI

// MARK: - Skeleton / Shimmer
/// Loading placeholders for dynamic content. Rule: only CONTENT gets a
/// skeleton (thumbnails, stats, chat history) — chrome never does.

/// Left-to-right shimmer sweep over any placeholder shape.
private struct DSSkeletonShimmerModifier: ViewModifier {
    let isActive: Bool
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if isActive && !reduceMotion {
                GeometryReader { geometry in
                    let band = geometry.size.width * 0.6
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.45), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: band)
                    .offset(x: isAnimating ? geometry.size.width : -band)
                    .onAppear {
                        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                            isAnimating = true
                        }
                    }
                }
                .clipped()
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// Adds the shimmer sweep while `isActive`; static (no motion) under
    /// Reduce Motion.
    func dsSkeletonShimmer(isActive: Bool = true) -> some View {
        modifier(DSSkeletonShimmerModifier(isActive: isActive))
    }
}

/// Ready-made shimmering block for image/thumbnail slots.
struct SkeletonBlock: View {
    var cornerRadius: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.secondary.opacity(0.14))
            .dsSkeletonShimmer()
            .accessibilityHidden(true)
    }
}
