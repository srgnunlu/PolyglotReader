import SwiftUI
import PhotosUI
import UIKit

// MARK: - Composer Accessories
// Mic (speech-to-text) and photo-attach buttons for the chat composer.
// Separate file keeps ChatView under the file-length budget.

/// Mikrofon butonu: kayıt sırasında canlı transcript composer'a akar.
struct ChatMicButton: View {
    @ObservedObject var recognizer: SpeechRecognitionService

    var body: some View {
        if recognizer.isAvailable {
            Button {
                DSHaptics.lightImpact()
                recognizer.toggle()
            } label: {
                Image(systemName: recognizer.isRecording ? "waveform.circle.fill" : "mic")
                    .font(.body.weight(.medium))
                    .foregroundStyle(recognizer.isRecording ? DSColor.danger : .secondary)
                    .symbolEffect(.pulse, isActive: recognizer.isRecording)
                    .frame(minWidth: 36, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(
                recognizer.isRecording
                    ? "chat.mic.stop".localized
                    : "chat.mic".localized
            )
            .accessibilityIdentifier("chat_mic_button")
        }
    }
}

/// Galeri butonu: seçilen görsel JPEG'e küçültülüp mevcut görsel-soru
/// akışına (ChatImageSelectionBar + sendMessageWithImage) verilir.
struct ChatPhotoPickerButton: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            Image(systemName: "photo")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("chat.attach_photo".localized)
        .accessibilityIdentifier("chat_photo_button")
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let jpeg = Self.downscaledJPEG(image) {
                    viewModel.selectedImage = jpeg
                }
                photoItem = nil
            }
        }
    }

    /// Gemini'ye gidecek görseli makul boyuta indirir (maks 1280pt, JPEG 0.8)
    /// — tam çözünürlüklü fotoğraflar isteği şişirir, kaliteye katkısı yok.
    static func downscaledJPEG(_ image: UIImage, maxDimension: CGFloat = 1280) -> Data? {
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > maxDimension else {
            return image.jpegData(compressionQuality: 0.8)
        }
        let scale = maxDimension / largestSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
