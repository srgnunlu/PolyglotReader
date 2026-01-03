import SwiftUI

// MARK: - Professional Markdown Renderer

struct MarkdownView: View {
    let text: String
    let onNavigateToPage: (Int) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseBlocks(text), id: \.id) { block in
                renderBlock(block)
            }
        }
    }
    
    // MARK: - Block Types
    
    private enum BlockType: Identifiable {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case table(headers: [String], rows: [[String]])
        case bulletList(items: [String])
        case numberedList(items: [String])
        case codeBlock(code: String)
        case blockquote(text: String)
        case divider
        
        var id: String {
            switch self {
            case .heading(_, let text): return "h_\(text.prefix(20))"
            case .paragraph(let text): return "p_\(text.prefix(20))"
            case .table(let headers, _): return "t_\(headers.joined())"
            case .bulletList(let items): return "bl_\(items.first?.prefix(20) ?? "")"
            case .numberedList(let items): return "nl_\(items.first?.prefix(20) ?? "")"
            case .codeBlock(let code): return "cb_\(code.prefix(20))"
            case .blockquote(let text): return "bq_\(text.prefix(20))"
            case .divider: return "div_\(UUID().uuidString)"
            }
        }
    }
    
    // MARK: - Parsing
    
    private func parseBlocks(_ text: String) -> [BlockType] {
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
    
    private func parseHeading(_ line: String) -> BlockType? {
        if line.hasPrefix("### ") {
            return .heading(level: 3, text: String(line.dropFirst(4)))
        } else if line.hasPrefix("## ") {
            return .heading(level: 2, text: String(line.dropFirst(3)))
        } else if line.hasPrefix("# ") {
            return .heading(level: 1, text: String(line.dropFirst(2)))
        }
        return nil
    }
    
    private func isTableRow(_ line: String) -> Bool {
        return line.contains("|") && line.filter { $0 == "|" }.count >= 2
    }
    
    private func parseTable(lines: [String]) -> (BlockType?, Int) {
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
    
    private func parseTableRow(_ line: String) -> [String] {
        return line
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
    
    private func parseBulletList(lines: [String]) -> (BlockType, Int) {
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
    
    private func parseNumberedList(lines: [String]) -> (BlockType, Int) {
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
    
    private func parseCodeBlock(lines: [String]) -> (BlockType, Int) {
        var code = ""
        var consumed = 1 // opening ```
        
        for i in 1..<lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                consumed += 1
                break
            }
            code += (code.isEmpty ? "" : "\n") + line
            consumed += 1
        }
        
        return (.codeBlock(code: code), consumed)
    }
    
    private func parseBlockquote(lines: [String]) -> (BlockType, Int) {
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
            
        case .codeBlock(let code):
            renderCodeBlock(code)
            
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
                    .fill(Color.indigo)
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
            // Check for page links [Sayfa X](jump:X)
            if let linkMatch = remaining.range(of: #"\[([^\]]+)\]\(jump:(\d+)\)"#, options: .regularExpression) {
                let before = String(remaining[..<linkMatch.lowerBound])
                if !before.isEmpty {
                    result = result + parseBasicFormatting(before)
                }
                
                let linkText = String(remaining[linkMatch])
                if let labelRange = linkText.range(of: #"\[([^\]]+)\]"#, options: .regularExpression),
                   let pageRange = linkText.range(of: #"jump:(\d+)"#, options: .regularExpression) {
                    let label = String(linkText[labelRange]).dropFirst().dropLast()
                    let pageStr = String(linkText[pageRange]).replacingOccurrences(of: "jump:", with: "")
                    result = result + Text("[\(label)]").foregroundColor(.indigo).underline()
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
                    .foregroundColor(.indigo)
                
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
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(headers.indices, id: \.self) { index in
                    Text(headers[index])
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.indigo.opacity(0.15))
                    
                    if index < headers.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color.indigo.opacity(0.1))
            
            Divider()
            
            // Data rows
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 0) {
                    ForEach(rows[rowIndex].indices, id: \.self) { colIndex in
                        Text(rows[rowIndex][colIndex])
                            .font(.caption)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
    
    private func renderBulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color.indigo)
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
                        .foregroundColor(.indigo)
                        .frame(width: 20, alignment: .trailing)

                    renderInlineText(items[index])
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    
    private func renderCodeBlock(_ code: String) -> some View {
        Text(code)
            .font(.system(.caption, design: .monospaced))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func renderBlockquote(_ text: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.indigo.opacity(0.5))
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
            """,
            onNavigateToPage: { page in print("Navigate to page \(page)") }
        )
        .padding()
    }
}
