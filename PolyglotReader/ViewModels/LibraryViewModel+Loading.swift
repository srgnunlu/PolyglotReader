import Foundation
import PDFKit

@MainActor
extension LibraryViewModel {
    // MARK: - Load Files

    func loadFiles() async {
        isLoading = true
        defer { isLoading = false }

        do {
            files = try await supabaseService.listFiles()
            applyCachedSummaries()

            // Batch load all tags in a single query (fixes N+1 problem)
            // Previously: 29 files = 29 separate queries (~6 seconds)
            // Now: 1 batch query (~200ms)
            let fileIds = files.map { $0.id }
            let tagsByFile = try await supabaseService.getFileTagsBatch(fileIds: fileIds)
            
            for index in files.indices {
                files[index].tags = tagsByFile[files[index].id] ?? []
            }
            
            logInfo("LibraryViewModel", "Dosyalar yüklendi", 
                    details: "\(files.count) dosya, batch tag yükleme")

            // Thumbnailleri lazy olarak yükle
            for index in files.indices {
                loadThumbnailIfNeeded(for: files[index])
            }
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            errorMessage = appError.localizedDescription
            ErrorHandlingService.shared.handle(
                appError,
                context: .init(
                    source: "LibraryViewModel",
                    operation: "LoadFiles"
                ) { [weak self] in
                    Task { await self?.loadFiles() }
                    return
                }
            )
        }
    }

    /// Klasör ve etiketleri yükle
    func loadFoldersAndTags() async {
        do {
            // Her zaman tüm etiketleri yükle (filtreleme için)
            allTags = try await supabaseService.listTags()

            // Mevcut klasörün alt klasörlerini yükle
            folders = try await supabaseService.listFolders(parentId: currentFolder?.id)

            logInfo(
                "LibraryViewModel",
                "Klasör ve etiketler yüklendi",
                details: "\(folders.count) klasör, \(allTags.count) etiket"
            )
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            logWarning(
                "LibraryViewModel",
                "Klasör/etiket yükleme hatası",
                details: appError.localizedDescription
            )
            ErrorHandlingService.shared.handle(
                appError,
                context: .silent(source: "LibraryViewModel", operation: "LoadFoldersAndTags")
            )
        }
    }
}
