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

// MARK: - Liquid Glass Background

/// QuickTranslationPopup'ın Liquid Glass arka planı
struct TranslationPopupBackground: View {
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            // Ana blur katmanı
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)

            // Gradient overlay - üst parlama
            LinearGradient(
                colors: [
                    .white.opacity(0.35),
                    .white.opacity(0.1),
                    .clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            // Renkli cam efekti
            RadialGradient(
                colors: [
                    .indigo.opacity(0.08),
                    .purple.opacity(0.05),
                    .clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 200
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            // İç glow
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.7),
                            .white.opacity(0.3),
                            .white.opacity(0.1),
                            .white.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )

            // Dış ince kenar
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(.white.opacity(0.2), lineWidth: 0.5)
                .blur(radius: 0.5)
        }
    }
}
