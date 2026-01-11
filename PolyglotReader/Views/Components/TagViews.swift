import SwiftUI

// MARK: - Tag Chip View
/// iOS native tarzı etiket chip bileşeni
struct TagChipView: View {
    let tag: Tag
    var isSelected: Bool = false
    var showCount: Bool = false
    var onTap: (() -> Void)?

    private var tagColor: Color {
        Color(hex: tag.color) ?? .green
    }

    var body: some View {
        Button(
            action: { onTap?() },
            label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(tagColor)
                        .frame(width: 6, height: 6)

                    Text(tag.name)
                        .font(.caption)
                        .fontWeight(.medium)

                    if showCount && tag.fileCount > 0 {
                        Text("\(tag.fileCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background {
                    Capsule()
                        .fill(isSelected ?
                              tagColor.opacity(0.15) :
                              Color(.tertiarySystemBackground))
                        .overlay {
                            Capsule()
                                .stroke(isSelected ?
                                       tagColor :
                                       Color.clear, lineWidth: 1)
                        }
                }
            }
        )
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? tagColor : .primary)
    }
}

// MARK: - Tag Filter Bar
/// Yatay kaydırılabilir etiket filtre çubuğu
struct TagFilterBar: View {
    @ObservedObject var viewModel: LibraryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Başlık ve temizle butonu
            HStack {
                Label("Etiketler", systemImage: "tag.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                if !viewModel.selectedTags.isEmpty {
                    Button("Temizle") {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.clearTagFilters()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.indigo)
                }
            }

            // Etiket chip'leri
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.visibleTags) { tag in
                        TagChipView(
                            tag: tag,
                            isSelected: viewModel.selectedTags.contains(tag.id),
                            showCount: true
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                viewModel.toggleTagFilter(tag.id)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

#Preview {
    VStack {
        TagChipView(
            tag: Tag(name: "yapay zeka", color: "#22C55E", userId: "test"),
            isSelected: false,
            showCount: true
        )

        TagChipView(
            tag: Tag(name: "tıbbi", color: "#3B82F6", userId: "test"),
            isSelected: true,
            showCount: true
        )
    }
    .padding()
}
