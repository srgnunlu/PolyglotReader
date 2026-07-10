import SwiftUI

// MARK: - Onboarding Parallax
/// Sayfa kaydırılırken hero illüstrasyonu metinden biraz daha yavaş hareket
/// eder — ucuz, render-zamanı bir derinlik katmanı. `visualEffect` layout'a
/// dokunmaz (plan kuralı: GeometryReader tabanlı el yapımı parallax yasak).
/// Reduce Motion açıkken hiçbir kayma uygulanmaz.
private struct OnboardingParallaxModifier: ViewModifier {
    /// 0...1 — sayfanın kayma miktarının ne kadarı geride bırakılır.
    let strength: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.visualEffect { [strength] view, proxy in
                // Sayfa TabView içinde kayarken global minX değişir; bunun bir
                // kısmını geri alarak katman "geride kalır" (lag = derinlik).
                view.offset(x: -proxy.frame(in: .global).minX * strength)
            }
        }
    }
}

extension View {
    /// Onboarding hero katmanlarına hafif kaydırma paralaksı uygular.
    /// Daha "uzak" katmanlar için daha yüksek `strength` kullanın.
    func onboardingParallax(strength: CGFloat = 0.14) -> some View {
        modifier(OnboardingParallaxModifier(strength: strength))
    }
}
