import SwiftUI

// MARK: - TTS Control Strip
/// Sesli okuma aktifken bottom bar üstünde beliren kompakt kontrol şeridi —
/// dock ile aynı yüzen cam kapsül dilinde.
struct TTSControlStrip: View {
    @ObservedObject var speech: SpeechService
    @ObservedObject var viewModel: PDFReaderViewModel

    var body: some View {
        VStack(spacing: DSSpacing.xxs) {
            HStack(spacing: 14) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(DSFont.controlIcon)
                    .foregroundStyle(DSColor.brand)

                Text("reader.tts.reading_page".localized(with: viewModel.currentPage))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .contentTransition(.numericText(value: Double(viewModel.currentPage)))
                    .dsAnimation(DSMotion.snappy, value: viewModel.currentPage)

                Spacer()

                // Hız kademesi (0.8x → 1x → 1.2x). Yeni hız bir sonraki
                // sayfadan itibaren geçerli olur.
                Button {
                    speech.cycleRate()
                } label: {
                    Text(speech.rateLabel)
                        .font(DSFont.pageCounterMeta)
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 36)
                        .dsGlass(.control, shape: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("reader.tts.rate".localized)
                .accessibilityValue(speech.rateLabel)

                Button {
                    if speech.isPaused { speech.resume() } else { speech.pause() }
                } label: {
                    Image(systemName: speech.isPaused ? "play.fill" : "pause.fill")
                        .font(DSFont.controlIcon)
                        .foregroundStyle(.primary)
                        .frame(width: 36, height: 36)
                        .dsGlass(.control, shape: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(speech.isPaused ? "reader.tts.resume".localized : "reader.tts.pause".localized)

                Button {
                    speech.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(DSFont.controlIcon)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(DSColor.danger))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("reader.tts.stop".localized)
            }

            // Cihazda yalnız robotik compact ses varsa yönlendirme göster —
            // doğal ses tek seferlik ücretsiz bir indirme uzağında.
            if speech.isUsingCompactVoice {
                Text("reader.tts.natural_voice_hint".localized)
                    .font(DSFont.meta)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, 10)
        .dsGlass(.bar, shape: speech.isUsingCompactVoice ? .rounded(DSRadius.medium) : .capsule)
        .dsShadow(.floating)
        .padding(.horizontal, DSSpacing.md)
        .padding(.bottom, DSSpacing.xs)
    }
}
