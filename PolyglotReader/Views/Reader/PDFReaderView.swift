import SwiftUI
import PDFKit

struct PDFReaderView: View {
    @StateObject private var viewModel: PDFReaderViewModel
    @StateObject private var chatViewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var showChat = false
    @State private var showQuiz = false
    @State private var showSearch = false
    @State private var barsVisible = true
    @State private var autoHideTimer: Timer?
    @State private var isPDFRendering = true  // PDF render durumu
    @State private var showAnnotationNote = false
    @State private var selectedAnnotation: Annotation?
    
    private let bottomDockInset: CGFloat = 90
    private let autoHideDelay: TimeInterval = 10.0
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
                        Text("Doküman yükleniyor...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else if let document = viewModel.document {
                    // Doküman yüklendi - PDF'i göster
                    ZStack {
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
                            onSelection: { text, rect, page, pdfRects in
                                viewModel.handleSelection(text: text, rect: rect, page: page, pdfRects: pdfRects)
                                chatViewModel.selectedText = text.isEmpty ? nil : text
                            },
                            onImageSelection: { imageInfo in
                                viewModel.handleImageSelection(imageInfo)
                            },
                            onRenderComplete: {
                                // PDF render tamamlandı - loading overlay'i kapat
                                withAnimation(.easeOut(duration: 0.2)) {
                                    isPDFRendering = false
                                }
                            },
                            onTap: {
                                // PDF'e tıklandığında barları toggle et
                                toggleBars()
                            },
                            onAnnotationTap: { annotation in
                                // Not popup'ını göster
                                if let note = annotation.note, !note.isEmpty {
                                    selectedAnnotation = annotation
                                    showAnnotationNote = true
                                }
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white)
                        .onAppear {
                            logDebug("UI", "PDFKitView appeared in hierarchy")
                        }
                        
                        // Render tamamlanana kadar loading overlay göster
                        if isPDFRendering {
                            Color(.systemGroupedBackground)
                                .ignoresSafeArea()
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text("Sayfa hazırlanıyor...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        VStack(spacing: 0) {
                            // Top Bar with collapse animation
                            if barsVisible && !isPDFRendering {
                                ReaderTopBar(
                                    viewModel: viewModel,
                                    showSearch: $showSearch,
                                    onClose: { dismiss() }
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
                            
                            // Bottom Bar with collapse animation
                            if barsVisible && !isPDFRendering {
                                ReaderBottomBar(
                                    viewModel: viewModel, 
                                    showChat: $showChat
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
                    
                    if viewModel.showQuickTranslation,
                       let text = viewModel.selectedText,
                       let rect = viewModel.selectionRect {
                        QuickTranslationPopup(
                            selectedText: text,
                            selectionRect: rect,
                            context: viewModel.fileMetadata.summary,
                            onDismiss: {
                                viewModel.showQuickTranslation = false
                                // Hızlı mod aktifse sadece seçimi temizle, büyük popup'a dönme
                                if viewModel.isQuickTranslationMode {
                                    viewModel.clearSelection()
                                } else if viewModel.selectedText != nil {
                                    viewModel.showTranslationPopup = true
                                }
                            }
                        )
                    }
                    
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
                } else {
                    // Error state when document failed to load
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundStyle(.red)
                        
                        Text("PDF Yüklenemedi")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Lütfen tekrar deneyin")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Button {
                            Task {
                                await viewModel.loadDocument()
                            }
                        } label: {
                            Text("Yeniden Dene")
                                .font(.headline)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.indigo)
                                .foregroundStyle(.white)
                                .cornerRadius(12)
                        }
                        
                        Button("Kapat") {
                            dismiss()
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .ignoresSafeArea()
            .navigationBarHidden(true)
            .edgeSwipeToDismiss {
                dismiss()
            }
            .sheet(isPresented: $showChat) {
                ChatView(viewModel: chatViewModel, onNavigateToPage: { page in
                    viewModel.goToPage(page)
                    showChat = false
                })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
            }
            .sheet(isPresented: $showQuiz) {
                QuizView(textContext: viewModel.extractedText)
            }
            .sheet(isPresented: $showSearch) {
                SearchSheet(viewModel: viewModel)
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
                startAutoHideTimer()
            }
            .onDisappear {
                // PDF kapatıldığında popup session memory'sini sıfırla
                QuickTranslationPopup.resetSessionMemory()
                logDebug("PDFReaderView", "View disappeared, popup session memory reset")
                autoHideTimer?.invalidate()
            }
            .onChange(of: showChat) { isOpen in
                if isOpen {
                    autoHideTimer?.invalidate()
                    // Görsel metadata yüklemesini devre dışı bıraktık - performans sorunu
                    // Görseller sadece kullanıcı görsel sorusu sorduğunda lazy load edilecek
                    // Eski kod:
                    // if let document = viewModel.document {
                    //     Task {
                    //         await chatViewModel.loadImageMetadata(document: document)
                    //     }
                    // }
                    
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
    
    // MARK: - Bar Toggle & Auto-Hide
    private func toggleBars() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            barsVisible.toggle()
        }
        
        if barsVisible {
            startAutoHideTimer()
        } else {
            autoHideTimer?.invalidate()
        }
    }
    
    private func startAutoHideTimer() {
        autoHideTimer?.invalidate()
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: autoHideDelay, repeats: false) { _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                barsVisible = false
            }
        }
    }
}


// MARK: - Collapsed Bar Indicator
struct CollapsedBarIndicator: View {
    enum Position { case top, bottom }
    let position: Position
    
    var body: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.3), lineWidth: 0.5)
            }
            .frame(width: 60, height: 5)
            .padding(position == .top ? .top : .bottom, position == .top ? 16 : 24)
    }
}


// MARK: - Reader Top Bar
struct ReaderTopBar: View {
    @ObservedObject var viewModel: PDFReaderViewModel
    @Binding var showSearch: Bool
    let onClose: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ReaderIconButton(systemName: "xmark", action: onClose)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.fileMetadata.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                if viewModel.totalPages > 0 {
                    Text("Sayfa \(viewModel.currentPage) / \(viewModel.totalPages)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            ReaderIconButton(systemName: "magnifyingglass") {
                showSearch = true
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            LiquidGlassBackground(cornerRadius: 18, intensity: .light, accentColor: .indigo)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 12)
        .padding(.top, 60)  // Safe area için Dynamic Island altında kalması için
    }
}

// MARK: - Reader Bottom Bar
struct ReaderBottomBar: View {
    @ObservedObject var viewModel: PDFReaderViewModel
    @Binding var showChat: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            // Sol: Sayfa Navigasyonu
            HStack(spacing: 8) {
                Button {
                    viewModel.previousPage()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(viewModel.currentPage <= 1 ? Color.secondary.opacity(0.4) : Color.primary)
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
                
                // Inline Page Spinner - yukarı/aşağı sürükleyerek sayfa değiştir
                PageSpinner(
                    currentPage: viewModel.currentPage,
                    totalPages: viewModel.totalPages,
                    onPageChange: { page in
                        viewModel.goToPage(page)
                    }
                )
                
                Button {
                    viewModel.nextPage()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(viewModel.currentPage >= viewModel.totalPages ? Color.secondary.opacity(0.4) : Color.primary)
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
            }
            
            Spacer()
            
            // Orta: Hızlı Çeviri Toggle
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
            
            Spacer()
            
            // Sağ: Chat Butonu
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
            }
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
}

// MARK: - Page Spinner (Wheel Picker)
/// iOS native wheel picker ile sayfa seçimi
/// Sayfa numarasına tıklandığında popover açılır
struct PageSpinner: View {
    let currentPage: Int
    let totalPages: Int
    let onPageChange: (Int) -> Void
    
    @State private var showPicker = false
    @State private var selectedPage: Int = 1
    
    var body: some View {
        Button {
            selectedPage = currentPage
            showPicker = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 4) {
                Text("\(currentPage)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text("/ \(max(totalPages, 1))")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 55)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            PagePickerPopover(
                selectedPage: $selectedPage,
                totalPages: totalPages,
                onConfirm: { page in
                    showPicker = false
                    if page != currentPage {
                        onPageChange(page)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                },
                onCancel: {
                    showPicker = false
                }
            )
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Page Picker Popover Content
/// Wheel picker içeren kompakt popover
struct PagePickerPopover: View {
    @Binding var selectedPage: Int
    let totalPages: Int
    let onConfirm: (Int) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("İptal") {
                    onCancel()
                }
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("Sayfa Seç")
                    .font(.system(size: 15, weight: .semibold))
                
                Spacer()
                
                Button("Git") {
                    onConfirm(selectedPage)
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.indigo)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            // Wheel Picker
            Picker("Sayfa", selection: $selectedPage) {
                ForEach(1...max(totalPages, 1), id: \.self) { page in
                    Text("\(page)")
                        .tag(page)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 150)
            .onChange(of: selectedPage) { _ in
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
        .frame(width: 220)
        .background(Color(.systemBackground))
    }
}

// MARK: - Reader Icon Button
struct ReaderIconButton: View {
    let systemName: String
    let action: () -> Void
    var isActive: Bool = true
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? .primary : .secondary)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.2), lineWidth: 0.5)
                        }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Search Sheet
struct SearchSheet: View {
    @ObservedObject var viewModel: PDFReaderViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Search Input
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Ara...", text: $viewModel.searchQuery)
                        .textFieldStyle(.plain)
                        .submitLabel(.search)
                        .onSubmit {
                            viewModel.search()
                        }
                    
                    if !viewModel.searchQuery.isEmpty {
                        Button {
                            viewModel.searchQuery = ""
                            viewModel.searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Results
                if viewModel.searchResults.isEmpty {
                    Spacer()
                    Text("Sonuç bulunamadı")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    HStack {
                        Button {
                            viewModel.previousSearchResult()
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        
                        Text("\(viewModel.currentSearchIndex + 1) / \(viewModel.searchResults.count)")
                            .font(.caption)
                        
                        Button {
                            viewModel.nextSearchResult()
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                    }
                    .padding()
                    
                    Spacer()
                }
            }
            .navigationTitle("Dokümanda Ara")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Note Detail Sheet
struct NoteDetailSheet: View {
    let annotation: Annotation
    let onSave: (String) -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    @State private var noteText: String = ""
    @State private var isEditing = false
    @State private var dragOffset = CGSize.zero
    @State private var showDeleteConfirmation = false

    private let maxCharacters = 500
    private let cornerRadius: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            dragHandle

            ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Küçük highlighted text preview
                        if let text = annotation.text, !text.isEmpty {
                            HStack(spacing: 8) {
                                Rectangle()
                                    .fill(Color.indigo)
                                    .frame(width: 2, height: 20)

                                Text(truncatedHighlightedText)
                                    .font(.caption)
                                    .italic()
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        }

                        // Not alanı
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Notunuz")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                if !isEditing {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isEditing = true
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "pencil")
                                                .font(.caption)
                                            Text("Düzenle")
                                                .font(.caption)
                                        }
                                        .foregroundStyle(.indigo)
                                    }
                                } else {
                                    // Karakter sayacı
                                    Text("\(noteText.count) / \(maxCharacters)")
                                        .font(.caption)
                                        .foregroundStyle(noteText.count > 450 ? .indigo : .secondary)
                                        .animation(.easeInOut(duration: 0.2), value: noteText.count)
                                }
                            }

                            if isEditing {
                                TextEditor(text: $noteText)
                                    .frame(minHeight: 120)
                                    .padding(12)
                                    .background(Color.indigo.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.indigo.opacity(0.3), lineWidth: 1)
                                    )
                                    .cornerRadius(12)
                            } else {
                                Text(noteText.isEmpty ? "Not eklemek için düzenleyin" : noteText)
                                    .font(.system(size: 15, weight: .regular, design: .rounded))
                                    .foregroundStyle(noteText.isEmpty ? .secondary : .primary)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.indigo.opacity(0.08))
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal, 16)

                        // Timestamp footer
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(timestampText)
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                    .padding(.top, 8)
                }

                // Bottom action bar (sadece edit modunda)
                if isEditing {
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                noteText = annotation.note ?? ""
                                isEditing = false
                            }
                        } label: {
                            Text("İptal")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                        }

                        Button {
                            saveWithAnimation()
                        } label: {
                            Text("Kaydet")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.indigo)
                                .cornerRadius(12)
                        }
                        .disabled(noteText.count > maxCharacters)
                        .opacity(noteText.count > maxCharacters ? 0.5 : 1.0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
        }
        .background(liquidGlassBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .shadow(color: .indigo.opacity(0.1), radius: 40, x: 0, y: 20)
        .overlay(alignment: .topLeading) {
            // Delete button
            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(width: 40, height: 40)
            }
            .padding(.top, 8)
            .padding(.leading, 16)
        }
        .overlay(alignment: .topTrailing) {
            // Close button
            Button {
                dismissWithAnimation()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, height: 40)
            }
            .padding(.top, 8)
            .padding(.trailing, 16)
        }
        .offset(y: dragOffset.height)
        .gesture(dragToDismissGesture)
        .animation(.easeInOut(duration: 0.2), value: isEditing)
        .confirmationDialog("Notu silmek istediğinize emin misiniz?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                deleteWithAnimation()
            }
            Button("İptal", role: .cancel) { }
        }
        .onAppear {
            noteText = annotation.note ?? ""
        }
    }

    // MARK: - Drag Handle
    private var dragHandle: some View {
        VStack(spacing: 0) {
            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(.systemGray3),
                                Color(.systemGray4)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 48, height: 6)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.8), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 46, height: 3)
                    .offset(y: -0.5)

                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.5), Color(.systemGray2)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
                    .frame(width: 48, height: 6)
            }
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: - Liquid Glass Background
    private var liquidGlassBackground: some View {
        LiquidGlassBackground(
            cornerRadius: cornerRadius,
            intensity: .medium,
            accentColor: .indigo
        )
    }

    // MARK: - Gestures
    private var dragToDismissGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation.height > 0 {
                    dragOffset = value.translation
                }
            }
            .onEnded { value in
                if value.translation.height > 100 {
                    dismissWithAnimation()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    // MARK: - Helper Functions
    private var truncatedHighlightedText: String {
        guard let text = annotation.text else { return "" }
        let cleaned = cleanupText(text)
        let words = cleaned.split(separator: " ")
        let preview = words.prefix(4).joined(separator: " ")
        return words.count > 4 ? "\(preview)..." : preview
    }

    private var timestampText: String {
        if let updated = annotation.updatedAt {
            return "Düzenlendi: \(updated.relativeTimeString())"
        } else {
            return "Eklendi: \(annotation.createdAt.relativeTimeString())"
        }
    }

    private func cleanupText(_ text: String) -> String {
        var cleaned = text
        cleaned = cleaned.replacingOccurrences(of: "-\n", with: "")
        cleaned = cleaned.replacingOccurrences(of: "\n", with: " ")
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveWithAnimation() {
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        onSave(noteText)
        isEditing = false

        // Sheet'in kendi dismiss animasyonunu kullan
        onDismiss()
    }

    private func deleteWithAnimation() {
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        onDelete()

        // Sheet'in kendi dismiss animasyonunu kullan
        onDismiss()
    }

    private func dismissWithAnimation() {
        // Sheet'in kendi dismiss animasyonunu kullan - daha profesyonel
        onDismiss()
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
