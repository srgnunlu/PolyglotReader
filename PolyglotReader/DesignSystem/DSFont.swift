import SwiftUI

// MARK: - Semantic Typography Tokens
/// 100% SF Pro via Dynamic Type styles — fixed `.system(size:)` values are
/// banned (SwiftLint `no_fixed_font_size`) because they break accessibility.
/// If a view needs a scalable custom metric, use `@ScaledMetric` instead.
enum DSFont {
    /// Onboarding, empty states — the biggest headline moments.
    static let displayTitle = Font.largeTitle.bold()
    /// Screen titles.
    static let screenTitle = Font.title2.bold()
    /// Card names, list item titles.
    static let cardTitle = Font.headline
    /// General body text.
    static let body = Font.body
    /// Translation text — the rounded design is part of the popup's identity,
    /// now bound to Dynamic Type.
    static let translation = Font.system(.body, design: .rounded)
    /// AI summary on the flip card — serif italic is its signature.
    static let aiSummary = Font.system(.subheadline, design: .serif).italic()
    /// Dates, file sizes, page numbers.
    static let caption = Font.caption
    static let meta = Font.caption2

    // MARK: Controls
    /// Icons inside circular/capsule toolbar controls (replaces `.system(size: 15, weight: .semibold)`).
    static let controlIcon = Font.subheadline.weight(.semibold)
    /// Prominent control icons (primary CTA circles).
    static let controlIconProminent = Font.body.weight(.semibold)
}
