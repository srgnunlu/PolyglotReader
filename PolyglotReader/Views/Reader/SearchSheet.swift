import SwiftUI

// MARK: - Search Sheet
struct SearchSheet: View {
    @ObservedObject var viewModel: PDFReaderViewModel
    /// Bir sonuca atlanınca okuyucudaki sarı parıltıyı tetikler
    /// (atıf navigasyonuyla aynı geri bildirim dili).
    var onJumpToResult: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                searchInput

                if !viewModel.searchResults.isEmpty {
                    resultsHeader
                    resultsList
                } else if viewModel.hasSearched {
                    emptyState(
                        icon: "doc.text.magnifyingglass",
                        message: "reader.search.no_results".localized
                    )
                } else {
                    emptyState(
                        icon: "magnifyingglass",
                        message: "reader.search.prompt".localized
                    )
                }
            }
            .padding(.top, 8)
            .navigationTitle("reader.search.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.close".localized) {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Search Input

    private var searchInput: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("reader.search.placeholder".localized, text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit {
                    viewModel.search()
                }

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("reader.search.clear".localized)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Results Header (count + prev/next)

    private var resultsCountText: String {
        "reader.search.result_count".localized(with: viewModel.searchResults.count)
    }

    private var resultPositionText: String {
        "\(viewModel.currentSearchIndex + 1) / \(viewModel.searchResults.count)"
    }

    private var resultsHeader: some View {
        HStack {
            Text(resultsCountText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                viewModel.previousSearchResult()
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("reader.search.previous".localized)

            Text(resultPositionText)
                .font(.caption)
                .monospacedDigit()
                .contentTransition(.numericText())
                .dsAnimation(DSMotion.snappy, value: viewModel.currentSearchIndex)

            Button {
                viewModel.nextSearchResult()
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("reader.search.next".localized)
        }
        .padding(.horizontal)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.searchResults.enumerated()), id: \.offset) { index, result in
                    Button {
                        viewModel.selectSearchResult(at: index)
                        // Satıra dokunmak "bu sonuca git" demektir: sheet
                        // kapanır, okuyucuda parıltı yanar. Prev/next ile
                        // gezinme ise sheet içinde kalır.
                        onJumpToResult?()
                        dismiss()
                    } label: {
                        searchResultRow(index: index, result: result)
                    }
                    .buttonStyle(.plain)
                    // Kenardan girerken kademeli belirme (kütüphane kartlarıyla aynı dil).
                    .scrollTransition(.interactive) { [reduceMotion] view, phase in
                        view
                            .opacity(!reduceMotion && !phase.isIdentity ? 0.55 : 1)
                            .scaleEffect(!reduceMotion && !phase.isIdentity ? 0.97 : 1)
                    }

                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
    }

    private func searchResultRow(index: Int, result: PDFSearchResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                Image(systemName: "doc.text")
                    .font(.caption)
                    .foregroundStyle(DSColor.brand)
                Text("\(result.pageNumber)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(DSColor.brand)
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("navigator.page".localized(with: result.pageNumber))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(highlightedSnippet(result.snippet.isEmpty ? viewModel.searchQuery : result.snippet))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            if index == viewModel.currentSearchIndex {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(DSColor.brand)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(index == viewModel.currentSearchIndex ? DSColor.brand.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\("navigator.page".localized(with: result.pageNumber)). \(result.snippet)")
    }

    /// Snippet içindeki tüm sorgu eşleşmelerini vurgu sarısıyla işaretler.
    /// Sarı zemin açık renk olduğundan eşleşme metni her iki temada da
    /// siyaha sabitlenir (PDF üzerindeki vurgularla aynı mantık).
    private func highlightedSnippet(_ snippet: String) -> AttributedString {
        var attributed = AttributedString(snippet)
        let query = viewModel.searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return attributed }

        var searchStart = snippet.startIndex
        while let match = snippet.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            range: searchStart..<snippet.endIndex
        ) {
            if let attributedRange = Range(match, in: attributed) {
                attributed[attributedRange].backgroundColor = DSColor.Highlight.yellow.color
                attributed[attributedRange].foregroundColor = Color.black
            }
            searchStart = match.upperBound
        }

        return attributed
    }

    @ViewBuilder
    private func emptyState(icon: String, message: String) -> some View {
        Spacer()
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.secondary.opacity(0.6))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        Spacer()
    }
}
