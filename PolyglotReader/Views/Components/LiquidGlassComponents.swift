import SwiftUI

// MARK: - Liquid Glass Background
/// iOS native liquid glass efekti için temel arka plan bileşeni
struct LiquidGlassBackground: View {
    var cornerRadius: CGFloat = 20
    var intensity: LiquidGlassIntensity = .medium
    var accentColor: Color = .indigo

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    // In light mode a pure-white glow washes out and white strokes become
    // invisible borders. Dim the glow and use a subtle dark edge for definition.
    private var glowOpacityScale: Double { isDark ? 1.0 : 0.35 }
    private var edgeColor: Color { isDark ? .white : .black }
    private var edgeOpacityScale: Double { isDark ? 1.0 : 0.2 }

    var body: some View {
        ZStack {
            // Ana blur katmanı
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(intensity.material)

            // Gradient overlay - üst parlama
            LinearGradient(
                colors: [
                    .white.opacity(intensity.topGlowOpacity * glowOpacityScale),
                    .white.opacity(intensity.topGlowOpacity * 0.3 * glowOpacityScale),
                    .clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            // Renkli cam efekti
            RadialGradient(
                colors: [
                    accentColor.opacity(0.08),
                    accentColor.opacity(0.04),
                    .clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 200
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

            // İç glow - parlak kenar (light mode'da koyu, görünür kenarlık)
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    LinearGradient(
                        colors: [
                            edgeColor.opacity(0.6 * edgeOpacityScale),
                            edgeColor.opacity(0.25 * edgeOpacityScale),
                            edgeColor.opacity(0.1 * edgeOpacityScale),
                            edgeColor.opacity(0.25 * edgeOpacityScale)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            // Dış ince kenar
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(edgeColor.opacity(0.15 * edgeOpacityScale), lineWidth: 0.5)
                .blur(radius: 0.5)
        }
    }
}

// MARK: - Intensity Levels
enum LiquidGlassIntensity {
    case light
    case medium
    case heavy

    var material: Material {
        switch self {
        case .light: return .ultraThinMaterial
        case .medium: return .thinMaterial
        case .heavy: return .regularMaterial
        }
    }

    var topGlowOpacity: Double {
        switch self {
        case .light: return 0.25
        case .medium: return 0.35
        case .heavy: return 0.45
        }
    }
}

// MARK: - Liquid Glass Search Bar
struct LiquidGlassSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Ara..."

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 16, weight: .medium))

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            LiquidGlassBackground(
                cornerRadius: 14,
                intensity: .light,
                accentColor: .indigo
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        LinearGradient(
            colors: [.blue.opacity(0.3), .purple.opacity(0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack(spacing: 20) {
            // Search Bar
            LiquidGlassSearchBar(text: .constant(""), placeholder: "Dosya ara...")
                .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 50)
    }
}
