import SwiftUI
import Combine

// MARK: - Trash Row Button
/// Kütüphane başlık bölümünde görünen "Son Silinenler" girişi; sheet'i kendi
/// içinde yönetir ki LibraryView'a state eklemesin.
struct TrashRowButton: View {
    @ObservedObject var viewModel: LibraryViewModel
    @State private var showTrash = false

    var body: some View {
        Button {
            showTrash = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                Text("library.trash.title".localized)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(viewModel.trashedFiles.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            }
        }
        .buttonStyle(DSPressableButtonStyle())
        .padding(.horizontal)
        .sheet(isPresented: $showTrash) {
            TrashView(viewModel: viewModel)
        }
        .accessibilityLabel("library.trash.accessibility".localized(with: viewModel.trashedFiles.count))
    }
}

// MARK: - Trash View
/// Silinen dosyalar: geri yükle veya kalıcı sil. 30 günden eski kayıtlar
/// otomatik temizlenir (loadTrash içinde).
struct TrashView: View {
    @ObservedObject var viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showEmptyConfirm = false
    @State private var fileToPurge: PDFDocumentMetadata?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.trashedFiles.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "trash.slash")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("library.trash.empty.title".localized)
                            .font(.headline)
                        Text("library.trash.empty.subtitle".localized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(viewModel.trashedFiles) { file in
                            trashRow(file)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("library.trash.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close".localized) { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    if !viewModel.trashedFiles.isEmpty {
                        Button("library.trash.empty_action".localized, role: .destructive) {
                            showEmptyConfirm = true
                        }
                    }
                }
            }
            .confirmationDialog(
                "library.trash.empty_confirm".localized(with: viewModel.trashedFiles.count),
                isPresented: $showEmptyConfirm,
                titleVisibility: .visible
            ) {
                Button("library.trash.delete_all".localized, role: .destructive) {
                    Task { await viewModel.emptyTrash() }
                }
                Button("common.cancel".localized, role: .cancel) {}
            } message: {
                Text("common.irreversible".localized)
            }
            .confirmationDialog(
                "library.trash.purge_confirm".localized(with: fileToPurge?.name ?? ""),
                isPresented: Binding(
                    get: { fileToPurge != nil },
                    set: { if !$0 { fileToPurge = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("library.trash.purge".localized, role: .destructive) {
                    if let file = fileToPurge {
                        Task { await viewModel.permanentlyDeleteFile(file) }
                    }
                    fileToPurge = nil
                }
                Button("common.cancel".localized, role: .cancel) { fileToPurge = nil }
            } message: {
                Text("common.irreversible".localized)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func trashRow(_ file: PDFDocumentMetadata) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.subheadline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(file.formattedSize)
                    if let deletedAt = file.deletedAt {
                        Circle().fill(.secondary).frame(width: 3, height: 3)
                        Text(deletedAt, format: .relative(presentation: .named))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task { await viewModel.restoreFromTrash(file) }
            } label: {
                Label("library.trash.restore".localized, systemImage: "arrow.uturn.backward")
            }
            .tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                fileToPurge = file
            } label: {
                Label("library.trash.purge".localized, systemImage: "trash.slash")
            }
        }
        .contextMenu {
            Button {
                Task { await viewModel.restoreFromTrash(file) }
            } label: {
                Label("library.trash.restore".localized, systemImage: "arrow.uturn.backward")
            }

            Button(role: .destructive) {
                fileToPurge = file
            } label: {
                Label("library.trash.purge".localized, systemImage: "trash.slash")
            }
        }
    }
}
