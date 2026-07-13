import Foundation
import Combine

// MARK: - Library Chat ViewModel

/// Kütüphane geneli (çok doküman) sohbet. Tek dosyalık ChatViewModel'in
/// sade eşleniği: RAGLibraryService arama yapar, GeminiService kütüphane
/// oturumunda yanıtı stream'ler, geçmiş chats tablosunda file_id NULL
/// satırlar olarak saklanır.
@MainActor
final class LibraryChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isLoading = false
    @Published var isLoadingHistory = false
    @Published var errorMessage: String?

    /// Sohbete dahil dokümanlar (v1: kütüphanedeki tümü; alt küme seçimi
    /// gelecekte bu listeyi daraltarak eklenebilir).
    let files: [RAGLibraryService.LibraryFile]

    private let ragLibrary = RAGLibraryService.shared
    private let geminiService = GeminiService.shared
    private let supabaseService = SupabaseService.shared

    private var activeStreamTask: Task<Void, Never>?
    private var hasLoadedHistory = false
    var pendingRetryText: String?

    static let defaultSuggestions: [String] = [
        "Kütüphanemdeki dokümanların ortak temaları neler?",
        "Bu dokümanlar arasındaki temel farklar neler?",
        "Tüm dokümanlardan önemli bulguları özetle"
    ]

    init(documents: [PDFDocumentMetadata]) {
        self.files = documents.compactMap { document in
            guard let uuid = UUID(uuidString: document.id) else { return nil }
            return RAGLibraryService.LibraryFile(id: uuid, name: document.name)
        }
    }

    deinit {
        activeStreamTask?.cancel()
    }

    // MARK: - History

    func loadHistoryIfNeeded() async {
        guard !hasLoadedHistory else { return }
        hasLoadedHistory = true

        isLoadingHistory = true
        defer { isLoadingHistory = false }

        do {
            let history = try await supabaseService.getLibraryChatHistory()
            if !history.isEmpty {
                messages = history
                // Model de konuşmayı hatırlasın (tek dosyalık akışla aynı).
                let turns = history.map { (role: $0.role.rawValue, text: $0.text) }
                geminiService.seedPersistedChatHistory(
                    fileId: GeminiChatService.librarySessionKey,
                    turns: turns
                )
            }
        } catch {
            logWarning("LibraryChatVM", "Kütüphane sohbeti yüklenemedi", details: error.localizedDescription)
        }
    }

    func clearChatHistory() async {
        cancelActiveStream()
        do {
            try await supabaseService.deleteLibraryChats()
            messages.removeAll()
            geminiService.resetLibraryChatSession()
        } catch {
            let appError = ErrorHandlingService.mapToAppError(error)
            errorMessage = appError.localizedDescription
        }
    }

    // MARK: - Messaging

    func sendMessage(_ text: String? = nil) async {
        guard !isLoading else { return }
        let candidate = text ?? inputText
        let userText = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userText.isEmpty else { return }

        cancelActiveStream()
        if text == nil { inputText = "" }

        messages.append(ChatMessage(role: .user, text: userText))
        persist(role: "user", content: userText)

        await runTrackedStream(for: userText)
    }

    func retryLastFailedMessage() async {
        guard !isLoading, let userText = pendingRetryText else { return }
        pendingRetryText = nil
        if let last = messages.last, last.isError == true {
            messages.removeLast()
        }
        await runTrackedStream(for: userText)
    }

    func regenerateLastResponse() async {
        guard !isLoading else { return }
        guard let lastUserIndex = messages.lastIndex(where: { $0.role == .user }) else { return }

        cancelActiveStream()
        let userText = messages[lastUserIndex].text
        if lastUserIndex + 1 < messages.count {
            messages.removeSubrange((lastUserIndex + 1)...)
        }
        await runTrackedStream(for: userText)
    }

    func cancelActiveStream() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
        isLoading = false
    }

    /// Konuşmayı Markdown'a çevirir (toolbar dışa aktarma).
    var exportTranscript: String {
        var lines = ["# Corio AI Kütüphane Sohbeti", ""]
        for message in messages where message.isError != true {
            let speaker = message.role == .user ? "Sen" : "Corio AI"
            lines.append("**\(speaker)**")
            lines.append("")
            lines.append(message.text)
            lines.append("")
            lines.append("---")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func runTrackedStream(for userText: String) async {
        isLoading = true
        let task = Task { [weak self] in
            guard let self else { return }
            await self.streamResponse(for: userText)
        }
        activeStreamTask = task
        await task.value
        if activeStreamTask == task {
            activeStreamTask = nil
        }
    }

    private func streamResponse(for userText: String) async {
        do {
            let (context, _) = try await ragLibrary.performLibraryQuery(query: userText, files: files)
            try Task.checkCancellation()

            let stream = geminiService.sendLibraryMessageStream(userText, context: context)

            var fullResponse = ""
            var messageId: String?
            var lastUpdate = Date.distantPast

            defer {
                isLoading = false
                if let id = messageId {
                    updateModelMessage(id: id, text: fullResponse)
                }
            }

            for try await chunk in stream {
                try Task.checkCancellation()
                fullResponse += chunk
                if messageId == nil {
                    let id = UUID().uuidString
                    messages.append(ChatMessage(id: id, role: .model, text: ""))
                    messageId = id
                }
                let now = Date()
                if let id = messageId, now.timeIntervalSince(lastUpdate) >= 0.08 {
                    updateModelMessage(id: id, text: fullResponse)
                    lastUpdate = now
                }
            }

            try Task.checkCancellation()
            persist(role: "model", content: fullResponse)
        } catch is CancellationError {
            isLoading = false
        } catch {
            guard !Task.isCancelled else {
                isLoading = false
                return
            }
            isLoading = false
            pendingRetryText = userText
            let appError = ErrorHandlingService.mapToAppError(error)
            errorMessage = appError.localizedDescription
            let prefix = NSLocalizedString("chat.error.prefix", comment: "")
            messages.append(ChatMessage(role: .model, text: "\(prefix) \(appError.localizedDescription)", isError: true))
        }
    }

    private func updateModelMessage(id: String, text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index] = ChatMessage(id: id, role: .model, text: text)
    }

    private func persist(role: String, content: String) {
        let supabase = supabaseService
        Task.detached(priority: .background) {
            do {
                try await supabase.saveLibraryChatMessage(role: role, content: content)
            } catch {
                await MainActor.run {
                    logWarning(
                        "LibraryChatVM",
                        "Kütüphane sohbet mesajı kaydedilemedi",
                        details: error.localizedDescription
                    )
                }
            }
        }
    }
}
