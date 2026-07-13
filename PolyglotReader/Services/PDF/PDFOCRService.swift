import Foundation
import PDFKit
import Vision
import UIKit

// MARK: - Reading-Order Text Assembly

/// One recognized line with normalized page coordinates.
/// Coordinates are normalized 0...1; `top` uses PDF/Vision convention where a
/// higher value means nearer the top of the page (y-origin bottom-left).
struct OCRTextLine: Equatable {
    let text: String
    let midX: Double
    let top: Double
}

/// Pure, PDFKit-free reading-order assembler for OCR output. Native selectable
/// text deliberately keeps PDFKit's exact source order and does not use this
/// heuristic.
enum OCRTextAssembler {
    /// Lines whose horizontal centers differ by less than this fraction of the
    /// page width are treated as belonging to the same column. 0.15 tolerates
    /// ragged left edges within a column while still splitting a 2-column layout.
    static let columnGapThreshold: Double = 0.15

    /// Orders lines reading-order aware: cluster into columns by x, left-to-right;
    /// within a column, top-to-bottom; then merge lines with hyphen handling.
    static func assemble(_ lines: [OCRTextLine]) -> String {
        guard !lines.isEmpty else { return "" }
        let columns = clusterIntoColumns(lines)
        let ordered = columns.flatMap { column in
            // Higher `top` = higher on the page, so descending sort = top-to-bottom.
            column.sorted { $0.top > $1.top }.map(\.text)
        }
        return mergeLines(ordered)
    }

    /// Greedily groups lines into left-to-right columns by horizontal center.
    static func clusterIntoColumns(_ lines: [OCRTextLine]) -> [[OCRTextLine]] {
        let sorted = lines.sorted { $0.midX < $1.midX }
        var columns: [[OCRTextLine]] = []
        for line in sorted {
            if let last = columns.last, abs(line.midX - average(of: last)) <= columnGapThreshold {
                columns[columns.count - 1].append(line)
            } else {
                columns.append([line])
            }
        }
        return columns
    }

    /// Joins ordered lines, merging hyphenated line breaks ("word-" + lowercase
    /// start → "word..."). Non-hyphenated boundaries join with a newline.
    static func mergeLines(_ lines: [String]) -> String {
        var result = ""
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if result.isEmpty {
                result = line
            } else if endsWithMergeableHyphen(result), line.first?.isLowercase == true {
                result.removeLast() // drop the trailing hyphen and glue the halves
                result += line
            } else {
                result += "\n" + line
            }
        }
        return result
    }

    private static func average(of lines: [OCRTextLine]) -> Double {
        guard !lines.isEmpty else { return 0 }
        return lines.reduce(0) { $0 + $1.midX } / Double(lines.count)
    }

    /// True when text ends with "<letter>-", i.e. a genuine word hyphenation and
    /// not a dash bullet or an "-" standing alone.
    private static func endsWithMergeableHyphen(_ text: String) -> Bool {
        guard text.last == "-" else { return false }
        let hyphenIndex = text.index(before: text.endIndex)
        guard hyphenIndex > text.startIndex else { return false }
        return text[text.index(before: hyphenIndex)].isLetter
    }
}

// MARK: - PDF OCR Service

/// OCR for scanned PDF pages that lack an embedded text layer.
///
/// Not `@MainActor`: recognition is CPU-heavy and must stay off the main thread.
/// Results are cached per document + page index so repeated extraction (RAG
/// re-index, document re-open) never redoes the expensive Vision pass.
final class PDFOCRService {
    static let shared = PDFOCRService()

    /// ~2x of page bounds gives Vision readable glyphs; the pixel cap keeps a
    /// huge page (posters, A0 scans) from spiking memory during rendering.
    private let targetScale: CGFloat = 2.0
    private let maxPixelDimension: CGFloat = 4000

    private let cache = OCRCache()

    private init() {}

    // MARK: - Public API

    /// True when the page already has selectable embedded text. Callers use this
    /// to decide whether an OCR fallback is needed for a scanned page.
    func hasTextLayer(_ page: PDFPage) -> Bool {
        guard let text = page.string else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Recognizes text on a scanned page via Vision, ordered reading-order aware.
    /// Returns nil when nothing is recognized. An empty result is cached too, so
    /// a truly blank/undecipherable page is not re-OCR'd on every call.
    func recognizeText(on page: PDFPage) async -> String? {
        let key = Self.cacheKey(for: page)
        if let key, let cached = await cache.value(for: key) {
            return cached.isEmpty ? nil : cached
        }

        guard let cgImage = renderPageImage(page: page) else { return nil }
        let recognized = await Self.performRecognition(on: cgImage) ?? ""

        if let key {
            await cache.set(recognized, for: key)
        }
        return recognized.isEmpty ? nil : recognized
    }

    // MARK: - Rendering

    private func renderPageImage(page: PDFPage) -> CGImage? {
        let pageRect = page.bounds(for: .mediaBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return nil }

        // Scale down from 2x only when the longest side would exceed the pixel
        // cap; never downscale below 1x (that would hurt recognition accuracy).
        let longestSide = max(pageRect.width, pageRect.height)
        let scale = max(min(targetScale, maxPixelDimension / longestSide), 1.0)

        let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            // PDF space is y-up (bottom-left); flip into image space (y-down).
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        return image.cgImage
    }

    // MARK: - Recognition

    private static func performRecognition(on cgImage: CGImage) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["tr-TR", "en-US"]
            request.usesLanguageCorrection = true

            do {
                try handler.perform([request])
            } catch {
                // Privacy: log only the error, never any recognized content.
                logWarning("PDFOCRService", "OCR isteği başarısız", details: error.localizedDescription)
                return nil
            }

            guard let observations = request.results, !observations.isEmpty else { return nil }

            let lines: [OCRTextLine] = observations.compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox // normalized, y-origin bottom-left
                return OCRTextLine(text: candidate.string, midX: Double(box.midX), top: Double(box.midY))
            }
            return OCRTextAssembler.assemble(lines)
        }.value
    }

    // MARK: - Cache Key

    private static func cacheKey(for page: PDFPage) -> String? {
        guard let document = page.document else { return nil }
        let documentId = ObjectIdentifier(document).hashValue
        return "\(documentId)#\(document.index(for: page))"
    }
}

// MARK: - OCR Cache

/// Actor-isolated string cache. Keyed by "<documentId>#<pageIndex>" so results
/// from different open documents never collide.
private actor OCRCache {
    private var storage: [String: String] = [:]

    func value(for key: String) -> String? { storage[key] }

    func set(_ value: String, for key: String) { storage[key] = value }
}
