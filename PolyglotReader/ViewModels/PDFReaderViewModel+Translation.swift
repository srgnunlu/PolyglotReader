import Foundation

// MARK: - Quick Translation
/// Quick-translation mode plus history persistence, split out to keep the
/// main view-model body inside the lint type-body budget.
@MainActor
extension PDFReaderViewModel {
    func toggleQuickTranslationMode() {
        isQuickTranslationMode.toggle()
        clearSelection()
        logInfo("PDFReaderVM", isQuickTranslationMode ? "Hızlı Çeviri Modu açıldı" : "Normal mod")
    }

    /// Fire-and-forget: tamamlanan çeviriyi geçmişe yazar (Defterim > Çeviriler).
    /// Kayıt hatası okumayı asla etkilemez; kopyalar DB'de sessizce elenir.
    func persistTranslation(source: String, translated: String) {
        guard !source.isEmpty, !translated.isEmpty else { return }
        let fileId = fileMetadata.id

        Task {
            do {
                try await supabaseService.saveTranslationToHistory(
                    fileId: fileId,
                    sourceText: source,
                    translatedText: translated
                )
            } catch {
                logWarning("PDFReaderVM", "Çeviri geçmişine yazılamadı", details: error.localizedDescription)
            }
        }
    }
}
