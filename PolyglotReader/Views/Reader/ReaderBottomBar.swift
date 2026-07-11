import SwiftUI

// MARK: - Reader Bottom Bar
/// Yüzen cam dock: sayfa navigasyonu, hızlı çeviri ve TTS/sohbet aksiyonları.
struct ReaderBottomBar: View {
    @ObservedObject var viewModel: PDFReaderViewModel
    @ObservedObject var speech: SpeechService
    @Binding var showChat: Bool
    let onToggleTTS: () -> Void
    /// iOS 26: collapsed pill ile aynı id → dock↔pill cam morph'u.
    var glassMorph: DSGlassMorph?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .dsGlass(.bar, shape: .rounded(DSRadius.dock), morph: glassMorph)
        .dsShadow(.floating)
        .padding(.bottom, DSSpacing.md)
        .padding(.horizontal, DSSpacing.md)
    }

    // MARK: - Page Navigation

    private var pageNavigationControls: some View {
        HStack(spacing: DSSpacing.xs) {
            pageStepButton(systemName: "chevron.left", disabled: viewModel.currentPage <= 1) {
                viewModel.previousPage()
            }
            .accessibilityLabel("reader.previous_page".localized)

            // Inline Page Spinner - popover ile sayfa seçimi
            PageSpinner(
                currentPage: viewModel.currentPage,
                totalPages: viewModel.totalPages
            ) { page in
                viewModel.goToPage(page)
            }

            pageStepButton(systemName: "chevron.right", disabled: viewModel.currentPage >= viewModel.totalPages) {
                viewModel.nextPage()
            }
            .accessibilityLabel("reader.next_page".localized)
        }
    }

    private func pageStepButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(DSFont.controlIcon)
                .foregroundStyle(disabled ? Color.secondary.opacity(0.4) : Color.primary)
                .frame(width: 36, height: 36)
                .dsGlass(.control, shape: .circle)
                // Dokunma alanı HIG minimumu 44pt — görsel daire 36pt kalır.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Quick Translation Toggle

    private var quickTranslationToggle: some View {
        Button {
            viewModel.toggleQuickTranslationMode()
        } label: {
            quickTranslationLabel
        }
        .buttonStyle(.plain)
        .dsAnimation(DSMotion.snappy, value: viewModel.isQuickTranslationMode)
        .dsHaptic(.selection, trigger: viewModel.isQuickTranslationMode)
        .accessibilityLabel("reader.quick_translation".localized)
        .accessibilityValue(viewModel.isQuickTranslationMode ? "common.on".localized : "common.off".localized)
        .accessibilityAddTraits(.isButton)
    }

    /// Aktifken düz marka kapsülü, pasifken cam kontrol — cam camın (veya
    /// dolgunun) üzerine binmez.
    @ViewBuilder
    private var quickTranslationLabel: some View {
        let content = HStack(spacing: DSSpacing.xxs + 2) {
            Image(systemName: viewModel.isQuickTranslationMode ? "character.bubble.fill" : "character.bubble")
                .font(DSFont.controlIconProminent)

            if viewModel.isQuickTranslationMode {
                Text("reader.translation_on".localized)
                    .font(DSFont.meta.weight(.semibold))
                    // Dar dock'ta metin dikey kırılıp "çe-vir-i" olmasın: tek
                    // satır + gerçek genişliğinde sabitle; sığmazsa harf kırpma
                    // yerine hafif küçült.
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .minimumScaleFactor(0.8)
            }
        }
        .foregroundStyle(viewModel.isQuickTranslationMode ? .white : .primary)
        .padding(.horizontal, viewModel.isQuickTranslationMode ? 14 : 12)
        .padding(.vertical, 10)

        if viewModel.isQuickTranslationMode {
            content.background(Capsule().fill(DSColor.brand))
        } else {
            content.dsGlass(.control, shape: .capsule)
        }
    }

    // MARK: - TTS + Chat Buttons

    private var trailingActionButtons: some View {
        HStack(spacing: DSSpacing.xs + 2) {
            Button(action: onToggleTTS) {
                ttsButtonLabel
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
                    chatButtonLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel("reader.chat".localized)
            }
        }
    }

    /// Okuma aktifken düz marka dairesi + hoparlör dalgalarında iterative
    /// nabız (TTS'in "canlı" göstergesi); pasifken cam kontrol.
    @ViewBuilder
    private var ttsButtonLabel: some View {
        let icon = Image(systemName: speech.isSpeaking ? "speaker.wave.2.fill" : "speaker.wave.2")
            .font(DSFont.controlIconProminent)
            .symbolEffect(
                .variableColor.iterative,
                options: .repeating,
                isActive: speech.isSpeaking && !reduceMotion
            )
            .foregroundStyle(speech.isSpeaking ? Color.white : Color.primary)
            .frame(width: 44, height: 44)

        if speech.isSpeaking {
            icon.background(Circle().fill(DSColor.brand))
        } else {
            icon.dsGlass(.control, shape: .circle)
        }
    }

    private var chatButtonLabel: some View {
        Image(systemName: "message.fill")
            .font(DSFont.controlIconProminent)
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background {
                Circle().fill(DSColor.brandGradient)
            }
            .dsShadow(.subtle, tint: DSColor.brand)
    }
}
