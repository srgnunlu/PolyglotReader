import Foundation

/// Anotasyon/vurgu dışa aktarma yardımcıları.
///
/// Notebook'taki anotasyonları akademik kullanım için Markdown veya düz metin
/// olarak biçimlendirir. Dosyaya göre gruplar, sayfa numarası ve renk/etiket
/// bilgisini korur; kullanıcı notlarını alıntının altına yerleştirir.
enum AnnotationExporter {
    enum Format: String, CaseIterable, Identifiable {
        case markdown
        case plainText

        var id: String { rawValue }

        var fileExtension: String {
            switch self {
            case .markdown: return "md"
            case .plainText: return "txt"
            }
        }

        var displayName: String {
            switch self {
            case .markdown: return "annotation.export.format.markdown".localized
            case .plainText: return "annotation.export.format.text".localized
            }
        }
    }

    /// Verilen anotasyonları seçilen formatta tek bir string'e dönüştürür.
    static func makeDocument(
        from annotations: [AnnotationWithFile],
        format: Format,
        title: String
    ) -> String {
        switch format {
        case .markdown: return makeMarkdown(from: annotations, title: title)
        case .plainText: return makePlainText(from: annotations, title: title)
        }
    }

    /// Dışa aktarılan içeriği geçici bir dosyaya yazıp paylaşım için URL döndürür.
    static func writeTemporaryFile(
        contents: String,
        format: Format,
        fileName: String
    ) throws -> URL {
        let safeName = sanitize(fileName)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName)
            .appendingPathExtension(format.fileExtension)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Markdown

    private static func makeMarkdown(from annotations: [AnnotationWithFile], title: String) -> String {
        var lines: [String] = ["# \(title)", ""]
        lines.append("> " + "annotation.export.subtitle".localized(with: annotations.count))
        lines.append("")

        for (fileName, items) in groupByFile(annotations) {
            lines.append("## \(fileName)")
            lines.append("")
            for item in items.sorted(by: { $0.pageNumber < $1.pageNumber }) {
                let page = "annotation.export.page".localized(with: item.pageNumber)
                let badge = "`\(item.colorName)` · \(page)"
                lines.append("- \(badge)")
                if let text = item.text, !text.isEmpty {
                    // Alıntıyı blok-quote olarak gir; çok satırlı seçimleri tek satıra indirge.
                    let quote = text.replacingOccurrences(of: "\n", with: " ")
                    lines.append("  > \(quote)")
                }
                if let note = item.note, !note.isEmpty {
                    lines.append("  - **\("annotation.export.note".localized):** \(note)")
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Plain Text

    private static func makePlainText(from annotations: [AnnotationWithFile], title: String) -> String {
        var lines: [String] = [title, String(repeating: "=", count: max(title.count, 3)), ""]
        lines.append("annotation.export.subtitle".localized(with: annotations.count))
        lines.append("")

        for (fileName, items) in groupByFile(annotations) {
            lines.append(fileName)
            lines.append(String(repeating: "-", count: max(fileName.count, 3)))
            for item in items.sorted(by: { $0.pageNumber < $1.pageNumber }) {
                let page = "annotation.export.page".localized(with: item.pageNumber)
                lines.append("[\(item.colorName) · \(page)]")
                if let text = item.text, !text.isEmpty {
                    lines.append("  \"\(text.replacingOccurrences(of: "\n", with: " "))\"")
                }
                if let note = item.note, !note.isEmpty {
                    lines.append("  \("annotation.export.note".localized): \(note)")
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Dosya adına göre gruplar; dosyalar alfabetik sıralanır, sıra deterministik kalır.
    private static func groupByFile(_ annotations: [AnnotationWithFile]) -> [(String, [AnnotationWithFile])] {
        let grouped = Dictionary(grouping: annotations) { $0.fileName }
        return grouped
            .map { ($0.key, $0.value) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    private static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "CorioScan-Notlar" : trimmed
    }
}
