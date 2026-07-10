import SwiftUI
import PDFKit

// MARK: - Scanned Page OCR Banner
/// Görüntü tabanlı (metin katmanı olmayan) sayfalarda alt bar üzerinde beliren
/// küçük OCR pili. Tanınan metin, normal metin seçimiyle birebir aynı state
/// mekanizması üzerinden QuickTranslationPopup'a aktarılır; kullanıcı böylece
/// tanınan metni hemen çevirebilir.
struct ScannedPageOCRBanner: View {
    @ObservedObject var viewModel: PDFReaderViewModel

    private enum RecognitionPhase: Equatable {
        case idle
        case recognizing
        case textNotFound
    }

    @State private var phase = RecognitionPhase.idle
    @State private var isScannedPage = false

    var body: some View {
        // ZStack (not Group): Group forwards modifiers to its children, so with
        // an empty conditional the onAppear/onChange below would never register.
        ZStack {
            if isScannedPage {
                bannerButton
                    .transition(.opacity)
            }
        }
        .onAppear {
            refreshScannedPageState()
        }
        .onChange(of: viewModel.currentPage) { _ in
            // New page: drop any stale phase (e.g. "not found") and re-evaluate.
            phase = .idle
            refreshScannedPageState()
        }
    }

    // MARK: - Banner UI

    private var bannerButton: some View {
        Button {
            recognizeCurrentPage()
        } label: {
            HStack(spacing: DSSpacing.xs) {
                if phase == .recognizing {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: phase == .textNotFound ? "exclamationmark.circle" : "text.viewfinder")
                        .font(DSFont.controlIcon)
                }

                Text(bannerTitle)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, DSSpacing.xs)
            .dsGlass(.banner, shape: .capsule)
        }
        .buttonStyle(.plain)
        .disabled(phase == .recognizing)
        .padding(.bottom, DSSpacing.xs)
        .accessibilityLabel(bannerTitle)
        .dsAnimation(.easeInOut(duration: 0.2), value: phase)
    }

    private var bannerTitle: String {
        switch phase {
        case .idle:
            return "Taranmış sayfa — metni tanı"
        case .recognizing:
            return "Metin tanınıyor..."
        case .textNotFound:
            return "Bu sayfada metin bulunamadı"
        }
    }

    // MARK: - Scanned Page Detection

    private func refreshScannedPageState() {
        guard let page = viewModel.document?.page(at: viewModel.currentPage - 1) else {
            isScannedPage = false
            return
        }
        isScannedPage = !PDFOCRService.shared.hasTextLayer(page)
    }

    // MARK: - Recognition Flow

    private func recognizeCurrentPage() {
        // Skip taps while this page's OCR is already in flight.
        guard phase != .recognizing else { return }
        let pageNumber = viewModel.currentPage
        guard let page = viewModel.document?.page(at: pageNumber - 1) else { return }

        phase = .recognizing
        Task { @MainActor in
            let recognized = await PDFOCRService.shared.recognizeText(on: page)

            // User may have navigated away during OCR; don't pop a stale result.
            guard viewModel.currentPage == pageNumber else {
                phase = .idle
                return
            }

            if let recognized, !recognized.isEmpty {
                phase = .idle
                presentQuickTranslation(with: recognized, pageNumber: pageNumber)
            } else {
                phase = .textNotFound
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if phase == .textNotFound {
                    phase = .idle
                }
            }
        }
    }

    /// Mirrors PDFReaderViewModel.handleSelection's quick-translation branch so
    /// the recognized text flows through the exact state a manual selection uses.
    private func presentQuickTranslation(with text: String, pageNumber: Int) {
        viewModel.selectedText = text
        viewModel.selectionRect = centeredSelectionRect()
        viewModel.selectionPage = pageNumber
        // OCR has no glyph rects; annotation save falls back to text search.
        viewModel.selectionPDFRects = []
        viewModel.showTranslationPopup = false
        viewModel.showQuickTranslation = true
    }

    /// QuickTranslationPopup anchors below selectionRect.maxY (+80pt), so this
    /// rect places the popup roughly at the vertical center of the screen.
    private func centeredSelectionRect() -> CGRect {
        let bounds = UIScreen.main.bounds
        return CGRect(x: bounds.midX - 100, y: bounds.midY - 140, width: 200, height: 40)
    }
}
