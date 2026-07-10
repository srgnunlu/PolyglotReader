import SwiftUI

// MARK: - Spacing Tokens (4pt base grid)
/// Card inner padding = `md`, screen edge padding = `md`, section gap = `lg`.
enum DSSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Corner Radius Tokens
/// Derived from the app's existing de-facto values — do not invent new radii.
enum DSRadius {
    static let small: CGFloat = 12
    static let medium: CGFloat = 16
    static let card: CGFloat = 20
    static let popup: CGFloat = 24
    static let dock: CGFloat = 28
}
