import Foundation
import PDFKit

@MainActor
extension LibraryViewModel {
    // MARK: - AI Summary Generation

    /// PDF için AI özeti oluştur
    func generateSummary(for file: PDFDocumentMetadata, force: Bool = false) async {
        if !force {
            if let summary = file.summary, !summary.isEmpty {
                return
            }

            if let cachedSummary = cachedSummary(for: file.id), !cachedSummary.isEmpty {
                updateFileSummary(fileId: file.id, summary: cachedSummary)
                return
            }
        }

        do {
            let url = try await supabaseService.getFileURL(storagePath: file.storagePath)
            let (data, _) = try await SecurityManager.shared.secureSession.data(from: url)

            guard let document = PDFDocument(data: data) else {
                logError("LibraryViewModel", "PDF oluşturulamadı: \(file.name)")
                return
            }

            let text = extractTextForSummary(from: document)
            guard !text.isEmpty else {
                logWarning("LibraryViewModel", "PDF'den metin çıkarılamadı: \(file.name)")
                return
            }

            let summary = try await GeminiService.shared.generateDocumentSummary(text)

            updateFileSummary(fileId: file.id, summary: summary)
            saveSummaryToCache(summary, fileId: file.id)

            do {
                try await supabaseService.updateFileSummary(fileId: file.id, summary: summary)
            } catch {
                logWarning(
                    "LibraryViewModel",
                    "Özet Supabase'e kaydedilemedi",
                    details: error.localizedDescription
                )
            }

            logInfo("LibraryViewModel", "Özet oluşturuldu: \(file.name)")
        } catch {
            logError("LibraryViewModel", "Özet oluşturma hatası: \(file.name)", error: error)
        }
    }

    /// PDF'den özet için metin çıkar (ilk 3 sayfa)
    func extractTextForSummary(from document: PDFDocument) -> String {
        var text = ""
        let pageCount = min(document.pageCount, 3)

        for i in 0..<pageCount {
            if let page = document.page(at: i), let pageText = page.string {
                text += pageText + "\n\n"
            }
        }

        return String(text.prefix(3000))
    }

    /// Dosya özetini güncelle
    func updateFileSummary(fileId: String, summary: String) {
        if let index = files.firstIndex(where: { $0.id == fileId }) {
            files[index].summary = summary
        }
    }

    // MARK: - Summary Cache

    private func summaryCacheKey(for fileId: String) -> String {
        "\(summaryCacheKeyPrefix)\(fileId)"
    }

    func cachedSummary(for fileId: String) -> String? {
        UserDefaults.standard.string(forKey: summaryCacheKey(for: fileId))
    }

    func saveSummaryToCache(_ summary: String, fileId: String) {
        UserDefaults.standard.set(summary, forKey: summaryCacheKey(for: fileId))
    }

    func removeSummaryFromCache(fileId: String) {
        UserDefaults.standard.removeObject(forKey: summaryCacheKey(for: fileId))
    }

    func applyCachedSummaries() {
        for index in files.indices {
            let fileId = files[index].id
            if let summary = files[index].summary, !summary.isEmpty {
                saveSummaryToCache(summary, fileId: fileId)
                continue
            }

            if let cachedSummary = cachedSummary(for: fileId), !cachedSummary.isEmpty {
                files[index].summary = cachedSummary
            }
        }
    }
}
