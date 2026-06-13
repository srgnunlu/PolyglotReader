import Foundation

/// Persists a user-chosen SF Symbol per folder.
///
/// The Supabase `folders` table has no icon column, so the chosen glyph is stored
/// locally in `UserDefaults` keyed by folder UUID. This keeps icon selection a
/// purely client-side enhancement (no schema migration) while letting the folder
/// cards render the user's choice.
final class FolderIconStore {
    static let shared = FolderIconStore()

    /// Curated set of folder-appropriate SF Symbols offered in the picker.
    static let availableIcons: [String] = [
        "folder.fill",
        "doc.text.fill",
        "books.vertical.fill",
        "graduationcap.fill",
        "cross.case.fill",
        "stethoscope",
        "brain.head.profile",
        "flask.fill",
        "building.columns.fill",
        "chart.line.uptrend.xyaxis",
        "briefcase.fill",
        "star.fill",
        "heart.fill",
        "bookmark.fill",
        "tag.fill",
        "lightbulb.fill"
    ]

    private let defaults = UserDefaults.standard
    private let keyPrefix = "folder.icon."

    private init() {}

    /// Returns the stored icon for a folder, or `nil` if none was chosen.
    func icon(for folderId: UUID) -> String? {
        defaults.string(forKey: keyPrefix + folderId.uuidString)
    }

    /// Stores (or clears) the icon for a folder.
    func setIcon(_ icon: String?, for folderId: UUID) {
        let key = keyPrefix + folderId.uuidString
        if let icon, !icon.isEmpty {
            defaults.set(icon, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
