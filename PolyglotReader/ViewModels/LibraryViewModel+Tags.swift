import Foundation

@MainActor
extension LibraryViewModel {
    // MARK: - Tag Management

    /// Etiket filtresini aç/kapa
    func toggleTagFilter(_ tagId: UUID) {
        if selectedTags.contains(tagId) {
            selectedTags.remove(tagId)
        } else {
            selectedTags.insert(tagId)
        }
    }

    /// Tüm etiket filtrelerini temizle
    func clearTagFilters() {
        selectedTags.removeAll()
    }
}
