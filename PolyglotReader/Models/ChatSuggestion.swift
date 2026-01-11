import Foundation

struct ChatSuggestion: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let prompt: String
}
