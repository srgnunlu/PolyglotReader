import SwiftUI

// MARK: - Chat Search Bar
// Aktifken mesaj listesi yalnız eşleşenleri gösterir; bir sonuca dokunmak
// aramayı kapatıp o mesaja kaydırır (ChatView yönetir).

struct ChatSearchBar: View {
    @Binding var query: String
    let matchCount: Int
    let onClose: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("chat.search.placeholder".localized, text: $query)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .accessibilityIdentifier("chat_search_field")

            if !query.isEmpty {
                Text(String(format: "chat.search.count".localized, matchCount))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 32, minHeight: 32)
            }
            .accessibilityLabel("common.cancel".localized)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, DSSpacing.xxs)
        .onAppear { isFocused = true }
    }
}
