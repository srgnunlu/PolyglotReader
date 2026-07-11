import SwiftUI
import PDFKit

struct PDFReaderView: View {
    @StateObject private var viewModel: PDFReaderViewModel
    @StateObject private var chatViewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var speech = SpeechService()
    @State private var showChat = false
    @State private var showQuiz = false
    @State private var showSearch = false
    @State private var showNavigator = false
    @State private var barsVisible = true
    // Odak modu: iki parmak çift dokunuşla girilir; TÜM chrome gizlenir.
    // Tek dokunuş her zaman güvenli çıkış kapısıdır (barlar geri gelir).
    @State private var isFocusMode = false
    @State private var focusHintTrigger = 0
    @State private var autoHideTimer: Timer?
    @State private var isPDFRendering = true  // PDF render durumu
    @State private var showAnnotationNote = false
    @State private var selectedAnnotation: Annotation?
    // Atıf/arama sıçrayışlarında sayfa üzerindeki sarı parıltıyı tetikler.
    @State private var jumpFlashCount = 0

    private let bottomDockInset: CGFloat = 90
    // İçerik-öncelikli okuyucu: chrome 6 saniyede kenara çekilir.
    private let autoHideDelay: TimeInterval = 6.0
    private let initialPage: Int?

    init(file: PDFDocumentMetadata, initialPage: Int? = nil) {
        _viewModel = StateObject(wrappedValue: PDFReaderViewModel(file: file))
        _chatViewModel = StateObject(wrappedValue: ChatViewModel(fileId: file.id))
        self.initialPage = initialPage
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)

                if viewModel.isLoading {
                    // Doküman indiriliyor
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("reader.loading_document".localized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let document = viewModel.document {
                    // Doküman yüklendi - PDF'i göster
                    ReaderDocumentContent(
                        document: document,
                        viewModel: viewModel,
                        speech: speech,
                        isPDFRendering: $isPDFRendering,
                        showChat: $showChat,
                        showSearch: $showSearch,
                        showNavigator: $showNavigator,
                        barsVisible: barsVisible,
                        isFocusMode: isFocusMode,
                        bottomDockInset: bottomDockInset,
                        onSelection: { text, rect, page, pdfRects in
                            viewModel.handleSelection(text: text, rect: rect, page: page, pdfRects: pdfRects)
                            chatViewModel.selectedText = text.isEmpty ? nil : text
                        },
                        onAnnotationTap: { annotation in
                            // Not popup'ını göster
                            if let note = annotation.note, !note.isEmpty {
                                selectedAnnotation = annotation
                                showAnnotationNote = true
                            }
                        },
                        onPDFTap: { yFraction in handlePDFTap(atYFraction: yFraction) },
                        onShowBars: showBars,
                        onToggleFocusMode: toggleFocusMode,
                        onToggleTTS: toggleTTS,
                        onClose: closeReader
                    )

                    ReaderSelectionOverlays(
                        viewModel: viewModel,
                        chatViewModel: chatViewModel,
                        showChat: $showChat
                    )

                    ReaderJumpFlashOverlay(trigger: jumpFlashCount)

                    ReaderFocusModeHint(trigger: focusHintTrigger)
                } else {
                    // Error state when document failed to load
                    ReaderLoadFailedView(
                        onRetry: {
                            Task {
                                await viewModel.loadDocument()
                            }
                        },
                        onClose: closeReader
                    )
                }
            }
            .ignoresSafeArea()
            .navigationBarHidden(true)
            .edgeSwipeToDismiss {
                dismiss()
            }
            .sheet(isPresented: $showChat) {
                ChatView(viewModel: chatViewModel) { page in
                    viewModel.goToPage(page)
                    showChat = false
                    // Atıf navigasyonu: hedef sayfada kısa sarı parıltı.
                    jumpFlashCount += 1
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(DSRadius.popup)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
            .onChange(of: showChat) { isShowing in
                // Chat açıldığında indexleme durumunu kontrol et (P0)
                if isShowing {
                    Task {
                        await chatViewModel.checkAndPrepareDocument(
                            pdfText: viewModel.extractedText
                        )
                        // P4: Chat açıldığında mevcut sayfa için önerileri güncelle
                        chatViewModel.updatePageContext(
                            pageNumber: viewModel.currentPage,
                            pageText: viewModel.currentPageText,
                            sectionTitle: nil,
                            hasTable: false,
                            hasImage: false
                        )
                    }
                }
            }
            .onChange(of: viewModel.currentPage) { newPage in
                // P4: Sayfa değiştiğinde smart suggestions güncelle
                chatViewModel.updatePageContext(
                    pageNumber: newPage,
                    pageText: viewModel.currentPageText,
                    sectionTitle: nil,
                    hasTable: false,
                    hasImage: false
                )
                // Kullanıcı bar üzerinden sayfa çeviriyor demektir — otomatik
                // gizleme sayacını sıfırla ki bar elinin altından kaybolmasın.
                if barsVisible {
                    startAutoHideTimer()
                }
            }
            .sheet(isPresented: $showQuiz) {
                QuizView(textContext: viewModel.extractedText)
                    .presentationCornerRadius(DSRadius.popup)
            }
            .sheet(isPresented: $showSearch) {
                SearchSheet(viewModel: viewModel) {
                    // Arama sonucuna atlama: hedef sayfada kısa sarı parıltı.
                    jumpFlashCount += 1
                }
                .presentationCornerRadius(DSRadius.popup)
            }
            .sheet(isPresented: $showNavigator) {
                if let document = viewModel.document {
                    DocumentNavigatorView(
                        document: document,
                        currentPage: viewModel.currentPage,
                        onSelectPage: { viewModel.goToPage($0) },
                        onDismiss: { showNavigator = false }
                    )
                    .presentationCornerRadius(DSRadius.popup)
                }
            }
            .sheet(isPresented: $showAnnotationNote) {
                if let annotation = selectedAnnotation {
                    NoteDetailSheet(
                        annotation: annotation,
                        onSave: { updatedNote in
                            Task {
                                await viewModel.updateAnnotationNote(annotationId: annotation.id, note: updatedNote)
                            }
                        },
                        onDelete: {
                            Task {
                                await viewModel.deleteAnnotation(annotationId: annotation.id)
                            }
                        },
                        onDismiss: {
                            showAnnotationNote = false
                            selectedAnnotation = nil
                        }
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(.clear)
                }
            }
            .onAppear {
                logDebug("PDFReaderView", "View appeared for file: \(viewModel.fileMetadata.name)")
                if let document = viewModel.document {
                    logDebug("PDFReaderView", "Document loaded with \(document.pageCount) pages")
                }
                configureSpeechAutoAdvance()
                startAutoHideTimer()
            }
            .onDisappear {
                logDebug("PDFReaderView", "View disappeared")
                speech.stop()
                autoHideTimer?.invalidate()
            }
            .dsAnimation(DSMotion.smooth, value: speech.isSpeaking)
            .onChange(of: showChat) { isOpen in
                if isOpen {
                    autoHideTimer?.invalidate()
                    // Görsel metadata yüklemesini devre dışı bıraktık - performans sorunu
                    // Görseller sadece kullanıcı görsel sorusu sorduğunda lazy load edilecek

                    // Sadece PDF referansını aktar (tarama yapmadan)
                    if let document = viewModel.document {
                        chatViewModel.pdfDocument = document
                    }
                } else {
                    startAutoHideTimer()
                }
            }
            .task {
                logDebug("PDFReaderView", "Task started")
                await viewModel.loadDocument()
                logDebug("PDFReaderView", "Task finished")

                // Navigate to initial page if specified
                // Wait for PDFKit render to complete before navigating
                if let page = initialPage, page > 0 {
                    // Small delay to ensure PDF renders first, then navigate
                    try? await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds
                    viewModel.goToPage(page)
                    logDebug("PDFReaderView", "Navigated to initial page: \(page)")
                }
            }
        }
    }

    // MARK: - Dismiss

    private func closeReader() {
        dismiss()
    }

    // MARK: - Bar Toggle & Auto-Hide

    /// PDF boşluğuna tek dokunuş. Barlar gizliyken her dokunuş onları getirir;
    /// barlar açıkken YALNIZ sayfa ortasındaki dokunuş kapatır. Üst/alt bar
    /// hizasına düşen dokunuşlar yok sayılır — bir bar butonunu milim ıskalamak
    /// artık barı kapatmaz.
    private func handlePDFTap(atYFraction fraction: CGFloat) {
        // Odak modundayken tek dokunuş modu kapatır — kullanıcı asla mahsur kalmaz.
        if isFocusMode {
            toggleFocusMode()
            return
        }

        guard barsVisible else {
            showBars()
            return
        }

        // Bar bölgeleri (üst %22, alt %22) kapatma dokunuşuna kapalıdır.
        guard (0.22...0.78).contains(fraction) else { return }

        withAnimation(DSMotion.resolved(DSMotion.smooth, reduceMotion: reduceMotion)) {
            barsVisible = false
        }
        autoHideTimer?.invalidate()
    }

    /// Barları koşulsuz geri getirir (collapsed pill dokunuşu ve orta tap).
    private func showBars() {
        if isFocusMode {
            toggleFocusMode()
            return
        }

        withAnimation(DSMotion.resolved(DSMotion.smooth, reduceMotion: reduceMotion)) {
            barsVisible = true
        }
        startAutoHideTimer()
    }

    // MARK: - Focus Mode
    /// İki parmak çift dokunuş: tüm chrome (barlar, pill'ler, banner'lar) çekilir,
    /// yalnız sayfa kalır. Tekrar aynı gesture ya da tek dokunuş moddan çıkarır.
    private func toggleFocusMode() {
        let entering = !isFocusMode

        withAnimation(DSMotion.resolved(DSMotion.smooth, reduceMotion: reduceMotion)) {
            isFocusMode = entering
            barsVisible = !entering
        }

        DSHaptics.softImpact()

        if entering {
            autoHideTimer?.invalidate()
            focusHintTrigger += 1
        } else {
            startAutoHideTimer()
        }
    }

    private func startAutoHideTimer() {
        // Odak modunda zamanlayıcıya gerek yok — chrome zaten tamamen gizli.
        guard !isFocusMode else { return }
        autoHideTimer?.invalidate()
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: autoHideDelay, repeats: false) { _ in
            withAnimation(DSMotion.resolved(DSMotion.smooth, reduceMotion: reduceMotion)) {
                barsVisible = false
            }
        }
    }

    // MARK: - Text-to-Speech

    /// TTS düğmesi: okuma sürüyorsa durdurur, değilse mevcut sayfayı okumaya başlar.
    private func toggleTTS() {
        if speech.isSpeaking {
            speech.stop()
        } else if let text = viewModel.currentPageText, !text.isEmpty {
            speech.speak(text)
        }
    }

    /// Bir sayfa bitince otomatik olarak sonraki sayfaya geçip okumaya devam eder.
    /// Nesneler `weak` yakalanır; closure'ın `speech` üzerinde tutulması döngü yaratmasın.
    private func configureSpeechAutoAdvance() {
        speech.onFinish = { [weak speech, weak viewModel] in
            guard let speech, let viewModel else { return }
            let next = viewModel.currentPage + 1
            guard next <= viewModel.totalPages else { return }
            viewModel.goToPage(next)
            if let text = viewModel.currentPageText, !text.isEmpty {
                speech.speak(text)
            }
        }
    }
}

#Preview {
    PDFReaderView(file: PDFDocumentMetadata(
        id: "1",
        name: "Test.pdf",
        size: 1234,
        uploadedAt: Date(),
        storagePath: "/test"
    ))
}
