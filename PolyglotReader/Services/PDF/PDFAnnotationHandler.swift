import Foundation
import PDFKit
import UIKit

class PDFAnnotationHandler {
    // MARK: - Annotation Application

    /// Annotation'ları PDF sayfalarına uygular
    /// - Parameters:
    ///   - document: Hedef PDF dokümanı
    ///   - annotations: Uygulanacak annotation listesi
    ///   - lastHash: Önceki hash değeri (değişiklik kontrolü için)
    /// - Returns: Yeni hash değeri (eğer işlem yapıldıysa)
    func applyAnnotations(to document: PDFDocument, annotations: [Annotation], lastHash: Int?) -> Int? {
        // PERFORMANS: Annotation hash'i hesapla ve değişiklik yoksa atla
        let currentHash = annotations.map { "\($0.id)|\($0.pageNumber)|\($0.text ?? "")" }.joined().hashValue

        if let last = lastHash, last == currentHash {
            // Annotation'lar değişmedi, işlem yapma
            return nil
        }

        // Önce mevcut custom annotation'ları temizle (PolyglotHighlight olanları)
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let existingAnnotations = page.annotations
            for annotation in existingAnnotations
            where annotation.value(forAnnotationKey: .name) as? String == "PolyglotHighlight" {
                // Sadece bizim eklediğimiz annotation'ları kaldır (key ile işaretli)
                page.removeAnnotation(annotation)
            }
        }

        // Yeni annotation'ları ekle
        for annotation in annotations {
            applySingleAnnotation(annotation, to: document)
        }

        return currentHash
    }

    private func applySingleAnnotation(_ annotation: Annotation, to document: PDFDocument) {
        guard annotation.pageNumber >= 1,
              annotation.pageNumber <= document.pageCount,
              let page = document.page(at: annotation.pageNumber - 1) else { return }

        let colorString = String(annotation.color)

        // Rengi parse et
        let highlightColor: UIColor
        if let color = UIColor(hex: colorString) {
            highlightColor = color
        } else {
            highlightColor = UIColor.yellow
        }

        // V2: Koordinatlar varsa direkt kullan
        if !annotation.rects.isEmpty {
            if applyUsingRects(annotation, page: page, color: highlightColor) {
                return
            }
        }

        // V1 Fallback: Metin araması yap
        applyUsingTextSearch(annotation, to: document, page: page, color: highlightColor)
    }

    private func applyUsingRects(_ annotation: Annotation, page: PDFPage, color: UIColor) -> Bool {
        let pageBounds = page.bounds(for: .mediaBox)

        // Step 1: Convert all rects to PDF coordinates
        var convertedRects: [CGRect] = []
        for annotationRect in annotation.rects {
            var rect = CGRect(
                x: annotationRect.x,
                y: annotationRect.y,
                width: annotationRect.width,
                height: annotationRect.height
            )

            guard !rect.isNull && !rect.isInfinite && rect.width > 0 && rect.height > 0 else { continue }

            // Detect web percentage coordinates (values typically 0-100)
            // Web saves as percentage with top-left origin
            // iOS PDFKit needs point coordinates with bottom-left origin
            let isWebPercentage = rect.origin.x <= 100 &&
                                  rect.origin.y <= 100 &&
                                  rect.width <= 100 &&
                                  rect.height <= 100

            if isWebPercentage {
                // Convert percentage (0-100) to PDF points
                let pdfX = (rect.origin.x / 100) * pageBounds.width
                let pdfWidth = (rect.width / 100) * pageBounds.width
                let pdfHeight = (rect.height / 100) * pageBounds.height
                // Flip Y axis: web top-left origin → PDF bottom-left origin
                let pdfY = pageBounds.height - ((rect.origin.y + rect.height) / 100) * pageBounds.height

                rect = CGRect(x: pdfX, y: pdfY, width: pdfWidth, height: pdfHeight)
            }

            convertedRects.append(rect)
        }

        guard !convertedRects.isEmpty else { return false }

        // Step 2: Merge overlapping rects to prevent opacity accumulation
        let mergedRects = mergeOverlappingRects(convertedRects)

        // Step 3: Create annotations for merged rects
        for rect in mergedRects {
            let highlight = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
            highlight.color = color.withAlphaComponent(0.4)
            highlight.setValue("PolyglotHighlight", forAnnotationKey: .name)
            highlight.userName = annotation.id
            page.addAnnotation(highlight)
        }

        return true
    }

    /// Aynı satırdaki overlapping rect'leri birleştirir
    /// Bu, opacity birikimini önler ve eşit boyama sağlar
    private func mergeOverlappingRects(_ rects: [CGRect]) -> [CGRect] {
        guard !rects.isEmpty else { return [] }

        // Y koordinatına göre satırlara grupla (benzer Y değerleri = aynı satır)
        var rows: [[CGRect]] = []
        let sortedRects = rects.sorted { $0.minY > $1.minY } // PDF koordinatlarında Y yukarı artar

        for rect in sortedRects {
            var addedToRow = false
            for i in 0..<rows.count {
                // Aynı satırda mı kontrol et (Y farkı height'ın yarısından az)
                if let firstInRow = rows[i].first {
                    let yOverlap = min(rect.maxY, firstInRow.maxY) - max(rect.minY, firstInRow.minY)
                    let minHeight = min(rect.height, firstInRow.height)
                    if yOverlap > minHeight * 0.3 { // %30 Y overlap = aynı satır
                        rows[i].append(rect)
                        addedToRow = true
                        break
                    }
                }
            }
            if !addedToRow {
                rows.append([rect])
            }
        }

        // Her satırdaki rect'leri X'e göre sırala ve bitişik/overlapping olanları birleştir
        var merged: [CGRect] = []
        for row in rows {
            guard !row.isEmpty else { continue }
            let sortedRow = row.sorted { $0.minX < $1.minX }
            var current = sortedRow[0]

            for i in 1..<sortedRow.count {
                let next = sortedRow[i]
                // Overlap veya bitişik mi? (5pt tolerans)
                if current.maxX >= next.minX - 5 {
                    // Union ile birleştir (Y'leri de düzelt)
                    current = current.union(next)
                } else {
                    merged.append(current)
                    current = next
                }
            }
            merged.append(current)
        }

        return merged
    }

    private func applyUsingTextSearch(
        _ annotation: Annotation,
        to document: PDFDocument,
        page: PDFPage,
        color: UIColor
    ) {
        guard let searchText = annotation.text, !searchText.isEmpty else { return }

        let normalizedText = normalizeText(searchText)

        var selections: [PDFSelection] = []
        selections = document.findString(normalizedText, withOptions: .caseInsensitive)

        // Fallback: Kısa metin
        if selections.isEmpty && normalizedText.count > 50 {
            let shortText = String(normalizedText.prefix(50))
            selections = document.findString(shortText, withOptions: .caseInsensitive)
        }

        for selection in selections {
            guard selection.pages.contains(page) else { continue }

            for lineSelection in selection.selectionsByLine() {
                let lineBounds = lineSelection.bounds(for: page)
                guard !lineBounds.isNull && !lineBounds.isInfinite else { continue }

                let pdfAnnotation = PDFAnnotation(bounds: lineBounds, forType: .highlight, withProperties: nil)
                pdfAnnotation.color = color.withAlphaComponent(0.4)
                pdfAnnotation.setValue("PolyglotHighlight", forAnnotationKey: .name)
                pdfAnnotation.setValue(annotation.id, forAnnotationKey: .contents) // ID sakla

                page.addAnnotation(pdfAnnotation)
            }

            // Not ikonu ekle
            addNoteIcon(annotation: annotation, selection: selection, page: page)

            break // Sadece ilk eşleşme
        }
    }

    private func addNoteIcon(annotation: Annotation, selection: PDFSelection, page: PDFPage) {
        guard let note = annotation.note, !note.isEmpty else { return }

        let firstLineBounds = selection.bounds(for: page)
        if !firstLineBounds.isNull && !firstLineBounds.isInfinite {
            let pageBounds = page.bounds(for: .mediaBox)
            let pageCenter = pageBounds.midX
            let textCenter = firstLineBounds.midX

            let noteIconSize: CGFloat = 16
            let iconX: CGFloat = textCenter < pageCenter
                ? firstLineBounds.minX - noteIconSize - 4
                : firstLineBounds.maxX + 4

            let noteIconRect = CGRect(
                x: iconX,
                y: firstLineBounds.midY - noteIconSize / 2,
                width: noteIconSize,
                height: noteIconSize
            )

            let noteAnnotation = PDFAnnotation(bounds: noteIconRect, forType: .text, withProperties: nil)
            noteAnnotation.contents = note
            noteAnnotation.color = UIColor.systemOrange.withAlphaComponent(0.9)
            noteAnnotation.setValue("PolyglotNote", forAnnotationKey: .name)
            noteAnnotation.userName = annotation.id

            page.addAnnotation(noteAnnotation)
        }
    }

    private func normalizeText(_ text: String) -> String {
        var normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Ligatures ve common fixes
        normalized = normalized
            .replacingOccurrences(of: "of\"", with: "of \"")
            .replacingOccurrences(of: "\"\"", with: "\" \"")
            .replacingOccurrences(of: ".....", with: "...")
            .replacingOccurrences(of: "....", with: "...")
            .replacingOccurrences(of: "…", with: "...")
            .replacingOccurrences(of: "' s", with: "'s")
            .replacingOccurrences(of: "' t", with: "'t")
            .replacingOccurrences(of: "ﬁ", with: "fi")
            .replacingOccurrences(of: "ﬂ", with: "fl")
            .replacingOccurrences(of: "ﬀ", with: "ff")
            .replacingOccurrences(of: "ﬃ", with: "ffi")
            .replacingOccurrences(of: "ﬄ", with: "ffl")
            .replacingOccurrences(of: "  ", with: " ")

        return normalized
    }
}
