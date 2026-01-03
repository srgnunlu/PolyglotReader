import SwiftUI

struct NotebookDashboardView: View {
    @ObservedObject var viewModel: NotebookViewModel
    let onSelectCategory: (NotebookCategory) -> Void
    let onSelectFile: (String) -> Void
    let onSelectAnnotation: (AnnotationWithFile) -> Void
    let onShowAllFiles: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - Stats Header
                StatsHeaderView(stats: viewModel.stats)

                // MARK: - Son Favoriler
                if !viewModel.recentFavorites.isEmpty {
                    RecentFavoritesSection(
                        favorites: viewModel.recentFavorites,
                        onSelectAnnotation: onSelectAnnotation,
                        onSeeAll: { onSelectCategory(.favorites) }
                    )
                }

                // MARK: - Kategoriler
                CategoriesSection(
                    viewModel: viewModel,
                    onSelectCategory: onSelectCategory
                )

                // MARK: - Dosyalar
                if !viewModel.fileAnnotationCounts.isEmpty {
                    FilesSection(
                        files: viewModel.fileAnnotationCounts,
                        onSelectFile: onSelectFile,
                        onShowAllFiles: onShowAllFiles
                    )
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Stats Header
private struct StatsHeaderView: View {
    let stats: AnnotationStats

    var body: some View {
        HStack(spacing: 16) {
            StatCard(
                title: "Toplam",
                value: "\(stats.total)",
                icon: "bookmark.fill",
                color: .indigo
            )
            StatCard(
                title: "Favoriler",
                value: "\(stats.favorites)",
                icon: "star.fill",
                color: .orange
            )
            StatCard(
                title: "Notlar",
                value: "\(stats.notes)",
                icon: "note.text",
                color: .purple
            )
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Recent Favorites Section
private struct RecentFavoritesSection: View {
    let favorites: [AnnotationWithFile]
    let onSelectAnnotation: (AnnotationWithFile) -> Void
    let onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Son Favoriler", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Spacer()

                Button("Tümünü Gör") {
                    onSeeAll()
                }
                .font(.subheadline)
                .foregroundStyle(.indigo)
            }

            VStack(spacing: 8) {
                ForEach(favorites) { annotation in
                    FavoriteAnnotationRow(annotation: annotation)
                        .onTapGesture {
                            onSelectAnnotation(annotation)
                        }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct FavoriteAnnotationRow: View {
    let annotation: AnnotationWithFile

    var body: some View {
        HStack(spacing: 12) {
            // Renk göstergesi
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(hex: annotation.color) ?? .yellow)
                .frame(width: 4, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(annotation.displayText)
                    .font(.subheadline)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text(annotation.fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text("s. \(annotation.pageNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Categories Section
private struct CategoriesSection: View {
    @ObservedObject var viewModel: NotebookViewModel
    let onSelectCategory: (NotebookCategory) -> Void

    // Gösterilecek ana kategoriler (files hariç)
    private let mainCategories: [NotebookCategory] = [
        .favorites, .notes, .aiNotes
    ]

    private let colorCategories: [NotebookCategory] = [
        .yellow, .green, .blue, .pink, .underlines
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Kategoriler")
                .font(.headline)
                .foregroundStyle(.primary)

            // Ana kategoriler (büyük kartlar)
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(mainCategories) { category in
                    CategoryCard(
                        category: category,
                        count: viewModel.countForCategory(category),
                        onTap: { onSelectCategory(category) }
                    )
                }
            }

            // Renk kategorileri (küçük kartlar)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(colorCategories) { category in
                        ColorCategoryChip(
                            category: category,
                            count: viewModel.countForCategory(category),
                            onTap: { onSelectCategory(category) }
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct CategoryCard: View {
    let category: NotebookCategory
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(hex: category.color)?.opacity(0.2) ?? Color.gray.opacity(0.2))
                        .frame(width: 44, height: 44)

                    Image(systemName: category.icon)
                        .font(.title3)
                        .foregroundStyle(Color(hex: category.color) ?? .gray)
                }

                Text("\(count)")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(category.rawValue)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct ColorCategoryChip: View {
    let category: NotebookCategory
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: category.color) ?? .gray)
                    .frame(width: 12, height: 12)

                Text(category.rawValue.replacingOccurrences(of: " Vurgular", with: ""))
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemFill))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Files Section
private struct FilesSection: View {
    let files: [FileAnnotationInfo]
    let onSelectFile: (String) -> Void
    let onShowAllFiles: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Dosyalar", systemImage: "doc.text.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)

                Spacer()

                Button("Tümünü Gör") {
                    onShowAllFiles()
                }
                .font(.subheadline)
                .foregroundStyle(.indigo)
            }

            VStack(spacing: 8) {
                ForEach(files.prefix(5)) { file in
                    FileAnnotationRow(file: file)
                        .onTapGesture {
                            onSelectFile(file.id)
                        }
                }

                if files.count > 5 {
                    Button {
                        onShowAllFiles()
                    } label: {
                        HStack {
                            Spacer()
                            Text("+ \(files.count - 5) dosya daha")
                                .font(.caption)
                                .foregroundStyle(.indigo)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.indigo)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct FileAnnotationRow: View {
    let file: FileAnnotationInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.fill")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text("\(file.count) not")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    NotebookDashboardView(
        viewModel: NotebookViewModel(),
        onSelectCategory: { _ in },
        onSelectFile: { _ in },
        onSelectAnnotation: { _ in },
        onShowAllFiles: {}
    )
}
