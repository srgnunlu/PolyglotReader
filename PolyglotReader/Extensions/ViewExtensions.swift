import SwiftUI

// MARK: - Edge Swipe to Dismiss
struct EdgeSwipeToDismissModifier: ViewModifier {
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var isHorizontalGesture = false

    private let edgeWidth: CGFloat = 20  // Sol kenardan kaç pixel içinde gesture başlayabilir (daha dar)
    private let dismissThreshold: CGFloat = 80  // Kaç pixel sağa sürüklenirse dismiss olur (daha az)
    // Yatay/dikey oran - yatay hareket dikey hareketin 1.5 katından fazla olmalı
    private let horizontalRatio: CGFloat = 1.5

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .offset(x: dragOffset)
                .simultaneousGesture(edgeSwipeGesture(in: geometry))
        }
    }

    private func edgeSwipeGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                handleDragChanged(value)
            }
            .onEnded { value in
                handleDragEnded(value, geometryWidth: geometry.size.width)
            }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        // Sadece sol kenardan başlayan ve yatay hareketi dominant olan swipe'ları kabul et
        guard value.startLocation.x < edgeWidth else { return }

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

    private func handleDragEnded(_ value: DragGesture.Value, geometryWidth: CGFloat) {
        if isDragging && isHorizontalGesture && value.startLocation.x < edgeWidth {
            let horizontalDistance = abs(value.translation.width)
            let verticalDistance = abs(value.translation.height)

            // Son kontrol: yatay hareket hala dominant mi ve threshold'u geçti mi?
            if horizontalDistance > verticalDistance * horizontalRatio &&
                value.translation.width > dismissThreshold {
                withAnimation(.easeOut(duration: 0.3)) {
                    dragOffset = geometryWidth
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
