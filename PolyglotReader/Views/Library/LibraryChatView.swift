import SwiftUI
import UIKit

// MARK: - Library Chat (multi-document)

/// Kütüphane geneli AI sohbeti: tüm dokümanlar üzerinde soru sor.
/// Tek dosyalık ChatView'ın bileşenlerini (MessageBubble, TypingIndicator)
/// yeniden kullanır; kaynak atıfları "(dosya.pdf, Sayfa 4)" formatındadır.
struct LibraryChatView: View {
    @StateObject private var viewModel: LibraryChatViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isInputFocused: Bool
    @State private var showClearConfirmation = false
    @State private var isNearBottom = true
    private let bottomAnchorID = "library_chat_bottom"

    init(documents: [PDFDocumentMetadata]) {
        _viewModel = StateObject(wrappedValue: LibraryChatViewModel(documents: documents))
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isLoading
    }

    private var shouldShowTypingIndicator: Bool {
        guard viewModel.isLoading else { return false }
        guard let lastMessage = viewModel.messages.last else { return true }
        return lastMessage.role != .model || lastMessage.text.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    messagesArea
                    VStack(spacing: 0) {
                        composer
                        Text("chat.disclaimer".localized)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DSSpacing.lg)
                            .padding(.bottom, DSSpacing.xs)
                    }
                        .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !viewModel.messages.isEmpty {
                        Menu {
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
                    }
                }

                ToolbarItem(placement: .principal) {
                    HStack(spacing: DSSpacing.xs) {
                        Circle()
                            .fill(DSColor.brandGradient)
                            .frame(width: 30, height: 30)
                            .overlay {
                                Image(systemName: "books.vertical.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                            }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("library_chat.assistant_name".localized)
                                .font(.subheadline.weight(.semibold))
                            Text(
                                viewModel.isLoading
                                    ? "library_chat.status.thinking".localized
                                    : String(
                                        format: "library_chat.status.ready".localized,
                                        viewModel.files.count
                                    )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
                }
            }
            .confirmationDialog(
                "library_chat.clear.confirm".localized,
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("chat.clear.title".localized, role: .destructive) {
                    Task { await viewModel.clearChatHistory() }
                }
                Button("common.cancel".localized, role: .cancel) {}
            }
            .onDisappear {
                viewModel.cancelActiveStream()
            }
            .task {
                await viewModel.loadHistoryIfNeeded()
                if viewModel.messages.isEmpty {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    isInputFocused = true
                }
            }
        }
    }

    // MARK: - Messages

    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DSSpacing.sm) {
                    if viewModel.isLoadingHistory && viewModel.messages.isEmpty {
                        ChatHistorySkeleton()
                    }

                    if viewModel.messages.isEmpty && !viewModel.isLoadingHistory {
                        emptyState
                    }

                    ForEach(viewModel.messages) { message in
                        MessageBubble(
                            message: message,
                            isStreaming: isStreamingMessage(message),
                            showsActions: message.role == .model
                                && message.isError != true
                                && !isStreamingMessage(message),
                            onRegenerate: isLastModelMessage(message) ? {
                                Task { await viewModel.regenerateLastResponse() }
                            } : nil,
                            onRetry: message.isError == true ? {
                                Task { await viewModel.retryLastFailedMessage() }
                            } : nil
                        ) { _ in }
                        .id(message.id)
                    }

                    if shouldShowTypingIndicator {
                        TypingIndicator()
                    }

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
            .onChange(of: viewModel.messages.count) { _ in
                guard let last = viewModel.messages.last else { return }
                if isNearBottom || last.role == .user {
                    withAnimation(reduceMotion ? nil : .default) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.messages.last?.text) { _ in
                if let last = viewModel.messages.last, isNearBottom {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            VStack(spacing: DSSpacing.xs) {
                Circle()
                    .fill(DSColor.brandGradient)
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: "books.vertical.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: DSColor.brand.opacity(0.24), radius: 18, y: 8)
                    .accessibilityHidden(true)
                Text("library_chat.empty.title".localized)
                    .font(.title3.weight(.bold))
                Text(String(format: "library_chat.empty.subtitle".localized, viewModel.files.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.lg)

            ForEach(LibraryChatViewModel.defaultSuggestions, id: \.self) { suggestion in
                Button {
                    DSHaptics.lightImpact()
                    Task { await viewModel.sendMessage(suggestion) }
                } label: {
                    HStack(spacing: DSSpacing.sm) {
                        Image(systemName: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DSColor.brand)
                            .frame(width: 34, height: 34)
                            .background(DSColor.brand.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: DSRadius.small - 4))

                        Text(suggestion)
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
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: DSSpacing.xxs) {
            TextField("library_chat.placeholder".localized, text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.leading, DSSpacing.md)
                .padding(.vertical, 10)
                .focused($isInputFocused)
                .accessibilityIdentifier("library_chat_input")

            Button {
                DSHaptics.lightImpact()
                if viewModel.isLoading {
                    viewModel.cancelActiveStream()
                    return
                }
                Task { await viewModel.sendMessage() }
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
                viewModel.isLoading ? "library_chat_stop_button" : "library_chat_send_button"
            )
        }
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
        }
        .padding(.horizontal)
        .padding(.vertical, DSSpacing.xs + 2)
    }

    // MARK: - Helpers

    private func isStreamingMessage(_ message: ChatMessage) -> Bool {
        viewModel.isLoading
            && message.role == .model
            && message.id == viewModel.messages.last?.id
    }

    private func isLastModelMessage(_ message: ChatMessage) -> Bool {
        message.role == .model
            && message.isError != true
            && message.id == viewModel.messages.last?.id
            && !viewModel.isLoading
    }
}
