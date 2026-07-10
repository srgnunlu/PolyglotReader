import SwiftUI

// MARK: - Motion Tokens
/// The app speaks spring. Three semantic presets instead of hand-tuned
/// `response`/`dampingFraction` pairs scattered across views:
/// - `smooth` — screen/element transitions
/// - `snappy` — direct-manipulation controls (toggles, selections)
/// - `celebrate` — earned celebration moments ONLY (quiz result, first upload)
///
/// Rule: if "what does this animation tell the user?" has no answer, delete
/// the animation. Durations stay ≤0.4s (celebrations ≤0.8s).
enum DSMotion {
    static let smooth = Animation.smooth(duration: 0.35)
    static let snappy = Animation.snappy(duration: 0.3)
    static let celebrate = Animation.bouncy(duration: 0.5, extraBounce: 0.1)

    /// For `withAnimation` call sites that already read reduce-motion from
    /// the environment. Views should prefer `.dsAnimation(_:value:)`.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - Reduce-Motion-Aware Animation
private struct DSAnimationModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// `.animation(_:value:)` that centrally respects Reduce Motion —
    /// closes the accessibility gap one call site at a time.
    func dsAnimation<Value: Equatable>(_ animation: Animation, value: Value) -> some View {
        modifier(DSAnimationModifier(animation: animation, value: value))
    }
}
