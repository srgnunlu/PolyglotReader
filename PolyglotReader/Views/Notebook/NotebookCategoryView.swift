import SwiftUI

struct NotebookCategoryView: View {
    @ObservedObject var viewModel: NotebookViewModel
    let category: NotebookCategory?
    let fileId: String?
    let onNavigateToAnnotation: (AnnotationWithFile) -> Void
    let onDismiss: () -> Void

    @State private var showingSortOptions = false

    private var title: String {
        if let category = category {
            return category.rawValue
        }
        if let fileId = fileId,
           let file = viewModel.fileAnnotationCounts.first(where: { $0.id == fileId }) {
            return file.name
        }
        return "Notlar"
    }

    private var subtitle: String {
        let count = viewModel.filteredAnnotations.count
        return "\(count) \(count == 1 ? "not" : "not")"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            CategoryHeader(
                title: title,
                subtitle: subtitle,
                category: category,
                sortOption: viewModel.sortOption,
                onDismiss: onDismiss,
                onShowSort: { showingSortOptions = true }
            )

            // Arama
            SearchBar(searchQuery: $viewModel.searchQuery)
                .padding(.horizontal)
                .padding(.bottom, 8)

            // Annotation Listesi
            if viewModel.filteredAnnotations.isEmpty {
                EmptyStateView(category: category)
            } else {
                AnnotationListView(
                    annotations: viewModel.filteredAnnotations,
                    viewModel: viewModel,
                    onNavigate: onNavigateToAnnotation
                )
            }
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            viewModel.selectedCategory = category
            viewModel.selectedFileId = fileId
        }
        .onDisappear {
            viewModel.selectedCategory = nil
            viewModel.selectedFileId = nil
        }
        .confirmationDialog("Sıralama", isPresented: $showingSortOptions) {
            ForEach(NotebookSortOption.allCases, id: \.self) { option in
                Button(option.rawValue) {
                    viewModel.sortOption = option
                }
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }
}

// MARK: - Category Header
private struct CategoryHeader: View {
    let title: String
    let subtitle: String
    let category: NotebookCategory?
    let sortOption: NotebookSortOption
    let onDismiss: () -> Void
    let onShowSort: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.medium))
                        Text("Geri")
                    }
                    .foregroundStyle(.indigo)
                }

                Spacer()

                Button(action: onShowSort) {
                    HStack(spacing: 4) {
                        Text(sortOption.rawValue)
                            .font(.subheadline)
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)

            HStack(spacing: 10) {
                // Kategori veya dosya ikonu
                if let category = category {
                    ZStack {
                        Circle()
                            .fill(Color(hex: category.color)?.opacity(0.2) ?? Color.gray.opacity(0.2))
                            .frame(width: 36, height: 36)

                        Image(systemName: category.icon)
                            .font(.subheadline)
                            .foregroundStyle(Color(hex: category.color) ?? .gray)
                    }
                } else {
                    // Dosya gösterimi
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 36, height: 36)

                        Image(systemName: "doc.text.fill")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 10)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Search Bar
private struct SearchBar: View {
    @Binding var searchQuery: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Ara...", text: $searchQuery)
                .textFieldStyle(.plain)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Empty State
private struct EmptyStateView: View {
    let category: NotebookCategory?

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("Bu kategoride henüz not yok")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let category = category {
                Text(emptyMessage(for: category))
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }

    private func emptyMessage(for category: NotebookCategory) -> String {
        switch category {
        case .favorites:
            return "Favori olarak isaretlediginiz notlar burada gorunecek"
        case .notes:
            return "Eklediginiz notlar burada listelenecek"
        case .aiNotes:
            return "AI tarafindan olusturulan notlar burada gorunecek"
        default:
            return "Vurgulariniz burada listelenecek"
        }
    }
}

// MARK: - Annotation List
private struct AnnotationListView: View {
    let annotations: [AnnotationWithFile]
    @ObservedObject var viewModel: NotebookViewModel
    let onNavigate: (AnnotationWithFile) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(annotations) { annotation in
                    AnnotationCard(
                        annotation: annotation,
                        onToggleFavorite: {
                            Task {
                                await viewModel.toggleFavorite(annotation.id)
                            }
                        },
                        onDelete: {
                            Task {
                                await viewModel.deleteAnnotation(annotation.id)
                            }
                        },
                        onNavigate: { onNavigate(annotation) }
                    )
                }
            }
            .padding()
        }
    }
}

// MARK: - Annotation Card
private struct AnnotationCard: View {
    let annotation: AnnotationWithFile
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    let onNavigate: () -> Void

    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                // Renk ve tip göstergesi
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: annotation.color) ?? .yellow)
                        .frame(width: 10, height: 10)

                    Text(annotation.colorName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if annotation.isAiGenerated {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                }

                Spacer()

                // Favori butonu
                Button(action: onToggleFavorite) {
                    Image(systemName: annotation.isFavorite ? "star.fill" : "star")
                        .font(.body)
                        .foregroundStyle(annotation.isFavorite ? .orange : .secondary)
                }

                // Tarih
                Text(annotation.shortDate)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Metin
            if let text = annotation.text, !text.isEmpty {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: annotation.color)?.opacity(0.15) ?? Color.yellow.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Not
            if let note = annotation.note, !note.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: annotation.isAiGenerated ? "sparkles" : "note.text")
                        .font(.caption)
                        .foregroundStyle(annotation.isAiGenerated ? .purple : .indigo)

                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            // Footer
            HStack {
                // Dosya bilgisi
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.caption2)
                    Text(annotation.fileName)
                        .font(.caption)
                    Text("• s. \(annotation.pageNumber)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)

                Spacer()

                // Aksiyonlar
                HStack(spacing: 16) {
                    Button {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.7))
                    }

                    Button(action: onNavigate) {
                        HStack(spacing: 4) {
                            Text("Git")
                                .font(.caption)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                        }
                        .foregroundStyle(.indigo)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .confirmationDialog(
            "Bu notu silmek istediginizden emin misiniz?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive, action: onDelete)
            Button("Vazgec", role: .cancel) {}
        }
    }
}

#Preview {
    NotebookCategoryView(
        viewModel: NotebookViewModel(),
        category: .favorites,
        fileId: nil,
        onNavigateToAnnotation: { _ in },
        onDismiss: {}
    )
}
