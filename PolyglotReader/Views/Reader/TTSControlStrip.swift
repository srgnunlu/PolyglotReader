import SwiftUI

// MARK: - TTS Control Strip
/// Sesli okuma aktifken bottom bar üstünde beliren kompakt kontrol şeridi.
struct TTSControlStrip: View {
    @ObservedObject var speech: SpeechService
    @ObservedObject var viewModel: PDFReaderViewModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.indigo)

            Text("reader.tts.reading_page".localized(with: viewModel.currentPage))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Button {
                if speech.isPaused { speech.resume() } else { speech.pause() }
            } label: {
                Image(systemName: speech.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(speech.isPaused ? "reader.tts.resume".localized : "reader.tts.pause".localized)

            Button {
                speech.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.red))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("reader.tts.stop".localized)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            LiquidGlassBackground(cornerRadius: 24, intensity: .medium, accentColor: .indigo)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}
