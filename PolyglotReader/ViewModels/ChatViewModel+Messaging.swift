import Foundation

@MainActor
extension ChatViewModel {
    // MARK: - Send Message (RAG Enhanced + Image Aware)

    func sendMessage(_ text: String? = nil) async {
        guard let textToSend = validatedUserInput(text) else { return }

        // A new message supersedes any response still streaming in.
        cancelActiveStream()

        let userText = prepareUserText(textToSend, context: selectedText)
        clearInput(after: text)

        if await handlePageImageReferenceIfNeeded(userText) {
            return
        }

        await handleStandardMessage(userText)
    }

    private func prepareUserText(_ text: String, context: String?) -> String {
        guard let ctx = context else { return text }
        return "Bağlam: \"\(ctx)\"\n\n\(text)"
    }

    func validatedUserInput(_ text: String?) -> String? {
        // Prevent re-entrancy / double submission
        guard !isLoading else { return nil }

        let textToSend = text ?? inputText
        guard !textToSend.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        return textToSend
    }

    private func clearInput(after text: String?) {
        selectedText = nil
        if text == nil {
            inputText = ""
        }
    }

    private func handleStandardMessage(_ userText: String) async {
        enqueueUserMessage(userText)
        isLoading = true

        // Run the stream inside a tracked task so cancelActiveStream() can
        // tear it down (new message sent, or the chat sheet is dismissed).
        let task = Task { [weak self] in
            guard let self else { return }
            await self.streamAndPersistResponse(for: userText)
        }
        activeStreamTask = task
        await task.value
        if activeStreamTask == task {
            activeStreamTask = nil
        }
    }

    private func streamAndPersistResponse(for userText: String) async {
        do {
            let response = try await streamModelResponse(for: userText)
            try Task.checkCancellation()
            // Persist only the complete final response — never partial chunks.
            saveChatMessage(role: "model", content: response)
        } catch is CancellationError {
            // Cancelled mid-stream: partial text stays visible in the bubble,
            // but a cancelled response is not final, so nothing is persisted.
            isLoading = false
        } catch {
            guard !Task.isCancelled else {
                isLoading = false
                return
            }
            let retryAction = { [weak self] in
                Task { await self?.handleStandardMessage(userText) }
                return
            }
            handleError(error, retryAction: retryAction)
        }
    }

    func enqueueUserMessage(_ userText: String) {
        messages.append(ChatMessage(role: .user, text: userText))
        saveChatMessage(role: "user", content: userText)
    }

    /// UI update throttle for streaming: ~12 updates/sec keeps the markdown
    /// renderer responsive without visible chunk lag.
    private static let streamUIUpdateInterval: TimeInterval = 0.08

    /// Streams the model response into a single assistant bubble. The bubble
    /// is created on the first chunk, so a request that fails before any text
    /// arrives never leaves an empty bubble behind.
    private func streamModelResponse(for userText: String) async throws -> String {
        let stream = try await getResponseStream(for: userText)

        var fullResponse = ""
        var messageId: String?
        var lastUpdateTime = Date.distantPast

        defer {
            isLoading = false
            // Flush whatever arrived: the full text on success, or the partial
            // text when the stream errored or was cancelled mid-way.
            if let id = messageId {
                updateModelMessage(id: id, text: fullResponse)
            }
        }

        for try await chunk in stream {
            try Task.checkCancellation()
            fullResponse += chunk

            if messageId == nil {
                messageId = startModelMessage()
            }

            let now = Date()
            if let id = messageId, now.timeIntervalSince(lastUpdateTime) >= Self.streamUIUpdateInterval {
                updateModelMessage(id: id, text: fullResponse)
                lastUpdateTime = now
            }
        }

        // A cancelled consumer ends the stream without throwing; surface it
        // explicitly so the caller skips persistence.
        try Task.checkCancellation()
        return fullResponse
    }

    private func startModelMessage() -> String {
        let messageId = UUID().uuidString
        messages.append(ChatMessage(id: messageId, role: .model, text: ""))
        return messageId
    }

    private func updateModelMessage(id: String, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index] = ChatMessage(id: id, role: .model, text: text)
        if !text.isEmpty { isLoading = false }
    }

    func saveChatMessage(role: String, content: String) {
        // Use Task.detached with background priority to avoid blocking main thread
        // This prevents keyboard freezing when user is typing
        let fileIdCopy = fileId
        let supabase = supabaseService
        
        Task.detached(priority: .background) {
            do {
                try await supabase.saveChatMessage(
                    fileId: fileIdCopy,
                    role: role,
                    content: content
                )
            } catch {
                // Log on main actor if needed but don't block
                await MainActor.run {
                    logWarning(
                        "ChatViewModel",
                        "Chat mesajı kaydedilemedi",
                        details: error.localizedDescription
                    )
                }
            }
        }
    }

    private func handleError(_ error: Error, retryAction: (() -> Void)? = nil) {
        isLoading = false
        let appError = ErrorHandlingService.mapToAppError(error)
        errorMessage = appError.localizedDescription
        ErrorHandlingService.shared.handle(
            appError,
            context: .init(
                source: "ChatViewModel",
                operation: "SendMessage",
                retryAction: retryAction
            )
        )
        let prefix = NSLocalizedString("chat.error.prefix", comment: "")
        let errorText = "\(prefix) \(appError.localizedDescription)"
        let errorMsg = ChatMessage(role: .model, text: errorText)
        messages.append(errorMsg)
    }

    private func getResponseStream(for userText: String) async throws -> AsyncThrowingStream<String, Error> {
        guard isRAGEnabled, let fileUUID = UUID(uuidString: fileId) else {
            return try await geminiService.sendMessageStream(userText, fileId: fileId)
        }

        // P0: Indexleme durumu kontrolü
        if !isDocumentIndexed {
            logInfo("ChatViewModel", "Doküman henüz indexlenmemiş, legacy mod kullanılıyor")

            // Indexleme devam ediyorsa, kullanıcıya bilgi ver
            if isIndexing {
                let warning = "⏳ Doküman hazırlanıyor. Şu an genel yanıt alıyorsunuz, " +
                    "hazırlık bitince daha doğru yanıtlar alacaksınız."
                return legacyModeWithWarning(userText: userText, warning: warning)
            }

            // Indexleme yapılmamış - legacy mod
            return try await geminiService.sendMessageStream(userText, fileId: fileId)
        }

        logRagQuery(fileUUID: fileUUID, userText: userText)

        // Image-caption search is independent of the RAG pipeline, so both
        // run concurrently instead of paying their latencies back to back.
        async let imageMatchesTask = fetchImageMatches(for: userText)

        let (ragContext, chunks) = try await ragService.performRAGQuery(
            query: userText,
            fileId: fileUUID,
            enableRerank: isDeepSearchEnabled,
            enableQueryExpansion: isDeepSearchEnabled
        )

        let imageMatches = await imageMatchesTask
        if let context = buildContext(ragContext: ragContext, imageMatches: imageMatches) {
            return try await sendStreamWithContext(
                userText: userText,
                context: context,
                chunkCount: chunks.count,
                imageCount: imageMatches?.count ?? 0
            )
        }

        logWarning("ChatViewModel", "RAG chunk bulunamadı, fallback yanıt")
        return fallbackResponseStream(for: userText)
    }

    /// Legacy mod (indexlenmemiş doküman) için uyarı ile yanıt
    private func legacyModeWithWarning(
        userText: String,
        warning: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                // Önce uyarı mesajı
                continuation.yield(warning + "\n\n")

                // Sonra genel yanıt (chat session ile)
                do {
                    let stream = try await self.geminiService.sendMessageStream(userText, fileId: self.fileId)
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// RAG chunk bulunamadığında fallback yanıt
    private func fallbackResponseStream(for userText: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                // Önce bilgi mesajı
                let info = "📝 Bu soru için dokümanda doğrudan bir bilgi bulamadım, " +
                    "genel bilgilerimle yanıtlıyorum:\n\n"
                continuation.yield(info)

                // Sonra genel yanıt
                do {
                    let stream = try await self.geminiService.sendMessageStream(userText, fileId: self.fileId)
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func logRagQuery(fileUUID: UUID, userText: String) {
        logDebug(
            "ChatVM",
            "RAG sorgusu",
            details: "FileID: \(fileUUID), Query: \(userText.prefix(20))..."
        )
    }

    private func fetchImageMatches(for userText: String) async -> [PDFImageMetadata]? {
        do {
            return try await searchImageCaptions(query: userText, fileId: fileId)
        } catch {
            logWarning(
                "ChatViewModel",
                "Görsel açıklama araması başarısız",
                details: error.localizedDescription
            )
            return nil
        }
    }

    private func buildContext(
        ragContext: String,
        imageMatches: [PDFImageMetadata]?
    ) -> String? {
        let hasContext = !ragContext.isEmpty || !(imageMatches?.isEmpty ?? true)
        guard hasContext else { return nil }

        var context = ragContext
        if let images = imageMatches, !images.isEmpty {
            context += "\n\n📷 İlgili Görseller:\n"
            for image in images {
                context += "- Sayfa \(image.pageNumber): \(image.caption ?? "Açıklama yok")\n"
            }
        }
        return context
    }

    private func sendStreamWithContext(
        userText: String,
        context: String,
        chunkCount: Int,
        imageCount: Int
    ) async throws -> AsyncThrowingStream<String, Error> {
        logInfo("ChatVM", "RAG devrede", details: "\(chunkCount) chunk, \(imageCount) img")
        return try await geminiService.sendMessageStreamWithContext(userText, context: context, fileId: fileId)
    }

    func sendSuggestion(_ prompt: String) async {
        inputText = prompt
        await sendMessage()
    }

    // MARK: - Image Caption Search (RAG Hybrid)

    private func searchImageCaptions(query: String, fileId: String) async throws -> [PDFImageMetadata] {
        let embedding = try await ragService.createEmbedding(for: query)
        return try await supabaseService.searchImageCaptions(
            embedding: embedding,
            fileId: fileId,
            limit: 5,
            threshold: 0.5
        )
    }
}
