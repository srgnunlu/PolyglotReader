import Foundation

@MainActor
extension ChatViewModel {
    // MARK: - Send Message (RAG Enhanced + Image Aware)

    func sendMessage(_ text: String? = nil) async {
        guard let textToSend = validatedUserInput(text) else { return }

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

        do {
            let response = try await streamModelResponse(for: userText)
            saveChatMessage(role: "model", content: response)
        } catch {
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

    private func streamModelResponse(for userText: String) async throws -> String {
        let aiMessageId = startModelMessage()
        let stream = try await getResponseStream(for: userText)
        var fullResponse = ""
        var lastUpdateTime = Date()
        let updateInterval: TimeInterval = 0.05 // 50ms - UI update throttle

        defer { isLoading = false }

        for try await chunk in stream {
            fullResponse += chunk
            
            // Throttle UI updates to prevent lag during fast streaming
            let now = Date()
            if now.timeIntervalSince(lastUpdateTime) >= updateInterval {
                updateModelMessage(id: aiMessageId, text: fullResponse)
                lastUpdateTime = now
            }
        }
        
        // Final update to ensure complete response is shown
        updateModelMessage(id: aiMessageId, text: fullResponse)

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
            return try await geminiService.sendMessageStream(userText)
        }

        // P0: Indexleme durumu kontrolü
        if !isDocumentIndexed {
            logInfo("ChatViewModel", "Doküman henüz indexlenmemiş, legacy mod kullanılıyor")

            // Indexleme devam ediyorsa, kullanıcıya bilgi ver
            if isIndexing {
                return legacyModeWithWarning(
                    userText: userText,
                    warning: "⏳ Doküman hazırlanıyor. Şu an genel yanıt alıyorsunuz, hazırlık bitince daha doğru yanıtlar alacaksınız."
                )
            }

            // Indexleme yapılmamış - legacy mod
            return try await geminiService.sendMessageStream(userText)
        }

        logRagQuery(fileUUID: fileUUID, userText: userText)

        let (ragContext, chunks) = try await ragService.performRAGQuery(
            query: userText,
            fileId: fileUUID,
            enableRerank: isDeepSearchEnabled,
            enableQueryExpansion: isDeepSearchEnabled
        )

        let imageMatches = await fetchImageMatches(for: userText)
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
        return AsyncThrowingStream { continuation in
            Task {
                // Önce uyarı mesajı
                continuation.yield(warning + "\n\n")

                // Sonra genel yanıt (chat session ile)
                do {
                    let stream = try await self.geminiService.sendMessageStream(userText)
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// RAG chunk bulunamadığında fallback yanıt
    private func fallbackResponseStream(for userText: String) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                // Önce bilgi mesajı
                let info = "📝 Bu soru için dokümanda doğrudan bir bilgi bulamadım, genel bilgilerimle yanıtlıyorum:\n\n"
                continuation.yield(info)

                // Sonra genel yanıt
                do {
                    let stream = try await self.geminiService.sendMessageStream(userText)
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
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
        return try await geminiService.sendMessageStreamWithContext(userText, context: context)
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
