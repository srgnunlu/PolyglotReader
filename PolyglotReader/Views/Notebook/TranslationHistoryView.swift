import SwiftUI

// MARK: - Translation History View
/// Defterim > Çeviriler: okuyucuda tamamlanan hızlı çevirilerin listesi —
/// akademik tekrar-görme (spaced review) için kaynak + çeviri yan yana.
struct TranslationHistoryView: View {
    @ObservedObject var viewModel: NotebookViewModel

    var body: some View {
        Group {
            if viewModel.translationHistory.isEmpty {
                emptyState
            } else {
                translationList
            }
        }
        .navigationTitle("notebook.category.translations".localized)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - List

    private var translationList: some View {
        List {
            ForEach(viewModel.translationHistory) { entry in
                TranslationHistoryRow(entry: entry)
            }
            .onDelete(perform: deleteEntries)
        }
        .listStyle(.insetGrouped)
    }

    private func deleteEntries(at offsets: IndexSet) {
        let entries = offsets.map { viewModel.translationHistory[$0] }
        Task {
            for entry in entries {
                await viewModel.deleteTranslation(entry.id)
            }
        }
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

private struct TranslationHistoryRow: View {
    let entry: TranslationHistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text(entry.sourceText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(entry.translatedText)
                .font(DSFont.translation)
                .foregroundStyle(.primary)
                .lineLimit(3)

            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "doc.text")
                    .font(DSFont.meta)

                Text(entry.fileName)
                    .font(DSFont.meta)
                    .lineLimit(1)

                Spacer()

                Text(entry.shortDate)
                    .font(DSFont.meta)
            }
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, DSSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.sourceText). \(entry.translatedText). \(entry.fileName)")
    }
}

#Preview {
    NavigationStack {
        TranslationHistoryView(viewModel: NotebookViewModel())
    }
}
