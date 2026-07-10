import Foundation
import PDFKit

@MainActor
extension ChatViewModel {
    // MARK: - Send Message With Image

    /// Görsel ile birlikte soru gönder
    func sendMessageWithImage(_ text: String? = nil) async {
        guard let textToSend = validatedUserInput(text) else { return }
        guard let imageData = selectedImage else {
            await sendMessage(text)
            return
        }

        // An image question supersedes any response still streaming in.
        cancelActiveStream()

        clearImageInput(after: text)
        appendImageUserMessage(textToSend)
        isLoading = true

        await handleImageResponse(imageData: imageData, question: textToSend)
    }

    private func clearImageInput(after text: String?) {
        if text == nil {
            inputText = ""
        }
        selectedImage = nil
    }

    private func appendImageUserMessage(_ text: String) {
        messages.append(ChatMessage(role: .user, text: "📷 [Görsel] \(text)"))
        saveChatMessage(role: "user", content: text)
    }

    private func handleImageResponse(imageData: Data, question: String) async {
        defer { isLoading = false }

        do {
            let response = try await geminiService.askAboutImage(imageData, question: question, fileId: fileId)
            messages.append(ChatMessage(role: .model, text: response))
            saveChatMessage(role: "model", content: response)
        } catch {
            handleImageError(error)
        }
    }

    private func handleImageError(_ error: Error) {
        let appError = ErrorHandlingService.mapToAppError(error)
        errorMessage = appError.localizedDescription
        ErrorHandlingService.shared.handle(
            appError,
            context: .init(source: "ChatViewModel", operation: "ImageAnalysis")
        )
        let prefix = NSLocalizedString("chat.image_error.prefix", comment: "")
        let errorText = "\(prefix) \(appError.localizedDescription)"
        messages.append(ChatMessage(role: .model, text: errorText))
    }

    // MARK: - Load History

    /// Fetches the persisted chat history once per reader session; repeated
    /// sheet openings reuse the in-memory messages. A non-empty history
    /// replaces the welcome message wholesale.
    func loadHistoryIfNeeded() async {
        guard !hasLoadedHistory else { return }
        hasLoadedHistory = true

        isLoadingHistory = true
        defer { isLoadingHistory = false }

        do {
            let history = try await supabaseService.getChatHistory(fileId: fileId)
            if !history.isEmpty {
                messages = history
            }
        } catch {
            logWarning("ChatViewModel", "Chat geçmişi yüklenemedi", details: error.localizedDescription)
        }
    }

    // MARK: - Page Image Reference Detection

    func handlePageImageReferenceIfNeeded(_ userText: String) async -> Bool {
        guard let pageRef = detectPageImageReference(in: userText) else { return false }
        enqueueUserMessage(userText)
        isLoading = true
        await handlePageImageQuery(userText: userText, pageNumber: pageRef)
        return true
    }

    /// Mesajda sayfa görseli referansı var mı kontrol et
    /// Örnek: "sayfa 5'teki görseli açıkla", "3. sayfadaki tabloyu analiz et"
    private func detectPageImageReference(in text: String) -> Int? {
        guard let regex = pageReferenceRegex else { return nil }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        if let match = regex.firstMatch(in: text, options: [], range: range),
           let pageRange = Range(match.range(at: 1), in: text),
           let pageNumber = Int(text[pageRange]) {
            logInfo("ChatViewModel", "Sayfa görsel referansı algılandı", details: "Sayfa \(pageNumber)")
            return pageNumber
        }

        return nil
    }

    /// Sayfa görseli sorgusunu işle
    private func handlePageImageQuery(userText: String, pageNumber: Int) async {
        guard let context = resolvePageImageContext(pageNumber: pageNumber) else { return }

        let pageImages = await loadPageImages(
            pageNumber: pageNumber,
            document: context.document,
            fileUUID: context.fileUUID
        )
        guard !pageImages.isEmpty else {
            let message = "Sayfa \(pageNumber)'de tespit edilebilen bir görsel bulunamadı. " +
                "Sayfada metin dışında görsel içerik olmayabilir veya format desteklenmiyor olabilir."
            handlePageImageFailure(message)
            return
        }

        let imagesWithData = renderImages(
            from: pageImages,
            pageNumber: pageNumber,
            document: context.document
        )
        guard !imagesWithData.isEmpty else {
            handlePageImageFailure("Sayfa \(pageNumber)'deki görseller işlenemedi.")
            return
        }

        await respondToPageImages(
            userText: userText,
            imagesWithData: imagesWithData,
            pageNumber: pageNumber,
            pageImages: pageImages,
            context: context
        )
    }

    private func resolvePageImageContext(
        pageNumber: Int
    ) -> (document: PDFDocument, fileUUID: UUID)? {
        guard let document = pdfDocument,
              let fileUUID = UUID(uuidString: fileId),
              pageNumber > 0,
              pageNumber <= document.pageCount else {
            handlePageImageFailure("Belirtilen sayfa bulunamadı.")
            return nil
        }
        return (document, fileUUID)
    }

    private func loadPageImages(
        pageNumber: Int,
        document: PDFDocument,
        fileUUID: UUID
    ) async -> [PDFImageMetadata] {
        var pageImages = cachedImageMetadata.filter { $0.pageNumber == pageNumber }
        if pageImages.isEmpty, let page = document.page(at: pageNumber - 1) {
            pageImages = await imageService.extractImagesFromPage(
                page,
                pageNumber: pageNumber,
                fileId: fileUUID
            )
        }
        return pageImages
    }

    private func renderImages(
        from pageImages: [PDFImageMetadata],
        pageNumber: Int,
        document: PDFDocument
    ) -> [(data: Data, caption: String?)] {
        var imagesWithData: [(data: Data, caption: String?)] = []

        for imageMetadata in pageImages {
            guard let bounds = imageMetadata.bounds,
                  let page = document.page(at: pageNumber - 1),
                  let renderedImage = imageService.renderRegionFullSize(
                    rect: bounds.cgRect,
                    in: page
                  ),
                  let jpegData = renderedImage.jpegData(compressionQuality: 0.85) else {
                continue
            }

            imagesWithData.append((data: jpegData, caption: imageMetadata.caption))
        }

        return imagesWithData
    }

    private func respondToPageImages(
        userText: String,
        imagesWithData: [(data: Data, caption: String?)],
        pageNumber: Int,
        pageImages: [PDFImageMetadata],
        context: (document: PDFDocument, fileUUID: UUID)
    ) async {
        defer { isLoading = false }

        do {
            let response = try await geminiService.askWithPageImages(
                userText,
                images: imagesWithData,
                pageNumber: pageNumber,
                fileId: fileId
            )

            messages.append(ChatMessage(role: .model, text: response))
            saveChatMessage(role: "model", content: response)

            Task.detached(priority: .background) {
                await self.lazyAnalyzePageImages(
                    pageImages,
                    document: context.document
                )
            }
        } catch {
            handlePageImageFailure("Görsel analizi sırasında hata oluştu: \(error.localizedDescription)")
        }
    }

    private func handlePageImageFailure(_ message: String) {
        messages.append(ChatMessage(role: .model, text: message))
        isLoading = false
    }

    // MARK: - Image Metadata Management

    /// Dosyadaki görsel metadata'larını yükle veya oluştur
    /// NOT: Bu fonksiyon artık lazy olarak çağrılıyor - sadece görsel referansı algılandığında
    func loadImageMetadata(document: PDFDocument) async {
        // Zaten yüklendi veya işlem devam ediyor ise tekrar çalıştırma
        guard !imageMetadataLoaded, !imageExtractionInProgress else {
            logDebug("ChatViewModel", "Görsel metadata zaten yüklendi veya işlem devam ediyor")
            return
        }
        
        self.pdfDocument = document

        guard let fileUUID = UUID(uuidString: fileId) else { return }

        do {
            let existing = try await supabaseService.getImageMetadata(fileId: fileId)

            if !existing.isEmpty {
                cachedImageMetadata = existing
                imageMetadataLoaded = true
                logInfo("ChatViewModel", "Görsel metadata yüklendi", details: "\(existing.count) adet")
            }
            // NOT: Otomatik tarama devre dışı - performans sorunu
            // Görseller sadece kullanıcı açıkça istediğinde lazy load edilecek
            // else {
            //     Task.detached(priority: .background) {
            //         await self.extractAndSaveImageMetadata(document: document, fileId: fileUUID)
            //     }
            // }
        } catch {
            logWarning("ChatViewModel", "Görsel metadata yüklenemedi", details: error.localizedDescription)
        }
    }

    /// PDF'deki görselleri tara ve kaydet
    /// NOT: Bu fonksiyon artık kullanılmıyor - performans sorunu
    /// Görseller sadece sayfa bazında lazy load ediliyor
    private func extractAndSaveImageMetadata(document: PDFDocument, fileId: UUID) async {
        // Guard: Tekrar taramayı önle
        guard !imageExtractionInProgress else {
            logDebug("ChatViewModel", "Görsel tarama zaten devam ediyor, atlanıyor")
            return
        }
        
        await MainActor.run { imageExtractionInProgress = true }
        defer {
            Task { @MainActor in imageExtractionInProgress = false }
        }
        
        let images = await imageService.extractAllImages(from: document, fileId: fileId)
        guard !images.isEmpty else { return }

        do {
            try await supabaseService.saveImageMetadata(images)
            await MainActor.run {
                cachedImageMetadata = images
                imageMetadataLoaded = true
            }
            logInfo("ChatViewModel", "Görsel metadata kaydedildi", details: "\(images.count) adet")
        } catch {
            logWarning("ChatViewModel", "Görsel metadata kaydedilemedi", details: error.localizedDescription)
        }
    }

    /// Henüz analiz edilmemiş görselleri arka planda analiz et.
    /// Analiz/persist işi `PDFImageAnalysisService`'e devredildi; burada yalnızca
    /// sonuçlar view model'in cache'ine yansıtılır.
    private func lazyAnalyzePageImages(_ images: [PDFImageMetadata], document: PDFDocument) async {
        let results = await imageAnalysisService.analyzeUnanalyzedImages(images, document: document)
        updateImageCache(results)
    }

    private func updateImageCache(_ results: [ImageAnalysisResult]) {
        for result in results {
            if let index = cachedImageMetadata.firstIndex(where: { $0.id == result.imageId }) {
                cachedImageMetadata[index].caption = result.caption
                cachedImageMetadata[index].analyzedAt = result.analyzedAt
            }
        }
    }
}
