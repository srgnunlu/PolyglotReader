import SwiftUI

// MARK: - Theme Colors
extension Color {
    static let theme = ThemeColors()
}

struct ThemeColors {
    let primary = Color.indigo
    let secondary = Color.purple
    let accent = Color.orange
    let background = Color(.systemGroupedBackground)
    let cardBackground = Color(.systemBackground)
    let success = Color.green
    let warning = Color.orange
    let error = Color.red
    
    // Highlight Colors
    let highlightYellow = Color(hex: "#fef08a")!
    let highlightGreen = Color(hex: "#bbf7d0")!
    let highlightPink = Color(hex: "#fbcfe8")!
    let highlightBlue = Color(hex: "#bae6fd")!
}

// MARK: - Glassmorphism Modifier
struct GlassmorphismModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }
}

extension View {
    func glassmorphism() -> some View {
        modifier(GlassmorphismModifier())
    }
}

// MARK: - Card Modifier
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}

// MARK: - Shimmer Effect
struct ShimmerModifier: ViewModifier {
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(0.5),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: isAnimating ? 200 : -200)
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Bounce Effect
struct BounceModifier: ViewModifier {
    @State private var isPressed = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

extension View {
    func bounceEffect() -> some View {
        modifier(BounceModifier())
    }
}

// MARK: - Fade In Animation
struct FadeInModifier: ViewModifier {
    @State private var opacity: Double = 0
    let delay: Double
    
    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeIn(duration: 0.3).delay(delay)) {
                    opacity = 1
                }
            }
    }
}

extension View {
    func fadeIn(delay: Double = 0) -> some View {
        modifier(FadeInModifier(delay: delay))
    }
}

// MARK: - Conditional Modifier
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Edge Swipe to Dismiss
struct EdgeSwipeToDismissModifier: ViewModifier {
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var isHorizontalGesture = false

    private let edgeWidth: CGFloat = 20  // Sol kenardan kaç pixel içinde gesture başlayabilir (daha dar)
    private let dismissThreshold: CGFloat = 80  // Kaç pixel sağa sürüklenirse dismiss olur (daha az)
    private let horizontalRatio: CGFloat = 1.5  // Yatay/dikey oran - yatay hareket dikey hareketin 1.5 katından fazla olmalı

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .offset(x: dragOffset)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 15)
                        .onChanged { value in
                            // Sadece sol kenardan başlayan ve yatay hareketi dominant olan swipe'ları kabul et
                            if value.startLocation.x < edgeWidth {
                                let horizontalDistance = abs(value.translation.width)
                                let verticalDistance = abs(value.translation.height)

                                // Yatay hareket dikey hareketten belirgin şekilde fazla olmalı
                                if horizontalDistance > verticalDistance * horizontalRatio {
                                    isDragging = true
                                    isHorizontalGesture = true

                                    // Sadece sağa doğru (pozitif) offset'e izin ver
                                    if value.translation.width > 0 {
                                        // Resistance effect - başlangıçta daha az, sonra daha fazla hareket
                                        let resistance = min(value.translation.width / 300, 1.0)
                                        dragOffset = value.translation.width * (0.3 + resistance * 0.7)
                                    }
                                } else if horizontalDistance < verticalDistance {
                                    // Dikey hareket daha dominant - swipe'ı iptal et
                                    isDragging = false
                                    isHorizontalGesture = false
                                }
                            }
                        }
                        .onEnded { value in
                            if isDragging && isHorizontalGesture && value.startLocation.x < edgeWidth {
                                let horizontalDistance = abs(value.translation.width)
                                let verticalDistance = abs(value.translation.height)

                                // Son kontrol: yatay hareket hala dominant mi ve threshold'u geçti mi?
                                if horizontalDistance > verticalDistance * horizontalRatio &&
                                   value.translation.width > dismissThreshold {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        dragOffset = geometry.size.width
                                    }
                                    // Animasyon tamamlandıktan sonra dismiss
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        onDismiss()
                                    }
                                } else {
                                    // Yeterince sürüklenmemişse veya dikey hareket varsa geri gel
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        dragOffset = 0
                                    }
                                }
                            } else {
                                // Gesture iptal edildi - geri gel
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    dragOffset = 0
                                }
                            }
                            isDragging = false
                            isHorizontalGesture = false
                        }
                )
        }
    }
}

extension View {
    func edgeSwipeToDismiss(onDismiss: @escaping () -> Void) -> some View {
        modifier(EdgeSwipeToDismissModifier(onDismiss: onDismiss))
    }
}

// MARK: - Date Extensions
extension Date {
    /// Relative time string with Turkish locale
    func relativeTimeString() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
