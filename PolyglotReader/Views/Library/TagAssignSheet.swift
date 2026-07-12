import SwiftUI
import Combine

// MARK: - Bulk Tag Button
/// Seçim modundaki alt çubuğun etiket butonu; sheet'ini kendi içinde yönetir.
struct BulkTagButton: View {
    @ObservedObject var viewModel: LibraryViewModel
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Image(systemName: "tag")
                .font(.system(size: 18, weight: .semibold))
                .frame(minWidth: 44, minHeight: 44)
        }
        .disabled(viewModel.selectedCount == 0 || viewModel.allTags.isEmpty)
        .accessibilityLabel("library.selection.add_tags".localized)
        .sheet(isPresented: $showSheet) {
            TagAssignSheet(viewModel: viewModel)
        }
    }
}

// MARK: - Tag Assign Sheet
/// Toplu etiketleme: mevcut etiketlerden çoklu seçim → seçili dosyaların
/// hepsine eklenir (var olan etiketler korunur, kaldırma yapmaz).
struct TagAssignSheet: View {
    @ObservedObject var viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTagIds: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(viewModel.allTags) { tag in
                        TagSelectionRow(
                            tag: tag,
                            isSelected: selectedTagIds.contains(tag.id)
                        ) {
                            DSHaptics.selection()
                            if selectedTagIds.contains(tag.id) {
                                selectedTagIds.remove(tag.id)
                            } else {
                                selectedTagIds.insert(tag.id)
                            }
                        }
                    }
                } footer: {
                    Text("library.tags.assign_footer".localized(with: viewModel.selectedCount))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("library.tags.assign_title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel".localized) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.apply".localized) {
                        let tagIds = Array(selectedTagIds)
                        Task { await viewModel.assignTagsToSelectedFiles(tagIds: tagIds) }
                        dismiss()
                    }
                    .disabled(selectedTagIds.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
