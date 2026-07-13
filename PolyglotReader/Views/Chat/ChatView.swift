import SwiftUI
import UIKit // UIPasteboard + UIImage

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    let onNavigateToPage: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isInputFocused: Bool

    /// AI yanıtlarını sesli okumak için (Reader'daki SpeechService'in chat'e
    /// bağlanmış hali) — balon menüsünden "Sesli Oku".
    @StateObject private var speech = SpeechService()

    /// Sesli girdi (mikrofon → composer).
    @StateObject private var speechRecognizer = SpeechRecognitionService()

    // Sohbet içi arama durumu.
    @State private var isSearchActive = false
    @State private var searchQuery = ""

    // Scroll throttle için debounce state
    @State private var lastScrollTime: Date = .distantPast
    private let scrollDebounceInterval: TimeInterval = 0.1 // 100ms debounce

    /// Alt sınır görünür mü? Kullanıcı eski mesajları okurken akış onu
    /// aşağı çekmesin; ayrıca "sona git" butonunun görünürlüğünü belirler.
    @State private var isNearBottom = true
    @State private var showClearConfirmation = false
    private let bottomAnchorID = "chat_bottom_anchor"

    // MARK: - Computed Properties
    /// Seçili görselin UIImage'ı
    private var selectedUIImage: UIImage? {
        guard let data = viewModel.selectedImage else { return nil }
        return UIImage(data: data)
    }

    private var canSend: Bool {
        viewModel.canSubmitMessage
    }

    private var hasConversation: Bool {
        !viewModel.conversationMessages.isEmpty
    }

    /// Arama aktifken yalnız eşleşen mesajlar listelenir.
    private var visibleMessages: [ChatMessage] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        let messages = viewModel.conversationMessages
        guard isSearchActive, !query.isEmpty else { return messages }
        return messages.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    /// The animated dots bridge only the time before the first response
    /// token. Once a model bubble exists, that bubble itself communicates the
    /// ongoing stream and a second indicator would look like a duplicate reply.
    private var shouldShowTypingIndicator: Bool {
        guard viewModel.isLoading else { return false }
        guard let lastMessage = viewModel.messages.last else { return true }
        return lastMessage.role != .model || lastMessage.text.isEmpty
    }

    /// Akış hâlâ sürerken son model mesajı "yazılıyor" kabul edilir —
    /// balonun alt kenarındaki yumuşak maske bu bayrakla açılıp kapanır.
    private func isStreamingMessage(_ message: ChatMessage) -> Bool {
        viewModel.isLoading
            && message.role == .model
            && message.id == viewModel.messages.last?.id
    }

    /// "Yanıtı Yeniden Oluştur" yalnız son (tamamlanmış) AI yanıtında sunulur.
    private func isLastModelMessage(_ message: ChatMessage) -> Bool {
        message.role == .model
            && message.isError != true
            && message.id == viewModel.messages.last?.id
            && !viewModel.isLoading
    }

    /// Kullanıcı balonu input alanından "uçarak" gelir (mikro-uçuş);
    /// model balonu akışla zaten yumuşak girdiğinden sade fade alır.
    private func bubbleTransition(for message: ChatMessage) -> AnyTransition {
        guard message.role == .user, !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.85, anchor: .bottomTrailing)
                .combined(with: .offset(y: 24))
                .combined(with: .opacity),
            removal: .opacity
        )
    }

    /// Zaman damgası yalnız konuşma kırılımlarında gösterilir: rol değişimi,
    /// 5 dakikadan uzun ara veya son mesaj — WhatsApp/iMessage dili.
    private func showsTimestamp(at index: Int) -> Bool {
        let messages = viewModel.conversationMessages
        guard index < messages.count else { return false }
        if index == messages.count - 1 { return true }

        let current = messages[index]
        let next = messages[index + 1]
        if next.role != current.role { return true }
        return next.timestamp.timeIntervalSince(current.timestamp) > 300
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background to cover safe area
                Color(.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    if isSearchActive {
                        ChatSearchBar(
                            query: $searchQuery,
                            matchCount: visibleMessages.count
                        ) {
                            withAnimation(DSMotion.snappy) {
                                isSearchActive = false
                                searchQuery = ""
                            }
                        }
                    }

                    messagesArea

                    inputArea
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if hasConversation {
                        Menu {
                            Button {
                                withAnimation(DSMotion.snappy) {
                                    isSearchActive.toggle()
                                    if !isSearchActive { searchQuery = "" }
                                }
                            } label: {
                                Label("chat.search".localized, systemImage: "magnifyingglass")
                            }

                            ShareLink(item: viewModel.exportTranscript) {
                                Label("chat.export".localized, systemImage: "square.and.arrow.up")
                            }

                            Divider()

                            Button(role: .destructive) {
                                showClearConfirmation = true
                            } label: {
                                Label("chat.clear.title".localized, systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("chat.actions".localized)
                        .accessibilityIdentifier("chat_actions_menu")
                    }
                }

                ToolbarItem(placement: .principal) {
                    HStack(spacing: DSSpacing.xs) {
                        Circle()
                            .fill(DSColor.brandGradient)
                            .frame(width: 30, height: 30)
                            .overlay {
                                Image(systemName: "sparkles")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                            }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("chat.assistant_name".localized)
                                .font(.subheadline.weight(.semibold))
                            Text(
                                viewModel.isLoading
                                    ? "chat.status.thinking".localized
                                    : "chat.status.ready".localized
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("chat.accessibility.close".localized)
                    .accessibilityIdentifier("close_chat_button")
                }
            }
            .confirmationDialog(
                "chat.clear.confirm".localized,
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("chat.clear.title".localized, role: .destructive) {
                    Task { await viewModel.clearChatHistory() }
                }
                Button("common.cancel".localized, role: .cancel) {}
            }
            // Leaving the chat must tear down the in-flight stream so it
            // doesn't keep mutating the message list in the background.
            .onDisappear {
                viewModel.cancelActiveStream()
                speech.stop()
                speechRecognizer.stop()
            }
            // Canlı dikte: kayıt sürerken transcript composer'a akar; kayıt
            // bittikten sonra kullanıcı metni serbestçe düzenleyebilir.
            .onChange(of: speechRecognizer.transcript) { transcript in
                guard speechRecognizer.isRecording, !transcript.isEmpty else { return }
                viewModel.inputText = transcript
            }
            // Persisted history loads once per reader session; the skeleton
            // above covers the fetch window.
            .task {
                await viewModel.loadHistoryIfNeeded()
                // Boş sohbette klavye hazır beklesin; geçmiş varsa okuma
                // alanını klavye ile daraltma.
                if viewModel.conversationMessages.isEmpty {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    isInputFocused = true
                }
            }
        }
    }
}

// MARK: - Chat Sections

private extension ChatView {
    // MARK: - Messages Area

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DSSpacing.sm) {
                    // Geçmiş yüklenirken balon iskeletleri (yalnız içerik iskeletlenir).
                    if viewModel.isLoadingHistory && viewModel.conversationMessages.isEmpty {
                        ChatHistorySkeleton()
                    }

                    if viewModel.conversationMessages.isEmpty
                        && !viewModel.isLoading
                        && !viewModel.isLoadingHistory {
                        emptyConversation
                    }

                    ForEach(Array(visibleMessages.enumerated()), id: \.element.id) { index, message in
                        MessageBubble(
                            message: message,
                            isStreaming: isStreamingMessage(message),
                            showsActions: message.role == .model
                                && message.isError != true
                                && !isStreamingMessage(message),
                            // Arama modunda indeksler filtreli listeye ait olduğundan
                            // zaman damgası kırılım hesabı anlamsızlaşır — gizlenir.
                            showsTimestamp: isSearchActive ? false : showsTimestamp(at: index),
                            onSpeak: { text in
                                speech.stop()
                                speech.speak(text)
                            },
                            onRegenerate: isLastModelMessage(message) ? {
                                Task { await viewModel.regenerateLastResponse() }
                            } : nil,
                            onRetry: message.isError == true ? {
                                Task { await viewModel.retryLastFailedMessage() }
                            } : nil,
                            onNavigateToPage: onNavigateToPage
                        )
                        .id(message.id)
                        .transition(bubbleTransition(for: message))
                        // Arama modunda sonuca dokunmak aramayı kapatıp
                        // konuşmadaki yerine kaydırır.
                        .onTapGesture {
                            guard isSearchActive else { return }
                            let targetId = message.id
                            withAnimation(DSMotion.snappy) {
                                isSearchActive = false
                                searchQuery = ""
                            }
                            DispatchQueue.main.async {
                                withAnimation(reduceMotion ? nil : .default) {
                                    proxy.scrollTo(targetId, anchor: .center)
                                }
                            }
                        }
                    }

                    if isSearchActive,
                       !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty,
                       visibleMessages.isEmpty {
                        Text("chat.search.no_results".localized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, DSSpacing.lg)
                    }

                    if shouldShowTypingIndicator {
                        TypingIndicator()
                    }

                    // Alt sınır nöbetçisi: görünürlüğü "sona git" butonunu
                    // ve otomatik kaydırma iznini yönetir.
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorID)
                        .onAppear { isNearBottom = true }
                        .onDisappear { isNearBottom = false }
                }
                .padding()
                .dsAnimation(DSMotion.snappy, value: viewModel.messages.count)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .bottomTrailing) {
                if !isNearBottom {
                    scrollToBottomButton(proxy: proxy)
                }
            }
            .onChange(of: viewModel.messages.count) { _ in
                guard let lastMessage = viewModel.messages.last else { return }
                // Kullanıcı yukarıda eski mesajları okuyorsa akış onu aşağı
                // çekmez; kendi gönderdiği mesaj her zaman görünür kılınır.
                if isNearBottom || lastMessage.role == .user {
                    withAnimation(reduceMotion ? nil : .default) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.messages.last?.text) { _ in
                // Debounce scroll updates during streaming to prevent lag
                let now = Date()
                guard now.timeIntervalSince(lastScrollTime) >= scrollDebounceInterval else { return }
                lastScrollTime = now

                if let lastMessage = viewModel.messages.last, isNearBottom {
                    // No animation for streaming updates to avoid jitter
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
            // Sheet açılışında konuşma en son mesajdan başlar — geçmiş zaten
            // bellekteyse onChange tetiklenmediği için burada elle kaydırılır.
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            }
            // Geçmiş Supabase'den ilk kez yüklendiğinde de en alta in.
            .onChange(of: viewModel.isLoadingHistory) { loading in
                guard !loading else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            }
        }
    }

    private func scrollToBottomButton(proxy: ScrollViewProxy) -> some View {
        Button {
            DSHaptics.lightImpact()
            withAnimation(reduceMotion ? nil : .default) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(Color(.separator).opacity(0.5), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(DSPressableButtonStyle())
        .padding(.trailing, DSSpacing.md)
        .padding(.bottom, DSSpacing.sm)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
        .accessibilityLabel("chat.scroll_to_bottom".localized)
    }

    // MARK: - Suggestion Cards (boş sohbet)

    private var emptyConversation: some View {
        VStack(spacing: DSSpacing.lg) {
            VStack(spacing: DSSpacing.sm) {
                Circle()
                    .fill(DSColor.brandGradient)
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: DSColor.brand.opacity(0.24), radius: 18, y: 8)
                    .accessibilityHidden(true)

                Text("chat.empty.title".localized)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("chat.empty.subtitle".localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, DSSpacing.lg)

            suggestionCards
        }
        .frame(maxWidth: 620)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var suggestionCards: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Text("chat.suggestions.header".localized)
                .font(DSFont.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.top, DSSpacing.sm)
                .padding(.leading, DSSpacing.xxs)

            ForEach(viewModel.currentSuggestions) { suggestion in
                Button {
                    DSHaptics.lightImpact()
                    Task {
                        await viewModel.sendMessage(suggestion.prompt)
                    }
                } label: {
                    HStack(spacing: DSSpacing.sm) {
                        Image(systemName: suggestion.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DSColor.brand)
                            .frame(width: 34, height: 34)
                            .background(DSColor.brand.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: DSRadius.small - 4))

                        Text(suggestion.label)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: DSSpacing.xs)

                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(DSSpacing.sm)
                    .background(DSColor.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: DSRadius.small))
                    .overlay {
                        RoundedRectangle(cornerRadius: DSRadius.small)
                            .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: DSRadius.small))
                }
                .buttonStyle(DSPressableButtonStyle())
                .accessibilityLabel(suggestion.label)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 0) {
            // Indexleme durumu (P0)
            IndexingStatusBanner(viewModel: viewModel)

            // Image Selection Info Bar
            if viewModel.selectedImage != nil, let uiImage = selectedUIImage {
                ChatImageSelectionBar(viewModel: viewModel, uiImage: uiImage)
            }

            // Text Selection Info Bar
            if let selectedText = viewModel.selectedText, !selectedText.isEmpty {
                ChatTextSelectionBar(viewModel: viewModel, selectedText: selectedText)
            }

            // Derin Arama aktif rozeti — kompozerin üstünde kompakt kapsül.
            if viewModel.isDeepSearchEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption2)
                    Text("chat.deep_search_active".localized)
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(DSColor.aiAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DSColor.aiAccent.opacity(0.10), in: Capsule())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, DSSpacing.xs)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }

            composer

            Text("chat.disclaimer".localized)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DSSpacing.lg)
                .padding(.bottom, DSSpacing.xs)
                .accessibilityLabel("chat.disclaimer".localized)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Composer
    /// Modern kompozer: büyüyen çok satırlı alan, gömülü gönder butonu ve
    /// solda kompakt derin arama anahtarı.
    private var composer: some View {
        HStack(alignment: .bottom, spacing: DSSpacing.xs) {
            // Derin Arama Toggle
            Button {
                withAnimation(DSMotion.resolved(DSMotion.snappy, reduceMotion: reduceMotion)) {
                    viewModel.isDeepSearchEnabled.toggle()
                }
            } label: {
                Image(
                    systemName: viewModel.isDeepSearchEnabled
                        ? "brain.head.profile.fill"
                        : "brain.head.profile"
                )
                .font(.body.weight(.medium))
                .foregroundStyle(viewModel.isDeepSearchEnabled ? DSColor.aiAccent : .secondary)
                .frame(width: 38, height: 38)
                .background(
                    viewModel.isDeepSearchEnabled
                        ? DSColor.aiAccent.opacity(0.12)
                        : Color(.tertiarySystemFill),
                    in: Circle()
                )
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSPressableButtonStyle())
            .dsHaptic(.selection, trigger: viewModel.isDeepSearchEnabled)
            .accessibilityLabel("chat.accessibility.deep_search".localized)
            .accessibilityValue(
                viewModel.isDeepSearchEnabled
                    ? "chat.accessibility.deep_search.on".localized
                    : "chat.accessibility.deep_search.off".localized
            )
            .accessibilityIdentifier("deep_search_toggle")
            .disabled(viewModel.isLoading)
            .opacity(viewModel.isLoading ? 0.55 : 1)

            // Büyüyen giriş kapsülü + gömülü gönder butonu
            HStack(alignment: .bottom, spacing: DSSpacing.xxs) {
                ChatPhotoPickerButton(viewModel: viewModel)
                    .padding(.leading, DSSpacing.xxs)
                    .disabled(viewModel.isLoading)
                    .opacity(viewModel.isLoading ? 0.55 : 1)

                TextField("chat.placeholder".localized, text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.vertical, 10)
                    .focused($isInputFocused)
                    .accessibilityIdentifier("chat_input_field")

                ChatMicButton(recognizer: speechRecognizer)
                    .disabled(viewModel.isLoading)
                    .opacity(viewModel.isLoading ? 0.55 : 1)

                Button {
                    DSHaptics.lightImpact()
                    speechRecognizer.stop()

                    if viewModel.isLoading {
                        viewModel.cancelActiveStream()
                        return
                    }

                    Task {
                        if viewModel.selectedImage != nil {
                            await viewModel.sendMessageWithImage()
                        } else {
                            await viewModel.sendMessage()
                        }
                    }
                } label: {
                    Image(systemName: viewModel.isLoading ? "stop.fill" : "arrow.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(
                            viewModel.isLoading
                                ? Color(.systemBackground)
                                : .white
                        )
                        .frame(width: 32, height: 32)
                        .background(
                            viewModel.isLoading
                                ? AnyShapeStyle(Color(.label))
                                : canSend
                                ? AnyShapeStyle(DSColor.brandGradient)
                                : AnyShapeStyle(Color(.systemGray3)),
                            in: Circle()
                        )
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DSPressableButtonStyle())
                .disabled(!viewModel.isLoading && !canSend)
                .dsAnimation(DSMotion.snappy, value: canSend)
                .dsAnimation(DSMotion.snappy, value: viewModel.isLoading)
                .accessibilityLabel(
                    viewModel.isLoading
                        ? "chat.stop_generation".localized
                        : "chat.accessibility.send".localized
                )
                .accessibilityHint(
                    viewModel.isLoading
                        ? "chat.stop_generation.hint".localized
                        : "chat.accessibility.send.hint".localized
                )
                .accessibilityIdentifier(
                    viewModel.isLoading ? "stop_response_button" : "send_message_button"
                )
            }
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, DSSpacing.xs + 2)
    }
}

#Preview {
    ChatView(
        viewModel: ChatViewModel(fileId: "test")
    ) { _ in }
}
