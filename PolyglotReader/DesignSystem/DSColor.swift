import SwiftUI

// MARK: - Semantic Color Tokens
/// Single source of truth for the app's color language.
/// Brand colors live in the asset catalog (dark/light variants);
/// views must use these tokens instead of `.indigo` / `Color(hex:)` literals.
enum DSColor {
    // MARK: Brand
    /// Primary brand color — CTAs, active states, brand moments.
    static let brand = Color("BrandPrimary")
    /// Gradient partner of `brand`; also marks AI-adjacent surfaces.
    static let brandSecondary = Color("BrandSecondary")
    /// Sparkle/AI moments (summary, deep search). Reserved for AI features.
    static let aiAccent = Color("AIAccent")

    /// The app's signature gradient. Only for icon fills, CTAs and glows —
    /// never for text or large surfaces.
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [brand, brandSecondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Colored component of the signature double shadow under glass surfaces.
    static var glassGlow: Color { brand.opacity(0.10) }

    // MARK: Semantic states
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red

    // MARK: Surfaces
    /// Screen background (grouped context).
    static let surfacePrimary = Color(.systemGroupedBackground)
    /// Secondary grouped surface (cards inside grouped screens).
    static let surfaceSecondary = Color(.secondarySystemGroupedBackground)
    /// Opaque content card surface.
    static let surfaceCard = Color(.systemBackground)
}

// MARK: - Highlight Palette
extension DSColor {
    /// Annotation highlight palette. The raw value is the CANONICAL hex string
    /// persisted in the `annotations` table — renaming or changing a value
    /// would orphan existing user annotations, so treat raw values as frozen data.
    enum Highlight: String, CaseIterable {
        case yellow = "#fef08a"
        case green = "#bbf7d0"
        case pink = "#fbcfe8"
        case blue = "#bae6fd"

        /// Display color. Fixed (no dark variant) because highlights render
        /// on top of PDF paper, which stays light in both appearances.
        var color: Color {
            switch self {
            case .yellow: return Color(hex: rawValue) ?? .yellow
            case .green: return Color(hex: rawValue) ?? .green
            case .pink: return Color(hex: rawValue) ?? .pink
            case .blue: return Color(hex: rawValue) ?? .blue
            }
        }

        /// Localized user-facing name ("Sarı", "Yeşil", ...).
        var localizedName: String {
            switch self {
            case .yellow: return "highlight.color.yellow".localized
            case .green: return "highlight.color.green".localized
            case .pink: return "highlight.color.pink".localized
            case .blue: return "highlight.color.blue".localized
            }
        }

        /// Case-insensitive lookup from a persisted hex string.
        static func from(hex: String) -> Highlight? {
            Highlight(rawValue: hex.lowercased())
        }
    }
}
