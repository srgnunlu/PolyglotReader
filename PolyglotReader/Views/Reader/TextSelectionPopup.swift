import SwiftUI

struct TextSelectionPopup: View {
    let selectedText: String
    let selectionRect: CGRect
    let context: String? // PDF özeti
    let onDismiss: () -> Void
    let onHighlight: (String) -> Void
    let onAskAI: () -> Void
    var onAddNote: ((String) async -> Void)?

    // MARK: - State
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showNoteSheet = false
    @State private var noteText = ""
    @State private var showCopiedToast = false

    // İkinci satıra genişleyen aksiyonlar ("..." menüsünün yerini alır)
    @State private var showMoreActions = false

    // Inline çeviri için state
    @State private var showTranslation = false
    @State private var translatedText: String?
    @State private var isTranslating = false
    @State private var translationTask: Task<Void, Never>?

    // Drag state
    @State private var currentOffset: CGSize = .zero
    @State private var accumulatedOffset: CGSize = .zero
    @State private var initialPosition: CGPoint = .zero
    @State private var hasCalculatedInitialPosition = false

    // MARK: - Layout Constants
    private let popupWidth: CGFloat = 360
    private let verticalOffset: CGFloat = 20 // Seçimin altında ne kadar uzakta

    private let highlightColors = DSColor.Highlight.allCases

    var body: some View {
        GeometryReader { geometry in
            // Popup içeriği
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
        .sheet(isPresented: $showNoteSheet) {
            AddNoteSheet(
                selectedText: selectedText,
                noteText: $noteText,
                onSave: { note in
                    Task {
                        await onAddNote?(note)
                        await MainActor.run {
                            showNoteSheet = false
                            noteText = ""
                            dismissPopup()
                        }
                    }
                },
                onCancel: {
                    showNoteSheet = false
                    noteText = ""
                }
            )
            .presentationDetents([.medium])
        }
        .onDisappear {
            translationTask?.cancel()
        }
    }

    // MARK: - Initial Position Calculator (sadece bir kez çağrılır)

    private func calculateInitialPosition(in geometry: GeometryProxy) -> CGPoint {
        let screenWidth = geometry.size.width
        let screenHeight = geometry.size.height
        let safeAreaTop = geometry.safeAreaInsets.top
        let safeAreaBottom = geometry.safeAreaInsets.bottom

        let baseHeight: CGFloat = 70

        // X pozisyonu: seçimin ortasında, ekran sınırları içinde
        var x = selectionRect.midX
        x = max(popupWidth / 2 + 8, min(screenWidth - popupWidth / 2 - 8, x))

        // Y pozisyonu: seçimin altında, sığmazsa üstünde
        let belowSelectionY = selectionRect.maxY + verticalOffset + baseHeight / 2
        let aboveSelectionY = selectionRect.minY - verticalOffset - baseHeight / 2

        var y: CGFloat

        if belowSelectionY + baseHeight / 2 < screenHeight - safeAreaBottom - 100 {
            y = belowSelectionY
        } else if aboveSelectionY - baseHeight / 2 > safeAreaTop + 100 {
            y = aboveSelectionY
        } else {
            y = screenHeight / 2
        }

        // Ekran sınırları içinde tut
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
            // Sürüklenebilir alan (Drag Handle + Action Bar + genişleyen satır)
            draggableArea

            // Çeviri alanı - animasyonlu açılış (bağımsız scroll)
            if showTranslation {
                translationArea
                    .transition(.asymmetric(
                        insertion: .move(edge: .top)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.95, anchor: .top)),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .frame(width: popupWidth)
        .dsGlass(.popup, shape: .rounded(DSRadius.medium))
        .dsShadow(.floating)
        .overlay(alignment: .top) {
            if showCopiedToast {
                copiedToast
                    .offset(y: -38)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            }
        }
        .dsAnimation(DSMotion.smooth, value: showTranslation)
        .dsAnimation(DSMotion.snappy, value: showMoreActions)
        .dsAnimation(DSMotion.snappy, value: showCopiedToast)
        .dsHaptic(.complete, trigger: translatedText) { old, new in
            old == nil && new != nil
        }
    }

    // MARK: - Copied Toast

    private var copiedToast: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
            Text("Kopyalandı")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, DSSpacing.xs)
        .background(Capsule().fill(DSColor.success))
        .dsShadow(.subtle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Metin kopyalandı")
    }

    // MARK: - Draggable Area (sadece bu alan sürüklenebilir)

    private var draggableArea: some View {
        VStack(spacing: 0) {
            dragHandle
            mainActionBar

            if showMoreActions {
                expandedActionRow
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
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

    // MARK: - Main Action Bar

    private var mainActionBar: some View {
        HStack(spacing: 6) {
            // Vurgulama renkleri
            ForEach(highlightColors, id: \.rawValue) { highlight in
                Button {
                    DSHaptics.selection()
                    onHighlight(highlight.rawValue)
                } label: {
                    Circle()
                        .fill(highlight.color)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.6), lineWidth: 0.5)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(HighlightDotButtonStyle())
                .accessibilityLabel("\(highlight.localizedName) ile vurgula")
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // Çevir butonu
            CompactActionButton(
                icon: showTranslation ? "character.bubble.fill" : "character.bubble",
                isActive: showTranslation,
                accessibilityLabel: "Çevir"
            ) {
                toggleTranslation()
            }

            // AI butonu
            CompactActionButton(icon: "sparkles", isActive: false, accessibilityLabel: "Yapay zekaya sor") {
                onAskAI()
            }

            // Kopyala butonu
            CompactActionButton(icon: "doc.on.doc", isActive: false, accessibilityLabel: "Kopyala") {
                copySelection()
            }

            // Daha fazla aksiyon: menü yerine ikinci satıra genişler
            CompactActionButton(
                icon: "ellipsis",
                isActive: showMoreActions,
                accessibilityLabel: showMoreActions ? "Diğer aksiyonları gizle" : "Diğer aksiyonlar"
            ) {
                showMoreActions.toggle()
            }

            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)

            // Kapat butonu
            Button(action: dismissPopup) {
                Image(systemName: "xmark")
                    .font(DSFont.meta.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(.tertiarySystemBackground).opacity(0.8))
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("Kapat")
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.vertical, 10)
    }

    // MARK: - Expanded Action Row

    /// PDF Expert dersi: gizli menü yerine bağlamsal, görünür ikinci satır.
    private var expandedActionRow: some View {
        HStack(spacing: DSSpacing.xs) {
            if onAddNote != nil {
                expandedActionButton(icon: "note.text", title: "Not Ekle") {
                    showNoteSheet = true
                }
            }

            expandedActionButton(icon: "square.and.arrow.up", title: "Paylaş") {
                shareText()
            }

            Spacer()
        }
        .padding(.horizontal, DSSpacing.sm)
        .padding(.bottom, DSSpacing.xs)
    }

    private func expandedActionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.xxs + 2) {
                Image(systemName: icon)
                    .font(DSFont.controlIcon)

                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(Capsule().fill(Color(.tertiarySystemBackground).opacity(0.6)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Translation Area

    private var translationArea: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, DSSpacing.sm)

            if isTranslating {
                VStack(spacing: DSSpacing.xs) {
                    TranslationWaveIndicator()

                    Text("Çevriliyor...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DSSpacing.md)
                .padding(.horizontal, 14)
            } else if let translated = translatedText {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(translated)
                        .font(DSFont.translation)
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
                .frame(maxHeight: 100) // Max 4-5 satır, içerik daha azsa küçülür
            } else {
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DSColor.warning)
                        .font(.subheadline)

                    Text("Çeviri yapılamadı")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        startTranslation()
                    } label: {
                        Text("Tekrar Dene")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(DSColor.brand)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, DSSpacing.sm)
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
        translationTask?.cancel()
        onDismiss()
    }

    private func toggleTranslation() {
        showTranslation.toggle()

        if showTranslation && translatedText == nil && !isTranslating {
            startTranslation()
        }
    }

    private func startTranslation() {
        translationTask?.cancel()

        translationTask = Task {
            await translate()
        }
    }

    private func translate() async {
        guard selectedText.count > 1 else { return }

        await MainActor.run {
            isTranslating = true
        }

        do {
            let result = try await GeminiService.shared.translateText(selectedText, context: context)

            if !Task.isCancelled {
                await MainActor.run {
                    translatedText = result.translated
                    isTranslating = false
                }
            }
        } catch {
            if !Task.isCancelled {
                await MainActor.run {
                    translatedText = nil
                    isTranslating = false
                }
            }
        }
    }

    private func copySelection() {
        UIPasteboard.general.string = selectedText
        showCopiedToast = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showCopiedToast = false
        }
    }

    private func shareText() {
        let activityVC = UIActivityViewController(
            activityItems: [selectedText],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - Highlight Dot Button Style

/// Vurgu rengi noktası: basılıyken spring ile büyür — "bu rengi seçiyorsun"
/// hissi. Haptic, aksiyonun kendisinde (.selection) tetiklenir.
private struct HighlightDotButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.25 : 1.0)
            .dsAnimation(DSMotion.snappy, value: configuration.isPressed)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()

        TextSelectionPopup(
            selectedText: "Bu bir örnek seçilen metindir ve aksiyon barı test ediliyor.",
            selectionRect: CGRect(x: 100, y: 200, width: 200, height: 30),
            context: nil,
            onDismiss: {},
            onHighlight: { _ in },
            onAskAI: {}
        )
    }
}
