import SwiftUI

// MARK: - Search Sheet
struct SearchSheet: View {
    @ObservedObject var viewModel: PDFReaderViewModel
    @Environment(\.dismiss) private var dismiss

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
                        message: "Sonuç bulunamadı"
                    )
                } else {
                    emptyState(
                        icon: "magnifyingglass",
                        message: "Dokümanda aramak için bir kelime yazın"
                    )
                }
            }
            .padding(.top, 8)
            .navigationTitle("Dokümanda Ara")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") {
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

            TextField("Ara...", text: $viewModel.searchQuery)
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
                .accessibilityLabel("Aramayı temizle")
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    // MARK: - Results Header (count + prev/next)

    private var resultsCountText: String {
        "\(viewModel.searchResults.count) sonuç"
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
            .accessibilityLabel("Önceki sonuç")

            Text(resultPositionText)
                .font(.caption)
                .monospacedDigit()

            Button {
                viewModel.nextSearchResult()
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Sonraki sonuç")
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
                    } label: {
                        searchResultRow(index: index, result: result)
                    }
                    .buttonStyle(.plain)

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
                    .foregroundStyle(.indigo)
                Text("\(result.pageNumber)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.indigo)
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Sayfa \(result.pageNumber)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(result.snippet.isEmpty ? viewModel.searchQuery : result.snippet)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            if index == viewModel.currentSearchIndex {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.indigo)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(index == viewModel.currentSearchIndex ? Color.indigo.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sayfa \(result.pageNumber). \(result.snippet)")
    }

    @ViewBuilder
    private func emptyState(icon: String, message: String) -> some View {
        Spacer()
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
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
