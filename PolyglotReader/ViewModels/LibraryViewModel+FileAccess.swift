import Foundation

@MainActor
extension LibraryViewModel {
    // MARK: - Get File URL

    func getFileURL(_ file: PDFDocumentMetadata) async -> URL? {
        do {
            return try await supabaseService.getFileURL(storagePath: file.storagePath)
        } catch {
            errorMessage = "Dosya URL'i alınamadı"
            return nil
        }
    }
}
