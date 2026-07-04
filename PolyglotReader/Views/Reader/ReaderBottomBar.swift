import SwiftUI

// MARK: - Reader Bottom Bar
struct ReaderBottomBar: View {
    @ObservedObject var viewModel: PDFReaderViewModel
    @ObservedObject var speech: SpeechService
    @Binding var showChat: Bool
    let onToggleTTS: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Sol: Sayfa Navigasyonu
            pageNavigationControls

            Spacer()

            // Orta: Hızlı Çeviri Toggle
            quickTranslationToggle

            Spacer()

            // Sağ: Sesli Okuma + Chat Butonları
            trailingActionButtons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            LiquidGlassBackground(cornerRadius: 28, intensity: .medium, accentColor: .indigo)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .shadow(color: .black.opacity(0.1), radius: 20, x: 0, y: 10)
        .padding(.bottom, 16)
        .padding(.horizontal, 12)
    }

    // MARK: - Page Navigation

    private var pageNavigationControls: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.previousPage()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(
                        viewModel.currentPage <= 1
                            ? Color.secondary.opacity(0.4)
                            : Color.primary
                    )
                    .frame(width: 36, height: 36)
                    .background {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Circle()
                                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
                            }
                    }
            }
            .disabled(viewModel.currentPage <= 1)
            .accessibilityLabel("Önceki sayfa")

            // Inline Page Spinner - yukarı/aşağı sürükleyerek sayfa değiştir
            PageSpinner(
                currentPage: viewModel.currentPage,
                totalPages: viewModel.totalPages
            ) { page in
                viewModel.goToPage(page)
            }

            Button {
                viewModel.nextPage()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(
                        viewModel.currentPage >= viewModel.totalPages
                            ? Color.secondary.opacity(0.4)
                            : Color.primary
                    )
                    .frame(width: 36, height: 36)
                    .background {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                Circle()
                                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
                            }
                    }
            }
            .disabled(viewModel.currentPage >= viewModel.totalPages)
            .accessibilityLabel("Sonraki sayfa")
        }
    }

    // MARK: - Quick Translation Toggle

    private var quickTranslationToggle: some View {
        Button {
            viewModel.toggleQuickTranslationMode()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: viewModel.isQuickTranslationMode ? "character.bubble.fill" : "character.bubble")
                    .font(.system(size: 16, weight: .medium))

                if viewModel.isQuickTranslationMode {
                    Text("Çeviri Açık")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(viewModel.isQuickTranslationMode ? .white : .primary)
            .padding(.horizontal, viewModel.isQuickTranslationMode ? 14 : 12)
            .padding(.vertical, 10)
            .background {
                Capsule()
                    .fill(viewModel.isQuickTranslationMode ? Color.indigo : Color.clear)

                if !viewModel.isQuickTranslationMode {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Capsule()
                                .stroke(.white.opacity(0.2), lineWidth: 0.5)
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isQuickTranslationMode)
        .accessibilityLabel("Hızlı çeviri")
        .accessibilityValue(viewModel.isQuickTranslationMode ? "Açık" : "Kapalı")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - TTS + Chat Buttons

    private var trailingActionButtons: some View {
        HStack(spacing: 10) {
            Button(action: onToggleTTS) {
                Image(systemName: speech.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(speech.isSpeaking ? .white : .primary)
                    .frame(width: 44, height: 44)
                    .background {
                        Circle()
                            .fill(speech.isSpeaking ? Color.indigo : Color.clear)
                        if !speech.isSpeaking {
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Circle().stroke(.white.opacity(0.2), lineWidth: 0.5)
                                }
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("reader.tts.toggle".localized)
            .accessibilityValue(
                speech.isSpeaking
                    ? "accessibility.selected".localized
                    : "accessibility.not_selected".localized
            )

            if viewModel.isChatReady {
                Button {
                    showChat = true
                } label: {
                    Image(systemName: "message.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.indigo, Color.indigo.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .indigo.opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sohbet")
            }
        }
    }
}
