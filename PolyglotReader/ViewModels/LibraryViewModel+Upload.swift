import Foundation
import PDFKit

@MainActor
extension LibraryViewModel {
    // MARK: - Upload File

    func uploadFile(url: URL, userId: String) async {
        isUploading = true
        uploadProgress = 0.0
        defer {
            isUploading = false
            uploadProgress = 0.0
        }

        do {
            let data = try fetchFileData(from: url)
            let fileName = url.lastPathComponent
            
            logInfo(
                "LibraryViewModel",
                "Dosya yükleniyor",
                details: "\(fileName) - \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
            )
            
            var metadata = try await supabaseService.uploadFile(
                data,
                fileName: fileName,
                userId: userId,
                progressHandler: { [weak self] progress in
                    Task { @MainActor in
                        let clampedProgress = min(max(progress, 0), 1)
                        self?.uploadProgress = clampedProgress
                    }
                }
            )

            await attachFileToCurrentFolder(&metadata)
            applyThumbnail(from: data, to: &metadata)
            await finalizeUpload(metadata: metadata, pdfData: data)
        } catch {
            handleUploadError(error, url: url, userId: userId)
        }
    }

    private enum UploadError: Error {
        case accessDenied
    }

    private func fetchFileData(from url: URL) throws -> Data {
        guard url.startAccessingSecurityScopedResource() else {
            throw UploadError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        return try Data(contentsOf: url)
    }

    private func attachFileToCurrentFolder(_ metadata: inout PDFDocumentMetadata) async {
        guard let folderId = currentFolder?.id else { return }
        do {
            try await supabaseService.moveFileToFolder(fileId: metadata.id, folderId: folderId)
            metadata.folderId = folderId
            logInfo(
                "LibraryViewModel",
                "Dosya klasöre eklendi",
                details: currentFolder?.name ?? ""
            )
        } catch {
            logWarning(
                "LibraryViewModel",
                "Dosya klasöre eklenemedi (migration gerekli olabilir)",
                details: error.localizedDescription
            )
        }
    }

    private func applyThumbnail(from data: Data, to metadata: inout PDFDocumentMetadata) {
        do {
            let document = try pdfService.loadPDF(from: data)
            let thumbnailData = try pdfService.generateThumbnailData(for: document)
            metadata.thumbnailData = thumbnailData
            CacheService.shared.setThumbnail(thumbnailData, forFileId: metadata.id)
            saveThumbnailToDisk(thumbnailData, fileId: metadata.id)
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            ErrorHandlingService.shared.handle(
                appError,
                context: .silent(source: "LibraryViewModel", operation: "Thumbnail")
            )
        }
    }

    private func finalizeUpload(metadata: PDFDocumentMetadata, pdfData: Data) async {
        files.insert(metadata, at: 0)
        await loadFoldersAndTags()

        Task {
            await generateSummary(for: metadata, force: true)
            await generateAndAssignTags(for: metadata, pdfData: pdfData)
            await indexDocumentForRAG(metadata: metadata, pdfData: pdfData)
        }
    }
    
    /// PDF dokümanını RAG için indexle
    private func indexDocumentForRAG(metadata: PDFDocumentMetadata, pdfData: Data) async {
        do {
            guard let document = PDFDocument(data: pdfData) else {
                logWarning("LibraryViewModel", "PDF oluşturulamadı - RAG indexing için")
                return
            }

            // PDFService kullanarak metni çıkar (sayfa marker'ları dahil)
            // Bu sayede RAGChunker sayfa numaralarını doğru parse edebilir
            let fullText = PDFService.shared.extractText(from: document)

            guard !fullText.isEmpty else {
                logWarning("LibraryViewModel", "PDF'den metin çıkarılamadı - RAG indexing için")
                return
            }

            logInfo("LibraryViewModel", "RAG indexing başlatılıyor",
                    details: "\(document.pageCount) sayfa, ~\(fullText.count) karakter")

            try await RAGService.shared.indexDocument(text: fullText, fileId: UUID(uuidString: metadata.id)!)
            
            logInfo("LibraryViewModel", "RAG indexing tamamlandı", details: metadata.name)
        } catch {
            logError("LibraryViewModel", "RAG indexing hatası", error: error)
        }
    }

    private func handleUploadError(_ error: Error, url: URL, userId: String) {
        let appError: AppError
        if error is UploadError {
            appError = AppError.storage(reason: .accessDenied, underlying: error)
        } else {
            appError = ErrorHandlingService.mapToAppError(error)
        }
        errorMessage = appError.localizedDescription
        ErrorHandlingService.shared.handle(
            appError,
            context: .init(
                source: "LibraryViewModel",
                operation: "UploadFile"
            ) { [weak self] in
                Task { await self?.uploadFile(url: url, userId: userId) }
                return
            }
        )
    }

    /// AI ile etiketler oluştur ve dosyaya ata
    func generateAndAssignTags(for file: PDFDocumentMetadata, pdfData: Data) async {
        do {
            guard let document = PDFDocument(data: pdfData) else {
                logWarning("LibraryViewModel", "PDF oluşturulamadı - etiketleme için")
                return
            }

            let text = extractTextForSummary(from: document)
            guard !text.isEmpty else {
                logWarning("LibraryViewModel", "PDF'den metin çıkarılamadı - etiketleme için")
                return
            }

            let existingTagNames = allTags.map { $0.name }
            let aiResult = try await GeminiService.shared.generateTags(
                text,
                existingTags: existingTagNames
            )

            var tagIds: [UUID] = []
            for tagName in aiResult.tags {
                let tag = try await supabaseService.getOrCreateTag(name: tagName)
                tagIds.append(tag.id)
            }

            try await supabaseService.addTagsToFile(fileId: file.id, tagIds: tagIds)
            try await supabaseService.updateFileCategory(fileId: file.id, category: aiResult.category)

            if let index = files.firstIndex(where: { $0.id == file.id }) {
                files[index].tags = try await supabaseService.getFileTags(fileId: file.id)
                files[index].aiCategory = aiResult.category
            }

            allTags = try await supabaseService.listTags()

            logInfo(
                "LibraryViewModel",
                "AI etiketleme tamamlandı",
                details: "\(tagIds.count) etiket eklendi"
            )
        } catch {
            logError("LibraryViewModel", "AI etiketleme hatası", error: error)
        }
    }
}
