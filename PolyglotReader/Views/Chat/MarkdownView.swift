import SwiftUI

// swiftlint:disable shorthand_operator
// MARK: - Professional Markdown Renderer

struct MarkdownView: View {
    let text: String
    let onNavigateToPage: (Int) -> Void

    /// Tablo sütun genişliği Dynamic Type ile ölçeklenir — sabit 130pt büyük
    /// yazı boyutlarında hücre metnini kırpıyordu.
    @ScaledMetric(relativeTo: .caption) private var tableColumnWidth: CGFloat = 130

    // Cached parsed blocks to avoid re-parsing on every render
    private var parsedBlocks: [BlockType] {
        Self.cachedParse(text)
    }

    // Simple in-memory cache for parsed markdown. Keyed by the full text —
    // hashValue keys could silently collide and render the wrong message.
    private static var parseCache: [String: [BlockType]] = [:]
    private static let maxCacheSize = 50

    private static func cachedParse(_ text: String) -> [BlockType] {
        let key = text

        if let cached = parseCache[key] {
            return cached
        }

        // Parse and cache
        let blocks = parseBlocksInternal(linkifyPageCitations(text))
        
        // Evict old entries if cache is too large
        if parseCache.count >= maxCacheSize {
            parseCache.removeAll()
        }
        
        parseCache[key] = blocks
        return blocks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parsedBlocks, id: \.id) { block in
                renderBlock(block)
            }
        }
        // Intercept taps on `[label](jump:N)` citation links and navigate the
        // reader to the cited page instead of opening a URL in the browser.
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == Self.jumpLinkScheme,
                  let host = url.host,
                  let page = Int(host) else {
                return .systemAction
            }
            onNavigateToPage(page)
            return .handled
        })
    }

    /// Custom URL scheme used for in-document page citations.
    static let jumpLinkScheme = "coriojump"

    /// Model her zaman [Sayfa X](jump:X) formatına uymuyor; düz metin kalan
    /// "Sayfa 12" / "Page 12" atıflarını tıklanabilir jump linklerine çevirir.
    /// Zaten link olan atıflara ("[" ile başlayanlara) dokunmaz.
    private static let pageCitationRegex = try? NSRegularExpression(
        pattern: #"(?<!\[)(Sayfa|Page)\s+(\d{1,4})"#,
        options: [.caseInsensitive]
    )

    static func linkifyPageCitations(_ text: String) -> String {
        guard let regex = pageCitationRegex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: "[$1 $2](jump:$2)"
        )
    }

    // MARK: - Block Types

    private enum BlockType: Identifiable {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case table(headers: [String], rows: [[String]])
        case bulletList(items: [String])
        case numberedList(items: [String])
        case codeBlock(code: String, language: String?)
        case blockquote(text: String)
        case divider

        var id: String {
            switch self {
            case .heading(_, let text): return "h_\(text.hashValue)"
            case .paragraph(let text): return "p_\(text.hashValue)"
            case .table(let headers, let rows): return "t_\(headers.joined().hashValue)_\(rows.count)"
            case .bulletList(let items): return "bl_\(items.joined().hashValue)"
            case .numberedList(let items): return "nl_\(items.joined().hashValue)"
            case .codeBlock(let code, _): return "cb_\(code.hashValue)"
            case .blockquote(let text): return "bq_\(text.hashValue)"
            case .divider: return "div_static"
            }
        }
    }

    // MARK: - Parsing

    private static func parseBlocksInternal(_ text: String) -> [BlockType] {
        var blocks: [BlockType] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Divider
            if trimmed.hasPrefix("---") || trimmed.hasPrefix("***") || trimmed.hasPrefix("___") {
                blocks.append(.divider)
                i += 1
                continue
            }

            // Heading
            if let headingMatch = parseHeading(trimmed) {
                blocks.append(headingMatch)
                i += 1
                continue
            }

            // Table - check if this and next line form a table
            if isTableRow(trimmed) && i + 1 < lines.count {
                let (table, consumed) = parseTable(lines: Array(lines[i...]))
                if let table = table {
                    blocks.append(table)
                    i += consumed
                    continue
                }
            }

            // Bullet list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                let (list, consumed) = parseBulletList(lines: Array(lines[i...]))
                blocks.append(list)
                i += consumed
                continue
            }

            // Numbered list
            if let _ = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let (list, consumed) = parseNumberedList(lines: Array(lines[i...]))
                blocks.append(list)
                i += consumed
                continue
            }

            // Code block
            if trimmed.hasPrefix("```") {
                let (codeBlock, consumed) = parseCodeBlock(lines: Array(lines[i...]))
                blocks.append(codeBlock)
                i += consumed
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                let (quote, consumed) = parseBlockquote(lines: Array(lines[i...]))
                blocks.append(quote)
                i += consumed
                continue
            }

            // Default: paragraph
            blocks.append(.paragraph(text: trimmed))
            i += 1
        }

        return blocks
    }

    private static func parseHeading(_ line: String) -> BlockType? {
        if line.hasPrefix("#### ") {
            return .heading(level: 4, text: String(line.dropFirst(5)))
        } else if line.hasPrefix("### ") {
            return .heading(level: 3, text: String(line.dropFirst(4)))
        } else if line.hasPrefix("## ") {
            return .heading(level: 2, text: String(line.dropFirst(3)))
        } else if line.hasPrefix("# ") {
            return .heading(level: 1, text: String(line.dropFirst(2)))
        }
        return nil
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.contains("|") && line.filter { $0 == "|" }.count >= 2
    }

    private static func parseTable(lines: [String]) -> (BlockType?, Int) {
        guard lines.count >= 2 else { return (nil, 0) }

        // İlk satır header mı?
        let headerLine = lines[0]
        guard isTableRow(headerLine) else { return (nil, 0) }

        // İkinci satır separator mı?
        let separatorLine = lines.count > 1 ? lines[1] : ""
        let isSeparator = separatorLine.contains(":---") ||
                          separatorLine.contains("---:") ||
                          separatorLine.contains("---") && separatorLine.contains("|")

        guard isSeparator else { return (nil, 0) }

        // Header'ları parse et
        let headers = parseTableRow(headerLine)

        // Data satırlarını topla
        var rows: [[String]] = []
        var consumed = 2 // header + separator

        for i in 2..<lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if isTableRow(line) {
                rows.append(parseTableRow(line))
                consumed += 1
            } else {
                break
            }
        }

        return (.table(headers: headers, rows: rows), consumed)
    }

    private static func parseTableRow(_ line: String) -> [String] {
        line
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func parseBulletList(lines: [String]) -> (BlockType, Int) {
        var items: [String] = []
        var consumed = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                let text = String(trimmed.dropFirst(2))
                items.append(text)
                consumed += 1
            } else {
                break
            }
        }

        return (.bulletList(items: items), consumed)
    }

    private static func parseNumberedList(lines: [String]) -> (BlockType, Int) {
        var items: [String] = []
        var consumed = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let range = trimmed.range(of: #"^\d+\.\s"#, options: .regularExpression) {
                let text = String(trimmed[range.upperBound...])
                items.append(text)
                consumed += 1
            } else {
                break
            }
        }

        return (.numberedList(items: items), consumed)
    }

    private static func parseCodeBlock(lines: [String]) -> (BlockType, Int) {
        var code = ""
        var consumed = 1 // opening ```

        // ```swift gibi açılış çitindeki dil etiketi başlıkta gösterilir.
        let fence = lines[0].trimmingCharacters(in: .whitespaces)
        let languageTag = String(fence.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        let language = languageTag.isEmpty ? nil : languageTag

        for i in 1..<lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                consumed += 1
                break
            }
            code += (code.isEmpty ? "" : "\n") + line
            consumed += 1
        }

        return (.codeBlock(code: code, language: language), consumed)
    }

    private static func parseBlockquote(lines: [String]) -> (BlockType, Int) {
        var text = ""
        var consumed = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(">") {
                let content = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                text += (text.isEmpty ? "" : " ") + content
                consumed += 1
            } else {
                break
            }
        }

        return (.blockquote(text: text), consumed)
    }

    // MARK: - Rendering

    @ViewBuilder
    private func renderBlock(_ block: BlockType) -> some View {
        switch block {
        case .heading(let level, let text):
            renderHeading(level: level, text: text)

        case .paragraph(let text):
            renderParagraph(text)

        case .table(let headers, let rows):
            renderTable(headers: headers, rows: rows)

        case .bulletList(let items):
            renderBulletList(items)

        case .numberedList(let items):
            renderNumberedList(items)

        case .codeBlock(let code, let language):
            renderCodeBlock(code, language: language)

        case .blockquote(let text):
            renderBlockquote(text)

        case .divider:
            Divider()
                .padding(.vertical, 4)
        }
    }

    private func renderHeading(level: Int, text: String) -> some View {
        HStack(spacing: 6) {
            if level <= 2 {
                Rectangle()
                    .fill(DSColor.brand)
                    .frame(width: 3)
            }
            renderInlineText(text)
                .font(level == 1 ? .headline : (level == 2 ? .subheadline.bold() : .subheadline.weight(.semibold)))
        }
        .padding(.top, level == 1 ? 8 : 4)
    }

    private func renderParagraph(_ text: String) -> some View {
        renderInlineText(text)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func renderInlineText(_ text: String) -> Text {
        // Parse inline formatting: **bold**, *italic*, `code`, [link](url)
        var result = Text("")
        var remaining = text

        while !remaining.isEmpty {
            // Any markdown link: [label](jump:N) page citations AND standard
            // [label](https://…) web links — the latter previously rendered
            // as dead plain text.
            if let linkMatch = remaining.range(of: #"\[([^\]]+)\]\(([^)\s]+)\)"#, options: .regularExpression) {
                let before = String(remaining[..<linkMatch.lowerBound])
                if !before.isEmpty {
                    result = result + parseBasicFormatting(before)
                }

                let linkText = String(remaining[linkMatch])
                if let labelRange = linkText.range(of: #"\[([^\]]+)\]"#, options: .regularExpression),
                   let targetRange = linkText.range(of: #"\(([^)\s]+)\)$"#, options: .regularExpression) {
                    let label = String(linkText[labelRange]).dropFirst().dropLast()
                    let target = String(linkText[targetRange]).dropFirst().dropLast()

                    var attributed = AttributedString(String(label))
                    if target.hasPrefix("jump:"), let page = Int(target.dropFirst(5)) {
                        // Page citation; OpenURLAction on `body` handles navigation.
                        attributed.foregroundColor = DSColor.brand
                        attributed.underlineStyle = Text.LineStyle.single
                        attributed.link = URL(string: "\(Self.jumpLinkScheme)://\(page)")
                        result = result + Text(attributed)
                    } else if target.hasPrefix("http://") || target.hasPrefix("https://"),
                              let url = URL(string: String(target)) {
                        // Standard web link; falls through OpenURLAction to Safari.
                        attributed.foregroundColor = DSColor.brand
                        attributed.underlineStyle = Text.LineStyle.single
                        attributed.link = url
                        result = result + Text(attributed)
                    } else {
                        // Unknown scheme: keep readable plain label.
                        result = result + parseBasicFormatting(String(label))
                    }
                }

                remaining = String(remaining[linkMatch.upperBound...])
                continue
            }

            // No special patterns found, parse rest as basic formatting
           result = result + parseBasicFormatting(remaining)
            break
        }

        return result
    }

    private func parseBasicFormatting(_ text: String) -> Text {
        var result = Text("")
        var remaining = text

        while !remaining.isEmpty {
            // Strikethrough: ~~text~~
            if let strikeRange = remaining.range(of: #"~~([^~]+)~~"#, options: .regularExpression) {
                let before = String(remaining[..<strikeRange.lowerBound])
                if !before.isEmpty {
                    result = result + Text(before)
                }

                let strikeText = String(remaining[strikeRange])
                    .replacingOccurrences(of: "~~", with: "")
                result = result + Text(strikeText).strikethrough()

                remaining = String(remaining[strikeRange.upperBound...])
                continue
            }

            // Bold: **text**
            if let boldRange = remaining.range(of: #"\*\*([^\*]+)\*\*"#, options: .regularExpression) {
                let before = String(remaining[..<boldRange.lowerBound])
                if !before.isEmpty {
                    result = result + Text(before)
                }

                let boldText = String(remaining[boldRange])
                    .replacingOccurrences(of: "**", with: "")
                result = result + Text(boldText).bold()

                remaining = String(remaining[boldRange.upperBound...])
                continue
            }

            // Italic: *text*
            if let italicRange = remaining.range(of: #"\*([^\*]+)\*"#, options: .regularExpression) {
                let before = String(remaining[..<italicRange.lowerBound])
                if !before.isEmpty {
                    result = result + Text(before)
                }

                let italicText = String(remaining[italicRange])
                    .replacingOccurrences(of: "*", with: "")
                result = result + Text(italicText).italic()

                remaining = String(remaining[italicRange.upperBound...])
                continue
            }

            // Code: `text`
            if let codeRange = remaining.range(of: #"`([^`]+)`"#, options: .regularExpression) {
                let before = String(remaining[..<codeRange.lowerBound])
                if !before.isEmpty {
                    result = result + Text(before)
                }

                let codeText = String(remaining[codeRange])
                    .replacingOccurrences(of: "`", with: "")
                result = result + Text(codeText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(DSColor.brand)

                remaining = String(remaining[codeRange.upperBound...])
                continue
            }

            // No patterns, add rest as plain text
            result = result + Text(remaining)
            break
        }

        return result
    }

    // MARK: - Table Rendering

    private func renderTable(headers: [String], rows: [[String]]) -> some View {
        // Fixed-width columns inside a horizontal ScrollView: wide academic tables
        // (drug/dose grids) scroll instead of clipping, and equal widths keep the
        // header aligned with every data row. Width scales with Dynamic Type.
        let columnWidth = tableColumnWidth

        return ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(headers.indices, id: \.self) { index in
                        Text(headers[index])
                            .font(.caption.bold())
                            .foregroundColor(.primary)
                            .frame(width: columnWidth, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(DSColor.brand.opacity(0.15))

                        if index < headers.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(DSColor.brand.opacity(0.1))

                Divider()

                // Data rows
                ForEach(rows.indices, id: \.self) { rowIndex in
                    HStack(spacing: 0) {
                        ForEach(rows[rowIndex].indices, id: \.self) { colIndex in
                            Text(rows[rowIndex][colIndex])
                                .font(.caption)
                                .foregroundColor(.primary)
                                .frame(width: columnWidth, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)

                            if colIndex < rows[rowIndex].count - 1 {
                                Divider()
                            }
                        }
                    }
                    .background(rowIndex % 2 == 0 ? Color(.systemBackground) : Color(.secondarySystemBackground).opacity(0.5))

                    if rowIndex < rows.count - 1 {
                        Divider()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(.separator), lineWidth: 1)
            )
        }
    }

    private func renderBulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(DSColor.brand)
                        .frame(width: 5, height: 5)
                        .padding(.top, 6)

                    renderInlineText(items[index])
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func renderNumberedList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.subheadline.bold())
                        .foregroundColor(DSColor.brand)
                        .frame(width: 20, alignment: .trailing)

                    renderInlineText(items[index])
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Kod bloğu: dil etiketi + kopyala butonu başlığı, uzun satırlar için
    /// yatay scroll (satır sarma kod hizasını bozuyordu).
    private func renderCodeBlock(_ code: String, language: String?) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(language ?? "chat.code".localized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.lowercase)

                Spacer()

                Button {
                    UIPasteboard.general.string = code
                    DSHaptics.lightImpact()
                } label: {
                    Label("chat.copy".localized, systemImage: "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("chat.copy".localized)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemBackground))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.secondarySystemBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
        )
    }

    private func renderBlockquote(_ text: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(DSColor.brand.opacity(0.5))
                .frame(width: 3)

            renderInlineText(text)
                .font(.subheadline)
                .italic()
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        MarkdownView(
            text: """
            ## Çalışmanın Ana Bulguları

            Bu çalışma önemli sonuçlar ortaya koymuştur:

            | İlaç Sınıfı | Düşük Risk (%) | Yüksek Risk (%) |
            | :--- | :---: | :---: |
            | **Antihiperlipidemik** | +7.75 | +7.86 |
            | **Antihipertansif** | +3.39 | +5.50 |
            | **Antidiyabetik** | +1.22 | +3.38 |

            ### Önemli Noktalar

            - Risk faktörleri analiz edildi
            - Sonuçlar *istatistiksel olarak anlamlı*
            - Detaylar için [Sayfa 10](jump:10) bakınız

            > Not: Bu veriler retrospektif analize dayanmaktadır.
            """
        )            { page in print("Navigate to page \(page)") }
        .padding()
    }
}
