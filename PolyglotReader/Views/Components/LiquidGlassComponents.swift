import SwiftUI

// MARK: - Liquid Glass Background
/// iOS native liquid glass efekti için temel arka plan bileşeni
struct LiquidGlassBackground: View {
    var cornerRadius: CGFloat = 20
    var intensity: LiquidGlassIntensity = .medium
    var accentColor: Color = .indigo

    var body: some View {
        ZStack {
            // Ana blur katmanı
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(intensity.material)

            // Gradient overlay - üst parlama
            LinearGradient(
                colors: [
                    .white.opacity(intensity.topGlowOpacity),
                    .white.opacity(intensity.topGlowOpacity * 0.3),
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

            // İç glow - parlak kenar
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.6),
                            .white.opacity(0.25),
                            .white.opacity(0.1),
                            .white.opacity(0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            // Dış ince kenar
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
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

// MARK: - Liquid Glass Card
/// Liquid glass tasarımlı kart bileşeni
struct LiquidGlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 20
    var accentColor: Color = .indigo
    var shadowOpacity: Double = 0.12

    init(
        cornerRadius: CGFloat = 20,
        accentColor: Color = .indigo,
        shadowOpacity: Double = 0.12,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.accentColor = accentColor
        self.shadowOpacity = shadowOpacity
        self.content = content()
    }

    var body: some View {
        content
            .background {
                LiquidGlassBackground(
                    cornerRadius: cornerRadius,
                    intensity: .medium,
                    accentColor: accentColor
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(shadowOpacity), radius: 12, x: 0, y: 6)
            .shadow(color: accentColor.opacity(0.08), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Liquid Glass Button Style
struct LiquidGlassButtonStyle: ButtonStyle {
    var isSelected: Bool = false
    var accentColor: Color = .indigo

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                ZStack {
                    Capsule()
                        .fill(isSelected ? .ultraThinMaterial : .ultraThinMaterial)

                    if isSelected {
                        // Seçili durum için glow
                        Capsule()
                            .fill(accentColor.opacity(0.15))

                        Capsule()
                            .stroke(accentColor.opacity(0.4), lineWidth: 1)
                    } else {
                        // Normal durum için subtle border
                        Capsule()
                            .stroke(.white.opacity(0.3), lineWidth: 0.5)
                    }

                    // Üst parlama
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.3), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .padding(1)
                }
            }
            .foregroundStyle(isSelected ? accentColor : .secondary)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
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

// MARK: - Liquid Glass Tab Bar
struct LiquidGlassTabBar: View {
    @Binding var selectedTab: Int
    let tabs: [(icon: String, title: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                tabButton(for: index, icon: tab.icon, title: tab.title)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background {
            LiquidGlassBackground(
                cornerRadius: 28,
                intensity: .medium,
                accentColor: .indigo
            )
        }
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .shadow(color: .indigo.opacity(0.1), radius: 30, x: 0, y: 15)
        .padding(.horizontal, 40)
        .padding(.bottom, 20)
    }

    private func tabButton(for index: Int, icon: String, title: String) -> some View {
        let isSelected = selectedTab == index

        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                selectedTab = index
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: isSelected ? .semibold : .regular))

                Text(title)
                    .font(.caption2)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundStyle(isSelected ? .indigo : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(.indigo.opacity(0.12))
                        .overlay {
                            Capsule()
                                .stroke(.indigo.opacity(0.2), lineWidth: 1)
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Liquid Glass Pill Button
struct LiquidGlassPillButton: View {
    let title: String
    let icon: String?
    var isSelected: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .medium)
            }
        }
        .buttonStyle(LiquidGlassButtonStyle(isSelected: isSelected))
    }
}

// MARK: - View Extension
extension View {
    /// Liquid glass efekti uygular
    func liquidGlass(
        cornerRadius: CGFloat = 20,
        intensity: LiquidGlassIntensity = .medium,
        accentColor: Color = .indigo
    ) -> some View {
        self
            .background {
                LiquidGlassBackground(
                    cornerRadius: cornerRadius,
                    intensity: intensity,
                    accentColor: accentColor
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// Liquid glass efekti ile shadow
    func liquidGlassCard(
        cornerRadius: CGFloat = 20,
        shadowOpacity: Double = 0.12
    ) -> some View {
        self
            .liquidGlass(cornerRadius: cornerRadius)
            .shadow(color: .black.opacity(shadowOpacity), radius: 12, x: 0, y: 6)
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

            // Pills
            HStack(spacing: 8) {
                LiquidGlassPillButton(title: "Tarih", icon: "chevron.down", isSelected: true) {}
                LiquidGlassPillButton(title: "İsim", icon: nil, isSelected: false) {}
                LiquidGlassPillButton(title: "Boyut", icon: nil, isSelected: false) {}
            }

            // Card
            LiquidGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Örnek PDF.pdf")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("1.2 MB • 20 Ara 2025")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .frame(width: 180)

            Spacer()

            // Tab Bar
            LiquidGlassTabBar(
                selectedTab: .constant(0),
                tabs: [
                    ("books.vertical", "Kütüphane"),
                    ("bookmark.fill", "Defterim"),
                    ("gearshape.fill", "Ayarlar")
                ]
            )
        }
        .padding(.top, 50)
    }
}
