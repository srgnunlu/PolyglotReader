import SwiftUI
import PDFKit

/// PDF içinde hızlı gezinme: içindekiler (TOC) ve sayfa küçük-resim ızgarası.
/// Doküman bir ana hat (outline) taşıyorsa varsayılan sekme TOC olur, aksi halde
/// doğrudan küçük resimler gösterilir.
struct DocumentNavigatorView: View {
    let document: PDFDocument
    let currentPage: Int
    let onSelectPage: (Int) -> Void
    let onDismiss: () -> Void

    private enum Tab: Hashable { case outline, thumbnails }
    @State private var tab: Tab

    private let outlineEntries: [OutlineEntry]

    init(
        document: PDFDocument,
        currentPage: Int,
        onSelectPage: @escaping (Int) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.document = document
        self.currentPage = currentPage
        self.onSelectPage = onSelectPage
        self.onDismiss = onDismiss
        let entries = DocumentNavigatorView.buildOutline(from: document)
        self.outlineEntries = entries
        _tab = State(initialValue: entries.isEmpty ? .thumbnails : .outline)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !outlineEntries.isEmpty {
                    Picker("", selection: $tab) {
                        Text("navigator.tab.outline".localized).tag(Tab.outline)
                        Text("navigator.tab.pages".localized).tag(Tab.thumbnails)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                }

                if tab == .outline {
                    outlineList
                } else {
                    thumbnailGrid
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("navigator.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.close".localized) { onDismiss() }
                }
            }
        }
    }

    // MARK: - Outline (TOC)

    private var outlineList: some View {
        List(outlineEntries) { entry in
            Button {
                if let page = entry.pageIndex { select(page + 1) }
            } label: {
                HStack(spacing: 8) {
                    Text(entry.label)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer()
                    if let page = entry.pageIndex {
                        Text("\(page + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.leading, CGFloat(entry.depth) * 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(entry.pageIndex == nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                entry.pageIndex.map {
                    "navigator.outline_entry".localized(with: entry.label, $0 + 1)
                } ?? entry.label
            )
        }
        .listStyle(.plain)
    }

    // MARK: - Thumbnails

    private var thumbnailGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 90, maximum: 120), spacing: 16)],
                spacing: 16
            ) {
                ForEach(0..<document.pageCount, id: \.self) { index in
                    Button {
                        select(index + 1)
                    } label: {
                        PageThumbnailCell(
                            page: document.page(at: index),
                            pageNumber: index + 1,
                            isCurrent: index + 1 == currentPage
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("navigator.page".localized(with: index + 1))
                }
            }
            .padding()
        }
    }

    private func select(_ page: Int) {
        onSelectPage(page)
        onDismiss()
    }

    // MARK: - Outline Parsing

    struct OutlineEntry: Identifiable {
        let id = UUID()
        let label: String
        let pageIndex: Int?
        let depth: Int
    }

    /// PDF ana hattını (varsa) düz, derinlik bilgili bir listeye dönüştürür.
    private static func buildOutline(from document: PDFDocument) -> [OutlineEntry] {
        guard let root = document.outlineRoot else { return [] }
        var result: [OutlineEntry] = []
        func walk(_ node: PDFOutline, depth: Int) {
            for index in 0..<node.numberOfChildren {
                guard let child = node.child(at: index) else { continue }
                let label = child.label ?? ""
                if !label.isEmpty {
                    let pageIndex: Int? = {
                        guard let page = child.destination?.page else { return nil }
                        let index = document.index(for: page)
                        return (index >= 0 && index < document.pageCount) ? index : nil
                    }()
                    result.append(OutlineEntry(label: label, pageIndex: pageIndex, depth: depth))
                }
                walk(child, depth: depth + 1)
            }
        }
        walk(root, depth: 0)
        return result
    }
}

// MARK: - Page Thumbnail Cell

private struct PageThumbnailCell: View {
    let page: PDFPage?
    let pageNumber: Int
    let isCurrent: Bool

    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.secondarySystemGroupedBackground))

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    ProgressView()
                }
            }
            .frame(height: 130)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isCurrent ? Color.indigo : Color.black.opacity(0.1), lineWidth: isCurrent ? 2 : 0.5)
            }

            Text("\(pageNumber)")
                .font(.caption2)
                .fontWeight(isCurrent ? .bold : .regular)
                .foregroundStyle(isCurrent ? .indigo : .secondary)
                .monospacedDigit()
        }
        .task(id: pageNumber) {
            guard image == nil, let page else { return }
            // PDFKit küçük resmi ana iş parçacığında üretilir (PDFPage thread-safe değil).
            // LazyVGrid yalnızca görünür hücreleri oluşturduğu için maliyet sınırlı kalır.
            image = page.thumbnail(of: CGSize(width: 180, height: 260), for: .cropBox)
        }
    }
}
