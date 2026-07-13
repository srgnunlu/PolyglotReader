import Foundation

/// Normalizes model-authored HTML fragments into the Markdown dialect rendered
/// by `MarkdownView`. This prevents literal `<br>`/tag leakage while retaining
/// useful emphasis, lists, headings, and tables.
nonisolated enum AIResponseFormatter {
    static func markdown(from source: String) -> String {
        var result = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        result = replacing(pattern: #"(?is)<(script|style)\b[^>]*>.*?</\1\s*>"#, in: result, with: "")
        result = replacingHTMLTables(in: result)
        result = replacing(pattern: #"(?i)<br\s*/?>"#, in: result, with: "\n")

        for level in 1...6 {
            result = replacingBlockTag(
                "h\(level)",
                in: result,
                prefix: String(repeating: "#", count: level) + " "
            )
        }

        result = replacingBlockTag("blockquote", in: result, prefix: "> ")
        result = replacingBlockTag("li", in: result, prefix: "- ")
        result = replacing(pattern: #"(?i)</?(ul|ol)\b[^>]*>"#, in: result, with: "\n")
        result = replacing(pattern: #"(?i)<(p|div|section)\b[^>]*>"#, in: result, with: "")
        result = replacing(pattern: #"(?i)</(p|div|section)\s*>"#, in: result, with: "\n\n")

        result = replacing(pattern: #"(?is)<(strong|b)\b[^>]*>(.*?)</\1\s*>"#, in: result, with: "**$2**")
        result = replacing(pattern: #"(?is)<(em|i)\b[^>]*>(.*?)</\1\s*>"#, in: result, with: "*$2*")
        result = replacing(pattern: #"(?is)<code\b[^>]*>(.*?)</code\s*>"#, in: result, with: "`$1`")
        result = replacing(
            pattern: #"(?is)<a\b[^>]*href\s*=\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a\s*>"#,
            in: result,
            with: "[$2]($1)"
        )
        result = replacing(pattern: #"(?is)<[^>]+>"#, in: result, with: "")
        result = decodeEntities(in: result)
        return normalizeWhitespace(in: result)
    }

    // MARK: - Tables

    private static func replacingHTMLTables(in source: String) -> String {
        replacingMatches(pattern: #"(?is)<table\b[^>]*>.*?</table\s*>"#, in: source) { tableHTML in
            markdownTable(from: tableHTML) ?? ""
        }
    }

    private static func markdownTable(from html: String) -> String? {
        let rowHTML = matches(pattern: #"(?is)<tr\b[^>]*>(.*?)</tr\s*>"#, in: html, captureGroup: 1)
        let rows = rowHTML.compactMap { row -> [String]? in
            let cells = matches(
                pattern: #"(?is)<t[hd]\b[^>]*>(.*?)</t[hd]\s*>"#,
                in: row,
                captureGroup: 1
            ).map(tableCellText)
            return cells.isEmpty ? nil : cells
        }
        guard let firstRow = rows.first, !firstRow.isEmpty else { return nil }

        let columnCount = rows.map(\.count).max() ?? firstRow.count
        let paddedRows = rows.map { row in
            row + Array(repeating: "", count: max(columnCount - row.count, 0))
        }
        guard let header = paddedRows.first else { return nil }

        var lines = [markdownRow(header)]
        lines.append(markdownRow(Array(repeating: "---", count: columnCount)))
        lines.append(contentsOf: paddedRows.dropFirst().map(markdownRow))
        return "\n\n" + lines.joined(separator: "\n") + "\n\n"
    }

    private static func tableCellText(_ html: String) -> String {
        var value = replacing(pattern: #"(?i)<br\s*/?>"#, in: html, with: " ")
        value = replacing(pattern: #"(?is)<(strong|b)\b[^>]*>(.*?)</\1\s*>"#, in: value, with: "**$2**")
        value = replacing(pattern: #"(?is)<(em|i)\b[^>]*>(.*?)</\1\s*>"#, in: value, with: "*$2*")
        value = replacing(pattern: #"(?is)<code\b[^>]*>(.*?)</code\s*>"#, in: value, with: "`$1`")
        value = replacing(pattern: #"(?is)<[^>]+>"#, in: value, with: "")
        value = decodeEntities(in: value)
        value = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return value.replacingOccurrences(of: "|", with: #"\|"#)
    }

    private static func markdownRow(_ cells: [String]) -> String {
        "| " + cells.joined(separator: " | ") + " |"
    }

    // MARK: - Regex Helpers

    private static func replacingBlockTag(_ tag: String, in source: String, prefix: String) -> String {
        replacingMatches(pattern: "(?is)<\(tag)\\b[^>]*>(.*?)</\(tag)\\s*>", in: source) { html in
            let content = matches(
                pattern: "(?is)<\(tag)\\b[^>]*>(.*?)</\(tag)\\s*>",
                in: html,
                captureGroup: 1
            ).first ?? ""
            return "\n\n" + prefix + content + "\n\n"
        }
    }

    private static func replacing(pattern: String, in source: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..., in: source)
        return regex.stringByReplacingMatches(in: source, range: range, withTemplate: template)
    }

    private static func replacingMatches(
        pattern: String,
        in source: String,
        transform: (String) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return source }
        var result = source
        let range = NSRange(source.startIndex..., in: source)
        for match in regex.matches(in: source, range: range).reversed() {
            guard let swiftRange = Range(match.range, in: result) else { continue }
            let replacement = transform(String(result[swiftRange]))
            result.replaceSubrange(swiftRange, with: replacement)
        }
        return result
    }

    private static func matches(pattern: String, in source: String, captureGroup: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard captureGroup < match.numberOfRanges,
                  let swiftRange = Range(match.range(at: captureGroup), in: source) else { return nil }
            return String(source[swiftRange])
        }
    }

    // MARK: - Cleanup

    private static func decodeEntities(in source: String) -> String {
        var result = source
        let entities = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">"
        ]
        for (entity, value) in entities {
            result = result.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }
        return result
    }

    private static func normalizeWhitespace(in source: String) -> String {
        var result = replacing(pattern: #"[ \t]+\n"#, in: source, with: "\n")
        result = replacing(pattern: #"\n[ \t]+"#, in: result, with: "\n")
        result = replacing(pattern: #"\n{3,}"#, in: result, with: "\n\n")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
