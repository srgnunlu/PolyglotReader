import SwiftUI

// MARK: - Translation History View
/// Defterim > Çeviriler: okuyucuda tamamlanan hızlı çevirilerin listesi —
/// akademik tekrar-görme (spaced review) için kaynak + çeviri yan yana.
/// Satıra dokununca tam metin açılır; dosyaya göre gruplama, tarih sıralama
/// ve arama ile kalabalık geçmişte gezinmek kolaylaşır.
struct TranslationHistoryView: View {
    @ObservedObject var viewModel: NotebookViewModel

    @State private var searchText = ""
    @State private var expandedIds: Set<String> = []
    // Tercihler oturumlar arası korunur — kullanıcı düzenini her seferinde kurmasın.
    @AppStorage("translationHistorySortNewest") private var sortNewestFirst = true
    @AppStorage("translationHistoryGroupByFile") private var groupByFile = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if viewModel.translationHistory.isEmpty {
                emptyState
            } else {
                translationList
                    .searchable(
                        text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "notebook.translations.search".localized
                    )
            }
        }
        .navigationTitle("notebook.category.translations".localized)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !viewModel.translationHistory.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    optionsMenu
                }
            }
        }
    }

    // MARK: - Filtering / Sorting / Grouping

    private var filteredEntries: [TranslationHistoryEntry] {
        var result = viewModel.translationHistory

        if !searchText.isEmpty {
            result = result.filter { entry in
                entry.sourceText.localizedCaseInsensitiveContains(searchText) ||
                entry.translatedText.localizedCaseInsensitiveContains(searchText) ||
                entry.fileName.localizedCaseInsensitiveContains(searchText)
            }
        }

        result.sort {
            sortNewestFirst ? $0.createdAt > $1.createdAt : $0.createdAt < $1.createdAt
        }
        return result
    }

    /// Dosyaya göre gruplar; grupların sırası içlerindeki ilk (en güncel/en eski)
    /// çeviriye göre belirlenir — sıralama tercihiyle tutarlı kalır.
    private var groupedEntries: [(fileId: String, fileName: String, entries: [TranslationHistoryEntry])] {
        Dictionary(grouping: filteredEntries, by: { $0.fileId })
            .map { fileId, entries in
                (fileId: fileId, fileName: entries.first?.fileName ?? "", entries: entries)
            }
            .sorted { lhs, rhs in
                guard let left = lhs.entries.first?.createdAt,
                      let right = rhs.entries.first?.createdAt else { return false }
                return sortNewestFirst ? left > right : left < right
            }
    }

    // MARK: - Options Menu

    private var optionsMenu: some View {
        Menu {
            Picker("notebook.translations.sort".localized, selection: $sortNewestFirst) {
                Label("notebook.translations.sort.newest".localized, systemImage: "arrow.down")
                    .tag(true)
                Label("notebook.translations.sort.oldest".localized, systemImage: "arrow.up")
                    .tag(false)
            }

            Divider()

            Toggle(isOn: $groupByFile) {
                Label("notebook.translations.group_by_file".localized, systemImage: "folder")
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(DSColor.brand)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("notebook.translations.options".localized)
    }

    // MARK: - List

    private var translationList: some View {
        List {
            if filteredEntries.isEmpty {
                noSearchResults
            } else if groupByFile {
                ForEach(groupedEntries, id: \.fileId) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            row(for: entry, showsFileName: false)
                        }
                    } header: {
                        Label(group.fileName, systemImage: "doc.text")
                            .font(DSFont.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                }
            } else {
                ForEach(filteredEntries) { entry in
                    row(for: entry, showsFileName: true)
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(
            reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85),
            value: expandedIds
        )
    }

    private func row(for entry: TranslationHistoryEntry, showsFileName: Bool) -> some View {
        TranslationHistoryRow(
            entry: entry,
            isExpanded: expandedIds.contains(entry.id),
            showsFileName: showsFileName
        ) {
            toggleExpansion(for: entry.id)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await viewModel.deleteTranslation(entry.id) }
            } label: {
                Label("common.delete".localized, systemImage: "trash")
            }
        }
    }

    private func toggleExpansion(for id: String) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
            if expandedIds.contains(id) {
                expandedIds.remove(id)
            } else {
                expandedIds.insert(id)
            }
        }
    }

    // MARK: - No Search Results

    private var noSearchResults: some View {
        VStack(spacing: DSSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.tertiary)

            Text("notebook.translations.empty.search".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xl)
        .listRowBackground(Color.clear)
    }

    // MARK: - Empty State

    /// Bu özelliğe özgü boş durum: çevirinin NASIL biriktiğini anlatır.
    private var emptyState: some View {
        VStack(spacing: DSSpacing.lg) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [DSColor.brand.opacity(0.1), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "character.bubble")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(DSColor.brandGradient)
            }
            .accessibilityHidden(true)

            VStack(spacing: DSSpacing.xs) {
                Text("notebook.translations.empty.title".localized)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)

                Text("notebook.translations.empty.subtitle".localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DSSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Translation History Row
/// Kapalıyken kısa önizleme (kaynak 1, çeviri 2 satır); dokununca tam metin
/// açılır. Chevron dönerek durumu belli eder.
private struct TranslationHistoryRow: View {
    let entry: TranslationHistoryEntry
    let isExpanded: Bool
    let showsFileName: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack(alignment: .top, spacing: DSSpacing.xs) {
                    Text(entry.sourceText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 1)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: DSSpacing.xs)

                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }

                Text(entry.translatedText)
                    .font(DSFont.translation)
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: DSSpacing.xxs) {
                    if showsFileName {
                        Image(systemName: "doc.text")
                            .font(DSFont.meta)

                        Text(entry.fileName)
                            .font(DSFont.meta)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(entry.shortDate)
                        .font(DSFont.meta)
                }
                .foregroundStyle(.tertiary)
            }
            .padding(.vertical, DSSpacing.xxs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.sourceText). \(entry.translatedText). \(entry.fileName)")
        .accessibilityHint(
            isExpanded
                ? "notebook.translations.collapse.hint".localized
                : "notebook.translations.expand.hint".localized
        )
        .accessibilityAddTraits(.isButton)
    }
}

#Preview {
    NavigationStack {
        TranslationHistoryView(viewModel: NotebookViewModel())
    }
}
