import SwiftUI

// MARK: - Drag Handle

/// QuickTranslationPopup üst tutamacı (sürükleme ipucu)
struct TranslationPopupDragHandle: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Arka plan pill şekli
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(.systemGray3),
                                Color(.systemGray4)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 48, height: 6)

                // Üst parlama
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.8), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 46, height: 3)
                    .offset(y: -0.5)

                // Kenar çizgisi
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.5), Color(.systemGray2)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
                    .frame(width: 48, height: 6)
            }
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
        .frame(height: TranslationPopupLayout.handleHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - Popup Surface

extension View {
    /// Shared surface of the quick-translation popup: glass + clip + signature
    /// shadow in one call. Used by the real popup AND the onboarding demo so
    /// the two can never drift apart. On iOS 26 the glass is interactive —
    /// it shimmers under the finger while the popup is dragged.
    func translationPopupSurface() -> some View {
        self
            .dsGlass(.popup, shape: .rounded(DSRadius.popup), interactive: true)
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.popup, style: .continuous))
            .dsShadow(.floating)
    }
}
