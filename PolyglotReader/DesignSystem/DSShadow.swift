import SwiftUI

// MARK: - Shadow Tokens
/// The app's signature is a DOUBLE shadow: a black ambient layer plus a
/// colored glow. Applying both through one modifier keeps every surface
/// consistent and makes global tuning possible.
enum DSShadowLevel {
    /// Small controls, list rows.
    case subtle
    /// Content cards (matches the previous LiquidGlassCard values).
    case card
    /// Floating chrome: popups, docks, overlays.
    case floating

    var ambientOpacity: Double {
        switch self {
        case .subtle: return 0.08
        case .card: return 0.12
        case .floating: return 0.12
        }
    }

    var ambientRadius: CGFloat {
        switch self {
        case .subtle: return 8
        case .card: return 12
        case .floating: return 24
        }
    }

    var ambientY: CGFloat {
        switch self {
        case .subtle: return 4
        case .card: return 6
        case .floating: return 12
        }
    }

    var glowOpacity: Double {
        switch self {
        case .subtle: return 0
        case .card: return 0.08
        case .floating: return 0.10
        }
    }

    var glowRadius: CGFloat {
        switch self {
        case .subtle: return 0
        case .card: return 20
        case .floating: return 24
        }
    }

    var glowY: CGFloat {
        switch self {
        case .subtle: return 0
        case .card: return 10
        case .floating: return 12
        }
    }
}

private struct DSShadowModifier: ViewModifier {
    let level: DSShadowLevel
    let tint: Color

    func body(content: Content) -> some View {
        content
            .shadow(
                color: .black.opacity(level.ambientOpacity),
                radius: level.ambientRadius,
                x: 0,
                y: level.ambientY
            )
            .shadow(
                color: tint.opacity(level.glowOpacity),
                radius: level.glowRadius,
                x: 0,
                y: level.glowY
            )
    }
}

extension View {
    /// Applies the signature double shadow (black ambient + colored glow).
    func dsShadow(_ level: DSShadowLevel = .card, tint: Color = DSColor.brand) -> some View {
        modifier(DSShadowModifier(level: level, tint: tint))
    }
}
