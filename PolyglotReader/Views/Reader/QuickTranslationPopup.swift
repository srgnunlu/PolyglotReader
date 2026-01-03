import SwiftUI

/// Seçilen metnin altında görünen hızlı çeviri popup'ı
/// Liquid Glass tasarımlı, sürüklenebilir ve ölçeklenebilir
struct QuickTranslationPopup: View {
    // MARK: - Session Memory (PDF oturumu boyunca hatırlanır)
    /// PDF kapatılınca sıfırlanır, aynı oturumda hatırlanır
    private static var sessionScale: CGFloat = 1.0
    let selectedText: String
    let selectionRect: CGRect
    let context: String? // PDF özeti
    let onDismiss: () -> Void
    
    // MARK: - State
    @State private var translatedText: String?
    @State private var isLoading = true
    @State private var isVisible = false
    
    // Drag (Sürükleme)
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    @GestureState private var isDragging = false
    
    // Scale (Büyütme/Küçültme)
    @State private var scale: CGFloat = QuickTranslationPopup.sessionScale

    @State private var lastScale: CGFloat = QuickTranslationPopup.sessionScale
    
    // Translation Task Management
    @State private var translationTask: Task<Void, Never>?
    
    // MARK: - Constants
    private let minScale: CGFloat = 0.6
    private let maxScale: CGFloat = 2.0
    private let cornerRadius: CGFloat = 24
    
    // Orientation-based dimensions
    private var baseContentHeight: CGFloat {
        isLandscape ? 120 : 180
    }
    
    private var popupWidth: CGFloat {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        
        if isLandscape {
            // Yatay modda ekranın %70'i, max 600
            return min(max(screenWidth, screenHeight) * 0.7, 600)
        } else {
            // Dikey modda ekranın genişliği - 40, max 340
            return min(min(screenWidth, screenHeight) - 40, 340)
        }
    }
    
    private var isLandscape: Bool {
        UIScreen.main.bounds.width > UIScreen.main.bounds.height
    }
    
    var body: some View {
        ZStack {

            // Popup içeriği
            popupContent
                .scaleEffect(scale)
                .offset(offset)
                .gesture(combinedGestures)
                .position(
                    x: selectionRect.midX,
                    y: selectionRect.maxY + 80
                )
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : -20)
        }
        .onAppear {
            // Başlangıç offset'ini ayarla
            offset = .zero
            lastOffset = .zero
            
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                isVisible = true
            }
            startTranslation(delay: 0)
        }
        .onChange(of: selectedText) { _ in
            // Seçilen metin değiştiğinde (tırnaklarla oynandığında)
            // Mevcut çeviriyi iptal et ve yeni çeviri başlat (debounce ile)
            startTranslation(delay: 0.6)
        }
    }
    
    // MARK: - Popup Content
    private var popupContent: some View {
        VStack(spacing: 0) {
            // Drag Handle
            dragHandle
            
            // İçerik Alanı - doğrudan çeviri
            contentArea
        }
        .frame(width: popupWidth)
        .background { liquidGlassBackground }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .shadow(color: .indigo.opacity(0.1), radius: 40, x: 0, y: 20)
    }
    
    // MARK: - Drag Handle
    private var dragHandle: some View {
        VStack(spacing: 0) {
            // Ana tutamacı - daha görünür tasarım
            ZStack {
                // Arka plan pill şekli
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
                
                // Üst parlama
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
                
                // Kenar çizgisi
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
    
    // MARK: - Content Area
    private var contentArea: some View {
        Group {
            if isLoading {
                loadingView
            } else if let translated = translatedText {
                translatedContentView(translated)
            } else {
                errorView
            }
        }
        .frame(maxHeight: baseContentHeight * scale)
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.9)
                .tint(.indigo)
            
            Text("Çevriliyor...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Translated Content View
    private func translatedContentView(_ text: String) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            Text(text)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
    }
    
    // MARK: - Error View
    private var errorView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            
            Text("Çeviri yapılamadı")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    // MARK: - Liquid Glass Background
    private var liquidGlassBackground: some View {
        ZStack {
            // Ana blur katmanı
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.ultraThinMaterial)
            
            // Gradient overlay - üst parlama
            LinearGradient(
                colors: [
                    .white.opacity(0.35),
                    .white.opacity(0.1),
                    .clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            
            // Renkli cam efekti
            RadialGradient(
                colors: [
                    .indigo.opacity(0.08),
                    .purple.opacity(0.05),
                    .clear
                ],
                center: .topLeading,
                startRadius: 0,
                endRadius: 200
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            
            // İç glow
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.7),
                            .white.opacity(0.3),
                            .white.opacity(0.1),
                            .white.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
            
            // Dış ince kenar
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(.white.opacity(0.2), lineWidth: 0.5)
                .blur(radius: 0.5)
        }
    }
    
    // MARK: - Gestures
    private var combinedGestures: some Gesture {
        // Drag ve magnification'u aynı anda tanı ama öncelik magnification'da
        magnificationGesture
            .simultaneously(with: dragGesture)
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.8)) {
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                }
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture(minimumScaleDelta: 0.005) // Daha hassas algılama
            .onChanged { value in
                // Daha hassas ve akıcı ölçekleme
                let sensitivity: CGFloat = 1.0 // 1.0 = normal, >1 = daha hassas
                let delta = (value - 1.0) * sensitivity
                let newScale = lastScale + delta
                
                // Sınırlar içinde tut
                let clampedScale = min(max(newScale, minScale), maxScale)
                
                // Akıcı animasyon
                withAnimation(.interactiveSpring(response: 0.1, dampingFraction: 0.85)) {
                    scale = clampedScale
                }
            }
            .onEnded { value in
                // Final değeri hesapla
                let sensitivity: CGFloat = 1.0
                let delta = (value - 1.0) * sensitivity
                var finalScale = lastScale + delta
                
                // Minimum snap
                if finalScale < 0.7 {
                    finalScale = 0.7
                }
                
                // Sınırla
                finalScale = min(max(finalScale, minScale), maxScale)
                
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    scale = finalScale
                    lastScale = finalScale
                    // Session memory'ı güncelle
                    QuickTranslationPopup.sessionScale = finalScale
                }
            }
    }
    
    // MARK: - Session Memory Reset
    /// PDF kapatılırken çağırılmalı
    static func resetSessionMemory() {
        sessionScale = 1.0
    }
    
    // MARK: - Actions
    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) {
            isVisible = false
            scale = 0.9
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            onDismiss()
        }
    }
    
    private func startTranslation(delay: TimeInterval) {
        // Varsa önceki task'ı iptal et
        translationTask?.cancel()
        
        translationTask = Task {
            // Debounce için bekle
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            
            if Task.isCancelled { return }
            
            await translate()
        }
    }

    private func translate() async {
        // Eğer metin çok kısaysa çevirme
        guard selectedText.count > 1 else { return }
        
        // UI güncellemesi
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let result = try await GeminiService.shared.translateText(selectedText, context: context)
            
            if !Task.isCancelled {
                // Sonuç geldiğinde göster
                await MainActor.run {
                    translatedText = result.translated
                    isLoading = false
                    logInfo("QuickTranslation", "Çeviri tamamlandı")
                }
            }
        } catch {
            if !Task.isCancelled {
                await MainActor.run {
                    translatedText = nil
                    isLoading = false
                    logError("QuickTranslation", "Çeviri hatası", error: error)
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        // Arka plan görsel simülasyonu
        LinearGradient(
            colors: [.blue.opacity(0.3), .purple.opacity(0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        
        // Örnek metin
        VStack {
            Text("Bu bir örnek metin paragrafıdır.")
                .padding()
                .background(.white)
                .cornerRadius(8)
            
            Spacer()
        }
        .padding(.top, 100)
        
        QuickTranslationPopup(
            selectedText: "The integration of artificial intelligence (AI) in dermatology presents a promising frontier for enhancing diagnostic accuracy and treatment planning.",
            selectionRect: CGRect(x: 200, y: 150, width: 100, height: 20),
            context: "Dermatolojide yapay zeka kullanımı ve tanı doğruluğu üzerine akademik bir çalışma.",
            onDismiss: {}
        )
    }
}
