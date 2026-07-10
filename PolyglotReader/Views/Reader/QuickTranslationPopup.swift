import SwiftUI

/// Seçilen metnin altında görünen hızlı çeviri popup'ı
/// Liquid Glass tasarımlı, sürüklenebilir ve ölçeklenebilir
struct QuickTranslationPopup: View {
    let selectedText: String
    let selectionRect: CGRect
    let context: String? // PDF özeti
    /// Pinch scale memory — lives in PDFReaderViewModel so it survives popup
    /// re-presentations within a session and resets when the reader closes.
    @Binding var persistedScale: CGFloat
    /// Depth layer CTA: hands the selection off to the AI chat. Optional so
    /// contexts without a chat (previews) simply hide the button.
    let onAskAI: (() -> Void)?
    let onDismiss: () -> Void

    init(
        selectedText: String,
        selectionRect: CGRect,
        context: String?,
        persistedScale: Binding<CGFloat>,
        onAskAI: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.selectedText = selectedText
        self.selectionRect = selectionRect
        self.context = context
        self._persistedScale = persistedScale
        self.onAskAI = onAskAI
        self.onDismiss = onDismiss
        self._scale = State(initialValue: persistedScale.wrappedValue)
        self._lastScale = State(initialValue: persistedScale.wrappedValue)
    }

    // MARK: - State
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var translationPhase: TranslationPopupPhase = .loading
    @State private var isVisible = false

    // Detail layer (depth on demand)
    @State private var isDetailExpanded = false
    @State private var detailPhase: TranslationDetailPhase = .idle
    @State private var detailTask: Task<Void, Never>?

    // Drag (Sürükleme)
    @State private var offset = CGSize.zero
    @State private var lastOffset = CGSize.zero
    @GestureState private var isDragging = false

    // Scale (Büyütme/Küçültme)
    @State private var scale: CGFloat
    @State private var lastScale: CGFloat

    // Translation Task Management
    @State private var translationTask: Task<Void, Never>?

    // MARK: - Constants
    private let minScale: CGFloat = 0.6
    private let maxScale: CGFloat = 2.0

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
                scale: scale,
                detailHeight: detailAllowance(expanded: isDetailExpanded)
            )

            popupContent(layout: layout)
                // Entrance: 0.92 → 1.0 on top of the user's pinch scale.
                .scaleEffect(scale * (isVisible ? 1.0 : 0.92))
                .offset(offset)
                .gesture(combinedGestures(layout: layout))
                .position(layout.basePosition)
                .opacity(isVisible ? 1 : 0)
        }
        .dsHaptic(.appear, trigger: isVisible) { _, new in new }
        .dsHaptic(.complete, trigger: translationPhase) { old, new in
            Self.translationJustCompleted(from: old, to: new)
        }
        .onAppear {
            // Başlangıç offset'ini ayarla
            offset = .zero
            lastOffset = .zero

            withAnimation(DSMotion.resolved(DSMotion.snappy, reduceMotion: reduceMotion)) {
                isVisible = true
            }
            startTranslation(delay: 0)
        }
        .onChange(of: selectedText) {
            // Seçilen metin değiştiğinde (tırnaklarla oynandığında)
            // Mevcut çeviriyi iptal et ve yeni çeviri başlat (debounce ile);
            // önceki seçimin detayı artık geçersiz.
            resetDetail()
            startTranslation(delay: 0.6)
        }
    }

    // MARK: - Popup Content

    private func popupContent(layout: TranslationPopupLayoutContext) -> some View {
        VStack(spacing: 0) {
            TranslationPopupDragHandle()
            TranslationPopupContentArea(phase: translationPhase, maxHeight: layout.contentMaxHeight)

            if case .translated = translationPhase {
                TranslationPopupDetailToggle(isExpanded: isDetailExpanded) {
                    toggleDetail(layout: layout)
                }

                if isDetailExpanded {
                    TranslationPopupDetailPanel(
                        phase: detailPhase,
                        onRetry: { loadDetail() },
                        onAskAI: onAskAI
                    )
                    .transition(.opacity)
                }
            }
        }
        .frame(width: layout.popupWidth)
        .translationPopupSurface()
        .dsAnimation(DSMotion.smooth, value: isDetailExpanded)
        .dsAnimation(DSMotion.smooth, value: detailPhase)
    }

    // MARK: - Detail Layer

    /// Unscaled height budget the detail layer adds to the popup, fed into
    /// the layout clamp so an expanded panel stays on screen.
    private func detailAllowance(expanded: Bool) -> CGFloat {
        guard case .translated = translationPhase else { return 0 }
        let toggle = TranslationPopupLayout.detailToggleHeight
        return expanded ? toggle + TranslationPopupLayout.detailPanelHeight : toggle
    }

    private func toggleDetail(layout: TranslationPopupLayoutContext) {
        let willExpand = !isDetailExpanded

        // Re-clamp the drag offset for the new size: a popup parked at the
        // bottom edge must slide up instead of growing off-screen.
        var expandedContext = layout
        expandedContext.detailHeight = detailAllowance(expanded: willExpand)
        let clampedOffset = TranslationPopupLayout.clampedOffset(
            offset,
            base: expandedContext.basePosition,
            popupSize: expandedContext.scaledSize,
            container: expandedContext.container
        )

        withAnimation(DSMotion.resolved(DSMotion.smooth, reduceMotion: reduceMotion)) {
            isDetailExpanded = willExpand
            offset = clampedOffset
            lastOffset = clampedOffset
        }

        if willExpand, detailPhase == .idle {
            loadDetail()
        }
    }

    private func loadDetail() {
        detailTask?.cancel()
        detailPhase = .loading

        detailTask = Task {
            do {
                let result = try await GeminiService.shared.translateTextDetailed(selectedText, context: context)
                if !Task.isCancelled {
                    detailPhase = .loaded(result)
                }
            } catch {
                if !Task.isCancelled {
                    detailPhase = .failed
                    logError("QuickTranslation", "Detaylı çeviri hatası", error: error)
                }
            }
        }
    }

    private func resetDetail() {
        detailTask?.cancel()
        detailPhase = .idle
        isDetailExpanded = false
    }

    // MARK: - Haptic Conditions

    /// True only for the loading → translated transition, so the completion
    /// haptic never fires on retries-into-failure or text re-selection.
    private static func translationJustCompleted(
        from old: TranslationPopupPhase,
        to new: TranslationPopupPhase
    ) -> Bool {
        guard old == .loading, case .translated = new else { return false }
        return true
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
                // Direct manipulation tracks the finger even with Reduce Motion.
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

                withAnimation(DSMotion.resolved(DSMotion.snappy, reduceMotion: reduceMotion)) {
                    scale = finalScale
                    lastScale = finalScale
                    offset = clampedOffset
                    lastOffset = clampedOffset
                }
                // Session memory: sonraki popup aynı ölçekle açılır.
                persistedScale = finalScale
            }
    }

    // MARK: - Actions

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
                    // Animated: the detail toggle appears and shifts the popup height.
                    withAnimation(DSMotion.resolved(DSMotion.smooth, reduceMotion: reduceMotion)) {
                        translationPhase = .translated(result.translated)
                    }
                    logInfo("QuickTranslation", "Çeviri tamamlandı")
                }
            }
        } catch {
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(DSMotion.resolved(DSMotion.smooth, reduceMotion: reduceMotion)) {
                        translationPhase = .failed
                    }
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
            context: "Dermatolojide yapay zeka kullanımı ve tanı doğruluğu üzerine akademik bir çalışma.",
            persistedScale: .constant(1.0)
        ) {}
    }
}
