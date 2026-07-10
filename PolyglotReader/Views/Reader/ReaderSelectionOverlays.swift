import SwiftUI

// MARK: - Reader Selection Overlays
/// Metin/görsel seçimine bağlı popup katmanı: TextSelectionPopup,
/// QuickTranslationPopup ve ImageSelectionPopup. Üst ZStack içinde,
/// önceki inline kullanımla birebir aynı koşullarla render edilir.
struct ReaderSelectionOverlays: View {
    @ObservedObject var viewModel: PDFReaderViewModel
    @ObservedObject var chatViewModel: ChatViewModel
    @Binding var showChat: Bool

    var body: some View {
        textSelectionPopup
        quickTranslationPopup
        imageSelectionPopup
    }

    // MARK: - Text Selection Popup

    @ViewBuilder
    private var textSelectionPopup: some View {
        if viewModel.showTranslationPopup,
           !viewModel.showQuickTranslation,
           let selectedText = viewModel.selectedText,
           let rect = viewModel.selectionRect {
            TextSelectionPopup(
                selectedText: selectedText,
                selectionRect: rect,
                context: viewModel.fileMetadata.summary,
                onDismiss: { viewModel.clearSelection() },
                onHighlight: { color in
                    Task {
                        await viewModel.addAnnotation(type: .highlight, color: color)
                    }
                },
                onAskAI: {
                    chatViewModel.selectedText = viewModel.selectedText
                    viewModel.clearSelection()
                    showChat = true
                },
                onAddNote: { note in
                    await viewModel.addAnnotation(type: .highlight, color: "#fef08a", note: note)
                }
            )
        }
    }

    // MARK: - Quick Translation Popup

    @ViewBuilder
    private var quickTranslationPopup: some View {
        if viewModel.showQuickTranslation,
           let text = viewModel.selectedText,
           let rect = viewModel.selectionRect {
            QuickTranslationPopup(
                selectedText: text,
                selectionRect: rect,
                context: viewModel.fileMetadata.summary,
                persistedScale: $viewModel.translationPopupScale,
                onAskAI: {
                    // Detay katmanı CTA'sı: seçim sohbete taşınır (TextSelectionPopup akışıyla aynı).
                    chatViewModel.selectedText = viewModel.selectedText
                    viewModel.showQuickTranslation = false
                    viewModel.clearSelection()
                    showChat = true
                }
            ) {
                viewModel.showQuickTranslation = false
                // Hızlı mod aktifse sadece seçimi temizle, büyük popup'a dönme
                if viewModel.isQuickTranslationMode {
                    viewModel.clearSelection()
                } else if viewModel.selectedText != nil {
                    viewModel.showTranslationPopup = true
                }
            }
        }
    }

    // MARK: - Image Selection Popup

    @ViewBuilder
    private var imageSelectionPopup: some View {
        // Görsel Seçim Popup'ı
        if viewModel.showImagePopup,
           let imageInfo = viewModel.selectedImage {
            ImageSelectionPopup(
                imageInfo: imageInfo,
                onDismiss: { viewModel.clearImageSelection() },
                onAskAI: {
                    // Görsel verisini ChatViewModel'e aktar
                    chatViewModel.selectedImage = imageInfo.jpegData
                    viewModel.clearImageSelection()
                    showChat = true
                }
            )
        }
    }
}
