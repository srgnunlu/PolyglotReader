import SwiftUI

// MARK: - Glass / Depth System
/// Single call point for every glass surface in the app.
///
/// On iOS 26+ this maps to Apple's native Liquid Glass (`glassEffect`), which
/// handles Reduced Transparency / Increased Contrast for free. On iOS 17-25 it
/// renders a deliberately designed material look (the app's existing glass
/// recipe), so older systems see a finished design — not a degraded iOS 26.
///
/// HIG rule encoded here: glass belongs ONLY to the navigation layer (bars,
/// docks, popups, banners, controls) — never on content or backgrounds.
enum DSGlassLevel {
    /// Floating top bars / bottom docks.
    case bar
    /// Small circular/capsule controls (toolbar buttons, pills).
    case control
    /// Popups and overlays that carry text — strongest material for legibility.
    case popup
    /// Glass-styled cards (library grid).
    case card
    /// Full-width banners (errors, OCR notices).
    case banner

    /// Material strength for the iOS 17-25 fallback renderer.
    fileprivate var fallbackMaterial: Material {
        switch self {
        case .control: return .ultraThinMaterial
        case .bar, .card: return .thinMaterial
        case .popup, .banner: return .regularMaterial
        }
    }

    fileprivate var sheenOpacity: Double {
        switch self {
        case .control: return 0.25
        case .bar, .card: return 0.35
        case .popup, .banner: return 0.45
        }
    }
}

// MARK: - Shape
enum DSGlassShape {
    case capsule
    case circle
    case rounded(CGFloat)

    fileprivate var shape: AnyShape {
        switch self {
        case .capsule: return AnyShape(Capsule())
        case .circle: return AnyShape(Circle())
        case .rounded(let radius):
            return AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}

// MARK: - Modifier
private struct DSGlassModifier: ViewModifier {
    let level: DSGlassLevel
    let glassShape: DSGlassShape
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(nativeGlass, in: glassShape.shape)
        } else {
            content
                .background { FallbackGlassSurface(level: level, glassShape: glassShape, tint: tint) }
                .clipShape(glassShape.shape)
        }
    }

    @available(iOS 26.0, *)
    private var nativeGlass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

// MARK: - Fallback Renderer (iOS 17-25)
/// Generic-shape version of the app's proven glass recipe
/// (material + top sheen + radial hue + gradient edge). `LiquidGlassBackground`
/// keeps serving existing rounded-rect surfaces until they migrate to `.dsGlass`.
private struct FallbackGlassSurface: View {
    let level: DSGlassLevel
    let glassShape: DSGlassShape
    let tint: Color?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isDark: Bool { colorScheme == .dark }
    // A pure-white sheen washes out in light mode; dim it and switch the edge
    // to a dark hairline so the surface still reads as bounded.
    private var glowScale: Double { isDark ? 1.0 : 0.35 }
    private var edgeColor: Color { isDark ? .white : .black }
    private var edgeScale: Double { isDark ? 1.0 : 0.2 }
    private var hue: Color { tint ?? DSColor.brand }

    var body: some View {
        if reduceTransparency {
            // Opaque stand-in: same silhouette, no blur dependence.
            glassShape.shape
                .fill(Color(.secondarySystemBackground))
                .overlay { glassShape.shape.stroke(Color.primary.opacity(0.15), lineWidth: 1) }
        } else {
            ZStack {
                glassShape.shape.fill(level.fallbackMaterial)

                LinearGradient(
                    colors: [
                        .white.opacity(level.sheenOpacity * glowScale),
                        .white.opacity(level.sheenOpacity * 0.3 * glowScale),
                        .clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(glassShape.shape)

                RadialGradient(
                    colors: [hue.opacity(0.08), hue.opacity(0.04), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 200
                )
                .clipShape(glassShape.shape)

                glassShape.shape.stroke(
                    LinearGradient(
                        colors: [
                            edgeColor.opacity(0.6 * edgeScale),
                            edgeColor.opacity(0.25 * edgeScale),
                            edgeColor.opacity(0.1 * edgeScale),
                            edgeColor.opacity(0.25 * edgeScale)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
        }
    }
}

// MARK: - View API
extension View {
    /// Applies the app's glass language to a navigation-layer surface.
    /// - Parameters:
    ///   - level: Semantic role of the surface (bar, control, popup, ...).
    ///   - shape: Silhouette; defaults to the card radius.
    ///   - tint: Optional hue. `nil` keeps native iOS 26 glass untinted
    ///     (the HIG-correct default) while the fallback uses the brand hue
    ///     for its subtle radial glow.
    ///   - interactive: iOS 26 only — glass shimmers while touched.
    func dsGlass(
        _ level: DSGlassLevel = .card,
        shape: DSGlassShape = .rounded(DSRadius.card),
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(DSGlassModifier(level: level, glassShape: shape, tint: tint, interactive: interactive))
    }
}
