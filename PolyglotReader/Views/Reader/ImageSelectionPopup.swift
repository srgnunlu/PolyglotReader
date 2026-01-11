import SwiftUI
import Photos

// MARK: - Image Selection Popup
/// PDF'den seçilen görsel bölge için aksiyon popup'ı
struct ImageSelectionPopup: View {
    let imageInfo: PDFImageInfo
    let onDismiss: () -> Void
    let onAskAI: () -> Void
    
    // MARK: - State
    @State private var showDescription = false
    @State private var descriptionText: String?
    @State private var isAnalyzing = false
    @State private var analysisTask: Task<Void, Never>?
    @State private var showCopiedToast = false
    @State private var showSavedToast = false
    @State private var showShareSheet = false
    @State private var showFullscreen = false
    
    // Drag state
    @State private var currentOffset: CGSize = .zero
    @State private var accumulatedOffset: CGSize = .zero
    @State private var initialPosition: CGPoint = .zero
    @State private var hasCalculatedInitialPosition = false
    
    // MARK: - Layout Constants
    private let popupWidth: CGFloat = 320
    private let cornerRadius: CGFloat = 18
    private let verticalOffset: CGFloat = 20
    
    var body: some View {
        GeometryReader { geometry in
            popupContent
                .position(x: initialPosition.x + accumulatedOffset.width + currentOffset.width,
                          y: initialPosition.y + accumulatedOffset.height + currentOffset.height)
                .onAppear {
                    if !hasCalculatedInitialPosition {
                        initialPosition = calculateInitialPosition(in: geometry)
                        hasCalculatedInitialPosition = true
                    }
                }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showShareSheet) {
            ImageShareSheet(image: imageInfo.image)
        }
        .fullScreenCover(isPresented: $showFullscreen) {
            FullscreenImageView(image: imageInfo.image) {
                showFullscreen = false
            }
        }
        .onDisappear {
            analysisTask?.cancel()
        }
    }
    
    // MARK: - Initial Position Calculator
    
    private func calculateInitialPosition(in geometry: GeometryProxy) -> CGPoint {
        let screenWidth = geometry.size.width
        let screenHeight = geometry.size.height
        let safeAreaTop = geometry.safeAreaInsets.top
        let safeAreaBottom = geometry.safeAreaInsets.bottom
        
        let baseHeight: CGFloat = 200 // Görsel önizleme + butonlar
        
        // X pozisyonu: seçimin ortasında
        var x = imageInfo.screenRect.midX
        x = max(popupWidth / 2 + 8, min(screenWidth - popupWidth / 2 - 8, x))
        
        // Y pozisyonu: seçimin altında
        let belowSelectionY = imageInfo.screenRect.maxY + verticalOffset + baseHeight / 2
        let aboveSelectionY = imageInfo.screenRect.minY - verticalOffset - baseHeight / 2
        
        var y: CGFloat
        
        if belowSelectionY + baseHeight / 2 < screenHeight - safeAreaBottom - 100 {
            y = belowSelectionY
        } else if aboveSelectionY - baseHeight / 2 > safeAreaTop + 100 {
            y = aboveSelectionY
        } else {
            y = screenHeight / 2
        }
        
        y = max(safeAreaTop + 40, min(screenHeight - safeAreaBottom - 60, y))
        
        return CGPoint(x: x, y: y)
    }
    
    // MARK: - Drag Gesture
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                currentOffset = value.translation
            }
            .onEnded { value in
                accumulatedOffset.width += value.translation.width
                accumulatedOffset.height += value.translation.height
                currentOffset = .zero
            }
    }
    
    // MARK: - Popup Content
    
    private var popupContent: some View {
        VStack(spacing: 0) {
            // Sürüklenebilir alan
            draggableArea
            
            // Açıklama alanı
            if showDescription {
                descriptionArea
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .frame(width: popupWidth)
        .background { liquidGlassBackground }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .shadow(color: .indigo.opacity(0.1), radius: 40, x: 0, y: 20)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showDescription)
    }
    
    // MARK: - Draggable Area
    
    private var draggableArea: some View {
        VStack(spacing: 0) {
            dragHandle
            imagePreview
            mainActionBar
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }
    
    // MARK: - Drag Handle
    
    private var dragHandle: some View {
        VStack(spacing: 0) {
            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(.systemGray3), Color(.systemGray4)],
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
            }
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
        }
        .frame(height: 20)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
    
    // MARK: - Image Preview
    
    private var imagePreview: some View {
        Image(uiImage: imageInfo.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxHeight: 120)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            .onTapGesture {
                showFullscreen = true
            }
    }
    
    // MARK: - Liquid Glass Background
    
    private var liquidGlassBackground: some View {
        LiquidGlassBackground(cornerRadius: cornerRadius, intensity: .medium, accentColor: .indigo)
    }
    
    // MARK: - Main Action Bar
    
    private var mainActionBar: some View {
        HStack(spacing: 6) {
            // Kopyala
            CompactActionButton(icon: "doc.on.doc", isActive: false) {
                copyImage()
            }
            
            // AI'a Sor
            CompactActionButton(icon: "sparkles", isActive: false) {
                onAskAI()
            }
            
            // Açıkla
            CompactActionButton(
                icon: showDescription ? "text.bubble.fill" : "text.bubble",
                isActive: showDescription
            ) {
                toggleDescription()
            }
            
            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)
            
            // Diğer menü
            Menu {
                Button {
                    saveImage()
                } label: {
                    Label("Kaydet", systemImage: "square.and.arrow.down")
                }
                
                Button {
                    showShareSheet = true
                } label: {
                    Label("Paylaş", systemImage: "square.and.arrow.up")
                }
                
                Button {
                    showFullscreen = true
                } label: {
                    Label("Büyüt", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            } label: {
                CompactActionLabel(icon: "ellipsis")
            }
            
            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)
            
            // Kapat
            Button(action: dismissPopup) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(.tertiarySystemBackground).opacity(0.8))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    // MARK: - Description Area
    
    private var descriptionArea: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 12)
            
            if isAnalyzing {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.indigo)
                    
                    Text("Analiz ediliyor...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 14)
            } else if let description = descriptionText {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(description)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .textSelection(.enabled)
                }
                .scrollIndicators(.visible)
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 120)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                    
                    Text("Analiz yapılamadı")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button {
                        startAnalysis()
                    } label: {
                        Text("Tekrar Dene")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.indigo)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        }
        .background {
            LinearGradient(
                colors: [
                    Color(.systemBackground).opacity(0.05),
                    Color(.systemBackground).opacity(0.1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    // MARK: - Actions
    
    private func dismissPopup() {
        analysisTask?.cancel()
        onDismiss()
    }
    
    private func toggleDescription() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showDescription.toggle()
        }
        
        if showDescription && descriptionText == nil && !isAnalyzing {
            startAnalysis()
        }
    }
    
    private func startAnalysis() {
        analysisTask?.cancel()
        
        analysisTask = Task {
            await analyzeImage()
        }
    }
    
    private func analyzeImage() async {
        guard let jpegData = imageInfo.jpegData else {
            await MainActor.run {
                descriptionText = nil
            }
            return
        }
        
        await MainActor.run {
            isAnalyzing = true
        }
        
        do {
            let result = try await GeminiService.shared.analyzeImage(jpegData)
            
            if !Task.isCancelled {
                await MainActor.run {
                    descriptionText = result
                    isAnalyzing = false
                }
            }
        } catch {
            if !Task.isCancelled {
                await MainActor.run {
                    descriptionText = nil
                    isAnalyzing = false
                }
            }
        }
    }
    
    private func copyImage() {
        UIPasteboard.general.image = imageInfo.image
        
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        showCopiedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopiedToast = false
        }
    }
    
    private func saveImage() {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            if status == .authorized || status == .limited {
                UIImageWriteToSavedPhotosAlbum(imageInfo.image, nil, nil, nil)
                
                DispatchQueue.main.async {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    showSavedToast = true
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showSavedToast = false
                    }
                }
            }
        }
    }
}
