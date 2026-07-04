import SwiftUI

/// Seçilen metnin altında görünen hızlı çeviri popup'ı
/// Liquid Glass tasarımlı, sürüklenebilir ve ölçeklenebilir
struct QuickTranslationPopup: View {
    // MARK: - Session Memory (PDF oturumu boyunca hatırlanır)
    /// PDF kapatılınca sıfırlanır, aynı oturumda hatırlanır.
    /// TECH-DEBT: static state is shared across popup instances. Safe today because
    /// only one popup exists at a time and access is main-thread only; scoping it
    /// per instance would require changing the frozen public API.
    private static var sessionScale: CGFloat = 1.0

    let selectedText: String
    let selectionRect: CGRect
    let context: String? // PDF özeti
    let onDismiss: () -> Void

    // MARK: - State
    @State private var translationPhase: TranslationPopupPhase = .loading
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

    var body: some View {
        GeometryReader { geometry in
            // selectionRect arrives in screen coordinates; convert it to this
            // container's local space so clamping respects the safe area.
            let containerGlobal = geometry.frame(in: .global)
            let layout = TranslationPopupLayoutContext(
                containerSize: geometry.size,
                selectionRect: selectionRect.offsetBy(
                    dx: -containerGlobal.minX,
                    dy: -containerGlobal.minY
                ),
                scale: scale
            )

            popupContent(layout: layout)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(combinedGestures(layout: layout))
                .position(layout.basePosition)
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

    private func popupContent(layout: TranslationPopupLayoutContext) -> some View {
        VStack(spacing: 0) {
            TranslationPopupDragHandle()
            TranslationPopupContentArea(phase: translationPhase, maxHeight: layout.contentMaxHeight)
        }
        .frame(width: layout.popupWidth)
        .background { TranslationPopupBackground(cornerRadius: cornerRadius) }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .shadow(color: .indigo.opacity(0.1), radius: 40, x: 0, y: 20)
    }

    // MARK: - Gestures

    private func combinedGestures(layout: TranslationPopupLayoutContext) -> some Gesture {
        // Drag ve magnification'u aynı anda tanı ama öncelik magnification'da
        magnificationGesture(layout: layout)
            .simultaneously(with: dragGesture(layout: layout))
    }

    private func dragGesture(layout: TranslationPopupLayoutContext) -> some Gesture {
        DragGesture()
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                let proposed = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                // Clamp so the popup can never be dragged off-screen.
                let clamped = TranslationPopupLayout.clampedOffset(
                    proposed,
                    base: layout.basePosition,
                    popupSize: layout.scaledSize,
                    container: layout.container
                )
                withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.8)) {
                    offset = clamped
                }
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func magnificationGesture(layout: TranslationPopupLayoutContext) -> some Gesture {
        MagnificationGesture(minimumScaleDelta: 0.005) // Daha hassas algılama
            .onChanged { value in
                let newScale = lastScale + (value - 1.0)
                let clampedScale = min(max(newScale, minScale), maxScale)

                withAnimation(.interactiveSpring(response: 0.1, dampingFraction: 0.85)) {
                    scale = clampedScale
                }
            }
            .onEnded { value in
                var finalScale = lastScale + (value - 1.0)

                // Minimum snap
                if finalScale < 0.7 {
                    finalScale = 0.7
                }
                finalScale = min(max(finalScale, minScale), maxScale)

                // Re-clamp the offset for the new size so zooming can't push it off-screen.
                let rescaled = layout.rescaled(to: finalScale)
                let clampedOffset = TranslationPopupLayout.clampedOffset(
                    offset,
                    base: rescaled.basePosition,
                    popupSize: rescaled.scaledSize,
                    container: rescaled.container
                )

                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    scale = finalScale
                    lastScale = finalScale
                    offset = clampedOffset
                    lastOffset = clampedOffset
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

        await MainActor.run {
            translationPhase = .loading
        }

        do {
            let result = try await GeminiService.shared.translateText(selectedText, context: context)

            if !Task.isCancelled {
                await MainActor.run {
                    translationPhase = .translated(result.translated)
                    logInfo("QuickTranslation", "Çeviri tamamlandı")
                }
            }
        } catch {
            if !Task.isCancelled {
                await MainActor.run {
                    translationPhase = .failed
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
            Text("Bu bir örnek paragraf.")
                .padding()
                .background(.white)
                .cornerRadius(8)

            Spacer()
        }
        .padding(.top, 100)

        QuickTranslationPopup(
            selectedText: "The integration of artificial intelligence (AI) in dermatology presents"
                + " a promising frontier for enhancing diagnostic accuracy and treatment planning.",
            selectionRect: CGRect(x: 200, y: 150, width: 100, height: 20),
            context: "Dermatolojide yapay zeka kullanımı ve tanı doğruluğu üzerine akademik bir çalışma."
        ) {}
    }
}
