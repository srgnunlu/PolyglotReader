import SwiftUI

/// Tüm anotasyonları Markdown veya düz metin olarak dışa aktarma sayfası.
/// Akademik kullanıcının vurgularını literatür özeti olarak dışarı alması için.
struct AnnotationExportView: View {
    let annotations: [AnnotationWithFile]
    let onDismiss: () -> Void

    @State private var format: AnnotationExporter.Format = .markdown
    @State private var exportURL: URL?
    @State private var preview: String = ""

    private var exportTitle: String { "annotation.export.title".localized }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("annotation.export.format".localized, selection: $format) {
                    ForEach(AnnotationExporter.Format.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                ScrollView {
                    Text(preview)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("annotation.export.share".localized, systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .frame(minHeight: 44)
                            .background(Color.indigo)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal)
                    .accessibilityIdentifier("share_annotations_button")
                }
            }
            .padding(.vertical)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(exportTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.close".localized) { onDismiss() }
                }
            }
        }
        .onAppear { regenerate() }
        .onChange(of: format) { _ in regenerate() }
    }

    /// Seçili formatta içeriği üretir, önizlemeyi günceller ve paylaşım dosyasını yazar.
    private func regenerate() {
        let contents = AnnotationExporter.makeDocument(
            from: annotations,
            format: format,
            title: exportTitle
        )
        preview = contents
        exportURL = try? AnnotationExporter.writeTemporaryFile(
            contents: contents,
            format: format,
            fileName: exportTitle
        )
    }
}
