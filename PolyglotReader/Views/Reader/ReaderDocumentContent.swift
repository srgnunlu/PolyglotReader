import SwiftUI
import PDFKit

// MARK: - Reader Document Content
/// Doküman yüklendikten sonraki ana katman: PDF görünümü, render overlay'i
/// ve üst/alt bar katmanı. PDFReaderView'ün ince kompozisyon köküne hizmet eder.
struct ReaderDocumentContent: View {
    let document: PDFDocument
    @ObservedObject var viewModel: PDFReaderViewModel
    @ObservedObject var speech: SpeechService

    @Binding var isPDFRendering: Bool
    @Binding var showChat: Bool
    @Binding var showSearch: Bool
    @Binding var showNavigator: Bool
    let barsVisible: Bool
    let bottomDockInset: CGFloat

    let onSelection: (String, CGRect, Int, [CGRect]) -> Void
    let onAnnotationTap: (Annotation) -> Void
    let onToggleBars: () -> Void
    let onToggleTTS: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            pdfView

            // Render tamamlanana kadar loading overlay veya cached image göster
            if isPDFRendering {
                ReaderRenderingOverlay(cachedFirstPageImage: viewModel.cachedFirstPageImage)
            }

            barsLayer
        }
    }

    // MARK: - PDF View

    private var pdfView: some View {
        PDFKitView(
            document: document,
            currentPage: $viewModel.currentPage,
            isQuickTranslationMode: viewModel.isQuickTranslationMode,
            bottomInset: max(showChat ? 350 : 0, bottomDockInset),
            annotations: viewModel.annotations,
            initialScrollPosition: viewModel.initialScrollPosition,
            onProgressChange: { page, point, scale in
                viewModel.updateReadingProgress(page: page, point: point, scale: scale)
            },
            onSelection: onSelection,
            onImageSelection: { imageInfo in
                viewModel.handleImageSelection(imageInfo)
            },
            onRenderComplete: {
                // PDF render tamamlandı - loading overlay'i kapat
                logDebug("UI", "PDF render tamamlandı - overlay kapatılıyor")
                withAnimation(.easeOut(duration: 0.2)) {
                    isPDFRendering = false
                }
            },
            onTap: {
                // PDF'e tıklandığında barları toggle et
                onToggleBars()
            },
            onAnnotationTap: onAnnotationTap
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .onAppear {
            logDebug("UI", "PDFKitView appeared in hierarchy")
        }
    }

    // MARK: - Bars Layer

    private var barsLayer: some View {
        VStack(spacing: 0) {
            // Top Bar with collapse animation
            if barsVisible && !isPDFRendering {
                ReaderTopBar(
                    viewModel: viewModel,
                    showSearch: $showSearch,
                    showNavigator: $showNavigator,
                    onClose: onClose
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            } else if !isPDFRendering {
                // Collapsed top indicator
                CollapsedBarIndicator(position: .top)
                    .transition(.opacity)
            }

            Spacer()

            // Taranmış (metin katmanı olmayan) sayfalarda OCR pili
            if !isPDFRendering {
                ScannedPageOCRBanner(viewModel: viewModel)
            }

            // Sesli okuma kontrol şeridi (okuma aktifken görünür)
            if speech.isSpeaking && !isPDFRendering {
                TTSControlStrip(speech: speech, viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Bottom Bar with collapse animation
            if barsVisible && !isPDFRendering {
                ReaderBottomBar(
                    viewModel: viewModel,
                    speech: speech,
                    showChat: $showChat,
                    onToggleTTS: onToggleTTS
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
            } else if !isPDFRendering {
                // Collapsed bottom indicator
                CollapsedBarIndicator(position: .bottom)
                    .transition(.opacity)
            }
        }
    }
}
