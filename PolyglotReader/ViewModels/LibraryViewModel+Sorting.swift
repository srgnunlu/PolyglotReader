import Foundation

@MainActor
extension LibraryViewModel {
    // MARK: - Toggle Sort

    func toggleSort(_ option: SortOption) {
        if sortBy == option {
            sortOrder = sortOrder == .ascending ? .descending : .ascending
        } else {
            sortBy = option
            sortOrder = .descending
        }
    }
}
