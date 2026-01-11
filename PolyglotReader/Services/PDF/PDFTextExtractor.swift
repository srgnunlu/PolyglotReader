import Foundation
import PDFKit

// MARK: - Search Result
struct PDFSearchResult {
    let pageIndex: Int
    let selection: PDFSelection

    var pageNumber: Int {
        pageIndex + 1
    }
}

// MARK: - Extraction Options (P2)
struct PDFExtractionOptions {
    var preserveTableStructure: Bool = true
    var normalizeWhitespace: Bool = true
    var detectParagraphs: Bool = true
    var includePageMarkers: Bool = true
    var removeHyphenation: Bool = true

    static let `default` = PDFExtractionOptions()
    static let raw = PDFExtractionOptions(
        preserveTableStructure: false,
        normalizeWhitespace: false,
        detectParagraphs: false,
        includePageMarkers: true,
        removeHyphenation: false
    )
}

class PDFTextExtractor {

    // MARK: - P2: Table Detection Patterns
    private let tableIndicatorPatterns: [String] = [
        #"^\s*\|.*\|.*\|"#,                    // Pipe tables
        #"^\s*[-+]+[-+]+"#,                    // ASCII table borders
        #"^\s*[\d,.]+\s{2,}[\d,.]+\s{2,}"#,   // Aligned numbers
        #"^\s*\w+\s{3,}\w+\s{3,}\w+"#          // Multi-space columns
    ]

    // MARK: - Text Extraction

    /// Legacy method - backward compatible
    func extractText(from document: PDFDocument) -> String {
        extractText(from: document, options: .default)
    }

    /// P2: Enhanced text extraction with options
    func extractText(from document: PDFDocument, options: PDFExtractionOptions) -> String {
        var fullText = ""

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            let pageNumber = pageIndex + 1

            // Sayfa marker'ı
            if options.includePageMarkers {
                fullText += buildPageMarker(pageNumber: pageNumber, totalPages: document.pageCount)
            }

            // Sayfa metnini çıkar ve işle
            if let rawText = page.string {
                var processedText = rawText

                // P2.2: Tablo yapısını koru
                if options.preserveTableStructure {
                    processedText = preserveTableStructure(in: processedText)
                }

                // P2.3: Metin normalleştirme
                if options.normalizeWhitespace {
                    processedText = normalizeWhitespace(in: processedText)
                }

                // P2.3: Tireleme düzeltme
                if options.removeHyphenation {
                    processedText = removeHyphenation(from: processedText)
                }

                // P2.2: Paragraf algılama
                if options.detectParagraphs {
                    processedText = detectAndMarkParagraphs(in: processedText)
                }

                fullText += processedText
            }

            fullText += "\n\n"
        }

        return fullText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func extractText(from page: PDFPage) -> String {
        guard let text = page.string else { return "" }
        var processed = normalizeWhitespace(in: text)
        processed = removeHyphenation(from: processed)
        return processed
    }

    // MARK: - P2.4: Enhanced Page Markers

    private func buildPageMarker(pageNumber: Int, totalPages: Int) -> String {
        // Zenginleştirilmiş sayfa marker formatı
        return "\n--- Sayfa \(pageNumber)/\(totalPages) ---\n"
    }

    // MARK: - P2.2: Table Structure Preservation

    /// Tablo yapısını algılar ve korur
    private func preserveTableStructure(in text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        var inTable = false
        var tableLines: [String] = []

        for line in lines {
            let isTableLine = isLikelyTableLine(line)

            if isTableLine {
                if !inTable {
                    // Tablo başlıyor
                    inTable = true
                    result.append("\n[TABLO_BAŞLANGIÇ]")
                }
                tableLines.append(line)
            } else {
                if inTable {
                    // Tablo bitiyor
                    let formattedTable = formatTableLines(tableLines)
                    result.append(formattedTable)
                    result.append("[TABLO_BİTİŞ]\n")
                    tableLines.removeAll()
                    inTable = false
                }
                result.append(line)
            }
        }

        // Son tablo kontrolü
        if inTable && !tableLines.isEmpty {
            let formattedTable = formatTableLines(tableLines)
            result.append(formattedTable)
            result.append("[TABLO_BİTİŞ]\n")
        }

        return result.joined(separator: "\n")
    }

    /// Satırın tablo satırı olup olmadığını kontrol eder
    private func isLikelyTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // Pattern eşleşmesi
        for pattern in tableIndicatorPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                return true
            }
        }

        // Tab sayısı heuristic - 2+ tab = muhtemel tablo
        let tabCount = line.filter { $0 == "\t" }.count
        if tabCount >= 2 {
            return true
        }

        // Çoklu boşluk heuristic - düzenli aralıklı veriler
        let multiSpacePattern = #"\s{3,}"#
        if let regex = try? NSRegularExpression(pattern: multiSpacePattern, options: []) {
            let matches = regex.matches(in: line, options: [], range: NSRange(line.startIndex..., in: line))
            if matches.count >= 2 {
                return true
            }
        }

        return false
    }

    /// Tablo satırlarını formatlar
    private func formatTableLines(_ lines: [String]) -> String {
        guard !lines.isEmpty else { return "" }

        var formattedLines: [String] = []

        for line in lines {
            // Tab'ları " | " ile değiştir
            var formatted = line.replacingOccurrences(of: "\t", with: " | ")

            // Çoklu boşlukları " | " ile değiştir (3+ boşluk)
            if let regex = try? NSRegularExpression(pattern: #"\s{3,}"#, options: []) {
                formatted = regex.stringByReplacingMatches(
                    in: formatted,
                    options: [],
                    range: NSRange(formatted.startIndex..., in: formatted),
                    withTemplate: " | "
                )
            }

            formattedLines.append(formatted)
        }

        return formattedLines.joined(separator: "\n")
    }

    // MARK: - P2.3: Text Normalization

    /// Gereksiz boşlukları temizler
    private func normalizeWhitespace(in text: String) -> String {
        var result = text

        // Çoklu boşlukları tek boşluğa indir (tablo dışı)
        // Dikkat: Tablo içindeki boşlukları korumak için TABLO marker'larını kontrol et
        let lines = result.components(separatedBy: .newlines)
        var normalizedLines: [String] = []
        var inTable = false

        for line in lines {
            if line.contains("[TABLO_BAŞLANGIÇ]") {
                inTable = true
                normalizedLines.append(line)
            } else if line.contains("[TABLO_BİTİŞ]") {
                inTable = false
                normalizedLines.append(line)
            } else if inTable {
                // Tablo içinde - boşlukları koru
                normalizedLines.append(line)
            } else {
                // Tablo dışında - normalleştir
                var normalized = line

                // Satır başı/sonu boşlukları temizle
                normalized = normalized.trimmingCharacters(in: .whitespaces)

                // Çoklu boşlukları tek boşluğa indir
                while normalized.contains("  ") {
                    normalized = normalized.replacingOccurrences(of: "  ", with: " ")
                }

                normalizedLines.append(normalized)
            }
        }

        result = normalizedLines.joined(separator: "\n")

        // Çoklu newline'ları maksimum 2'ye indir
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        return result
    }

    /// Satır sonu tirelemeyi düzeltir (ör: "prog-\nram" -> "program")
    private func removeHyphenation(from text: String) -> String {
        // Satır sonundaki tire + newline + küçük harf = tireleme
        let hyphenPattern = #"(\w)-\n(\p{Ll})"#

        guard let regex = try? NSRegularExpression(pattern: hyphenPattern, options: []) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: range,
            withTemplate: "$1$2"
        )
    }

    // MARK: - P2.2: Paragraph Detection

    /// Paragrafları algılar ve işaretler
    private func detectAndMarkParagraphs(in text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        var currentParagraph: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Boş satır veya özel marker = paragraf sonu
            if trimmed.isEmpty ||
               trimmed.hasPrefix("[TABLO_") ||
               trimmed.hasPrefix("--- Sayfa") {

                // Mevcut paragrafı kaydet
                if !currentParagraph.isEmpty {
                    result.append(currentParagraph.joined(separator: " "))
                    currentParagraph.removeAll()
                }

                // Boş satır veya marker'ı ekle
                if !trimmed.isEmpty {
                    result.append(line)
                } else {
                    result.append("")
                }
            } else {
                // Yeni paragraf başlangıç kontrolü
                let startsWithCapital = trimmed.first?.isUppercase == true
                let previousEndsWithPeriod = currentParagraph.last?.last?.isPunctuation == true

                // Yeni cümle başlıyorsa ve önceki bitmiş görünüyorsa
                if startsWithCapital && previousEndsWithPeriod && !currentParagraph.isEmpty {
                    // Aynı paragrafta devam (çoğu durumda)
                    currentParagraph.append(trimmed)
                } else if currentParagraph.isEmpty {
                    // Yeni paragraf başlat
                    currentParagraph.append(trimmed)
                } else {
                    // Mevcut paragrafa ekle
                    currentParagraph.append(trimmed)
                }
            }
        }

        // Son paragrafı kaydet
        if !currentParagraph.isEmpty {
            result.append(currentParagraph.joined(separator: " "))
        }

        return result.joined(separator: "\n")
    }

    // MARK: - Search

    func search(query: String, in document: PDFDocument, logger: LoggingService? = nil) -> [PDFSearchResult] {
        var results: [PDFSearchResult] = []

        // CRITICAL: findString() crash yapabilir - try-catch ile koru
        let selections = document.findString(query, withOptions: .caseInsensitive)

        if selections.isEmpty {
            logger?.warning("PDFTextExtractor", "Arama başarısız", details: "Query: \(query.prefix(50))")
            return []
        }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }

            for selection in selections where selection.pages.contains(page) {
                results.append(PDFSearchResult(
                    pageIndex: pageIndex,
                    selection: selection
                ))
            }
        }

        return results
    }
}
