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
    /// Odak modu: tüm chrome (pill'ler, banner, TTS şeridi dahil) gizlenir.
    let isFocusMode: Bool
    let bottomDockInset: CGFloat

    let onSelection: (String, CGRect, Int, [CGRect]) -> Void
    let onAnnotationTap: (Annotation) -> Void
    /// PDF boşluğuna tek dokunuş; parametre dikey konum (0 üst – 1 alt).
    let onPDFTap: (CGFloat) -> Void
    /// Collapsed pill'e dokunma — barları her koşulda geri getirir.
    let onShowBars: () -> Void
    let onToggleFocusMode: () -> Void
    let onToggleTTS: () -> Void
    let onClose: () -> Void

    /// iOS 26 cam morph kimlikleri: bar ve collapsed pill aynı cam varlığıdır.
    @Namespace private var chromeGlassNamespace

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
            initialScale: viewModel.scale,
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
            onTap: { yFraction in
                // PDF'e tıklandığında bar görünürlüğü bölge mantığıyla yönetilir.
                onPDFTap(yFraction)
            },
            onAnnotationTap: onAnnotationTap,
            onTwoFingerDoubleTap: onToggleFocusMode
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
            // Top Bar with collapse animation — iOS 26'da bar ve pill aynı
            // cam kapsayıcıyı paylaşır, geçişte şekil morph'u oynar.
            DSGlassContainer {
                if barsVisible && !isPDFRendering {
                    ReaderTopBar(
                        viewModel: viewModel,
                        showSearch: $showSearch,
                        showNavigator: $showNavigator,
                        onClose: onClose,
                        glassMorph: DSGlassMorph("reader.chrome.top", in: chromeGlassNamespace)
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                } else if !isPDFRendering && !isFocusMode {
                    // Collapsed top indicator — dokununca barlar geri gelir.
                    CollapsedBarIndicator(
                        position: .top,
                        glassMorph: DSGlassMorph("reader.chrome.top", in: chromeGlassNamespace),
                        onTap: onShowBars
                    )
                    .transition(.opacity)
                }
            }

            Spacer()

            // Taranmış (metin katmanı olmayan) sayfalarda OCR pili
            if !isPDFRendering && !isFocusMode {
                ScannedPageOCRBanner(viewModel: viewModel)
            }

            // Sesli okuma kontrol şeridi (okuma aktifken görünür)
            if speech.isSpeaking && !isPDFRendering && !isFocusMode {
                TTSControlStrip(speech: speech, viewModel: viewModel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Bottom Bar with collapse animation — üst bar ile aynı morph deseni.
            DSGlassContainer {
                if barsVisible && !isPDFRendering {
                    ReaderBottomBar(
                        viewModel: viewModel,
                        speech: speech,
                        showChat: $showChat,
                        onToggleTTS: onToggleTTS,
                        glassMorph: DSGlassMorph("reader.chrome.bottom", in: chromeGlassNamespace)
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                } else if !isPDFRendering && !isFocusMode {
                    // Collapsed bottom indicator — dokununca barlar geri gelir.
                    CollapsedBarIndicator(
                        position: .bottom,
                        glassMorph: DSGlassMorph("reader.chrome.bottom", in: chromeGlassNamespace),
                        onTap: onShowBars
                    )
                    .transition(.opacity)
                }
            }
        }
    }
}
