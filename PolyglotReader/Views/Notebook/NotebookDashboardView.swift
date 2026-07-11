import SwiftUI

struct NotebookDashboardView: View {
    @ObservedObject var viewModel: NotebookViewModel
    let onSelectCategory: (NotebookCategory) -> Void
    let onSelectFile: (String) -> Void
    let onSelectAnnotation: (AnnotationWithFile) -> Void
    let onShowAllFiles: () -> Void
    let onSelectTranslations: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: DSSpacing.lg) {
                // MARK: - Stats Header
                StatsHeaderView(stats: viewModel.stats)

                // MARK: - Son Favoriler
                if !viewModel.recentFavorites.isEmpty {
                    RecentFavoritesSection(
                        favorites: viewModel.recentFavorites,
                        onSelectAnnotation: onSelectAnnotation
                    ) { onSelectCategory(.favorites) }
                }

                // MARK: - Kategoriler
                CategoriesSection(
                    viewModel: viewModel,
                    onSelectCategory: onSelectCategory,
                    onSelectTranslations: onSelectTranslations
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
        HStack(spacing: DSSpacing.sm) {
            StatCard(
                title: "Toplam",
                value: "\(stats.total)",
                icon: "bookmark.fill",
                color: DSColor.brand
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
                icon: "square.and.pencil",
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
        VStack(spacing: DSSpacing.xs) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.14))
                    .frame(width: 38, height: 38)

                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
            }
            .accessibilityHidden(true)

            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            Text(title)
                .font(DSFont.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.md)
        .background(DSColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: DSRadius.medium)
                .stroke(color.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

// MARK: - Recent Favorites Section
private struct RecentFavoritesSection: View {
    let favorites: [AnnotationWithFile]
    let onSelectAnnotation: (AnnotationWithFile) -> Void
    let onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Label("Son Favoriler", systemImage: "star.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Spacer()

                Button("Tümünü Gör") {
                    onSeeAll()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DSColor.brand)
            }

            VStack(spacing: DSSpacing.xs) {
                ForEach(favorites) { annotation in
                    Button {
                        onSelectAnnotation(annotation)
                    } label: {
                        FavoriteAnnotationRow(annotation: annotation)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(DSColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.medium))
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
        .padding(.vertical, DSSpacing.xs)
        .padding(.horizontal, DSSpacing.sm)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.small))
        .contentShape(RoundedRectangle(cornerRadius: DSRadius.small))
    }
}

// MARK: - Categories Section
private struct CategoriesSection: View {
    @ObservedObject var viewModel: NotebookViewModel
    let onSelectCategory: (NotebookCategory) -> Void
    let onSelectTranslations: () -> Void

    // Gösterilecek ana kategoriler (files hariç). AI Notları kullanılmadığı
    // için dashboard'dan kaldırıldı — veri modeli ve backend dokunulmadan durur.
    private let mainCategories: [NotebookCategory] = [
        .favorites, .notes
    ]

    private let colorCategories: [NotebookCategory] = [
        .yellow, .green, .blue, .pink, .underlines
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Label("Kategoriler", systemImage: "square.grid.2x2.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            // Ana kategoriler (büyük kartlar) + Çeviriler
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: DSSpacing.sm) {
                ForEach(mainCategories) { category in
                    CategoryCard(
                        icon: category.icon,
                        colorHex: category.color,
                        title: category.rawValue,
                        count: viewModel.countForCategory(category)
                    ) { onSelectCategory(category) }
                }

                // Çeviri geçmişi — annotation değil, kendi listesine gider.
                CategoryCard(
                    icon: "character.bubble.fill",
                    colorHex: "#14B8A6",
                    title: "notebook.category.translations".localized,
                    count: viewModel.translationHistory.count,
                    onTap: onSelectTranslations
                )
            }

            // Renk kategorileri (küçük kartlar)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.xs) {
                    ForEach(colorCategories) { category in
                        ColorCategoryChip(
                            category: category,
                            count: viewModel.countForCategory(category)
                        ) { onSelectCategory(category) }
                    }
                }
            }
        }
        .padding()
        .background(DSColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.medium))
    }
}

private struct CategoryCard: View {
    let icon: String
    let colorHex: String
    let title: String
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: DSSpacing.xs) {
                ZStack {
                    Circle()
                        .fill(Color(hex: colorHex)?.opacity(0.16) ?? Color.gray.opacity(0.16))
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color(hex: colorHex) ?? .gray)
                }
                .accessibilityHidden(true)

                Text("\(count)")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())

                Text(title)
                    .font(DSFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.sm)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.small))
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.small)
                    .stroke((Color(hex: colorHex) ?? .gray).opacity(0.10), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: DSRadius.small))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count)")
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
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemFill))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.rawValue), \(count)")
    }
}

// MARK: - Files Section
private struct FilesSection: View {
    let files: [FileAnnotationInfo]
    let onSelectFile: (String) -> Void
    let onShowAllFiles: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Label("Dosyalar", systemImage: "folder.fill")
                    .font(.headline)
                    .foregroundStyle(DSColor.brand)

                Spacer()

                Button("Tümünü Gör") {
                    onShowAllFiles()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DSColor.brand)
            }

            VStack(spacing: DSSpacing.xs) {
                ForEach(files.prefix(5)) { file in
                    Button {
                        onSelectFile(file.id)
                    } label: {
                        FileAnnotationRow(file: file)
                    }
                    .buttonStyle(.plain)
                }

                if files.count > 5 {
                    Button {
                        onShowAllFiles()
                    } label: {
                        HStack {
                            Spacer()
                            Text(String(
                                format: NSLocalizedString(
                                    "notebook.more_files",
                                    comment: "More files button"
                                ),
                                files.count - 5
                            ))
                                .font(.caption)
                                .foregroundStyle(.indigo)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.indigo)
                            Spacer()
                        }
                        .padding(.vertical, DSSpacing.xs)
                        .background(Color(.tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: DSRadius.small))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(DSColor.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.medium))
    }
}

private struct FileAnnotationRow: View {
    let file: FileAnnotationInfo

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "doc.text.fill")
                .font(.body.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DSColor.brand)
                .frame(width: 36, height: 36)
                .background(DSColor.brand.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.small - 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                Text("\(file.count) not")
                    .font(DSFont.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, DSSpacing.sm)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.small))
        .contentShape(RoundedRectangle(cornerRadius: DSRadius.small))
    }
}

#Preview {
    NotebookDashboardView(
        viewModel: NotebookViewModel(),
        onSelectCategory: { _ in },
        onSelectFile: { _ in },
        onSelectAnnotation: { _ in },
        onShowAllFiles: {},
        onSelectTranslations: {}
    )
}
