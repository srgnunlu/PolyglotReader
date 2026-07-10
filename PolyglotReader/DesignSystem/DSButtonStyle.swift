import SwiftUI

// MARK: - Pressable Button Style
/// The app's shared press feedback: a subtle scale-down with a snappy
/// spring, generalized from the old PDFCardButtonStyle so every tappable
/// surface answers the finger the same way. Reduce Motion suppresses the
/// scale via dsAnimation.
struct DSPressableButtonStyle: ButtonStyle {
    /// 0.96 reads right on cards; pass a deeper value only if a control is
    /// so small the default press is invisible.
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .dsAnimation(DSMotion.snappy, value: configuration.isPressed)
    }
}
