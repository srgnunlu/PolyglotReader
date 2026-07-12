import SwiftUI

// MARK: - Compact Filter Bar
/// Tek satırda sıralama + etiket filtresi
/// Sol: Sıralama pill butonları (Tarih, İsim, Boyut)
/// Sağ: Etiket filtre butonu (aktif etiket sayısı badge)
struct CompactFilterBar: View {
    @ObservedObject var viewModel: LibraryViewModel
    @State private var showTagPopover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            // Sol taraf: Sıralama butonları (4 pill dar ekrana sığmayabilir → kaydırılabilir)
            ScrollView(.horizontal, showsIndicators: false) {
                sortingButtons
            }

            Spacer(minLength: 8)

            // Sağ taraf: İstatistik + favori + etiket filtre butonları
            LibraryStatsButton(viewModel: viewModel)

            favoriteFilterButton

            if !viewModel.visibleTags.isEmpty {
                tagFilterButton
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Sorting Buttons
    private var sortingButtons: some View {
        HStack(spacing: 6) {
            ForEach(LibraryViewModel.SortOption.allCases, id: \.self) { option in
                CompactSortPill(
                    title: option.rawValue,
                    isSelected: viewModel.sortBy == option,
                    sortOrder: viewModel.sortBy == option ? viewModel.sortOrder : nil
                ) {
                    DSHaptics.selection()
                    withAnimation(DSMotion.resolved(DSMotion.snappy, reduceMotion: reduceMotion)) {
                        viewModel.toggleSort(option)
                    }
                }
            }
        }
    }

    // MARK: - Favorite Filter Button
    private var favoriteFilterButton: some View {
        Button {
            DSHaptics.selection()
            withAnimation(DSMotion.resolved(DSMotion.snappy, reduceMotion: reduceMotion)) {
                viewModel.showFavoritesOnly.toggle()
            }
        } label: {
            Image(systemName: viewModel.showFavoritesOnly ? "star.fill" : "star")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(viewModel.showFavoritesOnly ?
                              Color.yellow.opacity(0.2) :
                              Color(.tertiarySystemBackground))
                        .overlay {
                            Capsule()
                                .stroke(viewModel.showFavoritesOnly ?
                                       Color.yellow.opacity(0.5) :
                                       Color.clear, lineWidth: 1)
                        }
                }
        }
        .buttonStyle(DSPressableButtonStyle())
        .foregroundStyle(viewModel.showFavoritesOnly ? Color.yellow : Color.secondary)
        .accessibilityLabel(
            viewModel.showFavoritesOnly
                ? "library.filter.favorites_off".localized
                : "library.filter.favorites_on".localized
        )
    }

    // MARK: - Tag Filter Button
    private var tagFilterButton: some View {
        Button {
            showTagPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tag.fill")
                    .font(.caption.weight(.medium))

                if !viewModel.selectedTags.isEmpty {
                    Text(String(viewModel.selectedTags.count))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Circle().fill(DSColor.brand))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(viewModel.selectedTags.isEmpty ?
                          Color(.tertiarySystemBackground) :
                          DSColor.brand.opacity(0.15))
                    .overlay {
                        Capsule()
                            .stroke(viewModel.selectedTags.isEmpty ?
                                   Color.clear :
                                   DSColor.brand.opacity(0.3), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(DSPressableButtonStyle())
        .foregroundStyle(viewModel.selectedTags.isEmpty ? Color.secondary : DSColor.brand)
        .popover(isPresented: $showTagPopover, arrowEdge: .bottom) {
            TagSelectionPopover(viewModel: viewModel)
        }
    }
}

// MARK: - Compact Sort Pill
/// Daha kompakt sıralama pill butonu
struct CompactSortPill: View {
    let title: String
    let isSelected: Bool
    var sortOrder: LibraryViewModel.SortOrder?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .medium)

                if let order = sortOrder {
                    Image(systemName: order == .ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                        .imageScale(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(isSelected ?
                          DSColor.brand.opacity(0.15) :
                          Color(.tertiarySystemBackground))
            }
            .overlay {
                Capsule()
                    .stroke(isSelected ? DSColor.brand.opacity(0.3) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(DSPressableButtonStyle())
        .foregroundStyle(isSelected ? DSColor.brand : .secondary)
    }
}

// MARK: - Tag Selection Popover
/// Etiket seçimi için popup
struct TagSelectionPopover: View {
    @ObservedObject var viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.visibleTags.isEmpty {
                    // Boş durum gösterimi - tüm platformlarda çalışır
                    VStack(spacing: 12) {
                        Image(systemName: "tag.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("library.tags.none".localized)
                            .font(.headline)
                        Text(NSLocalizedString("library.no_tagged_files", comment: "No tagged files in folder"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(viewModel.visibleTags) { tag in
                            TagSelectionRow(
                                tag: tag,
                                isSelected: viewModel.selectedTags.contains(tag.id)
                            ) {
                                DSHaptics.selection()
                                withAnimation(DSMotion.snappy) {
                                    viewModel.toggleTagFilter(tag.id)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("library.tags".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !viewModel.selectedTags.isEmpty {
                        Button("common.clear".localized) {
                            withAnimation {
                                viewModel.clearTagFilters()
                            }
                        }
                        .foregroundStyle(DSColor.brand)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.done".localized) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Tag Selection Row
/// Etiket seçim satırı
struct TagSelectionRow: View {
    let tag: Tag
    let isSelected: Bool
    var onTap: () -> Void

    private var tagColor: Color {
        Color(hex: tag.color) ?? .green
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Renk göstergesi
                Circle()
                    .fill(tagColor)
                    .frame(width: 10, height: 10)

                // Etiket adı
                Text(tag.name)
                    .font(.body)

                Spacer()

                // Dosya sayısı
                if tag.fileCount > 0 {
                    Text("\(tag.fileCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background {
                            Capsule()
                                .fill(Color(.tertiarySystemBackground))
                        }
                }

                // Seçim işareti
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? DSColor.brand : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

#Preview {
    VStack {
        CompactFilterBar(viewModel: LibraryViewModel())
    }
    .padding()
}
