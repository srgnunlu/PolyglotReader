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
    @State private var showNoteSheet = false
    @State private var noteText = ""
    @State private var showCopiedToast = false
    
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
    private let cornerRadius: CGFloat = 18
    private let verticalOffset: CGFloat = 20 // Seçimin altında ne kadar uzakta
    
    private let highlightColors = [
        "#fef08a", // Yellow
        "#bbf7d0", // Green
        "#fbcfe8", // Pink
        "#bae6fd"  // Blue
    ]
    
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
        x = max(popupWidth/2 + 8, min(screenWidth - popupWidth/2 - 8, x))
        
        // Y pozisyonu: seçimin altında, sığmazsa üstünde
        let belowSelectionY = selectionRect.maxY + verticalOffset + baseHeight/2
        let aboveSelectionY = selectionRect.minY - verticalOffset - baseHeight/2
        
        var y: CGFloat
        
        if belowSelectionY + baseHeight/2 < screenHeight - safeAreaBottom - 100 {
            y = belowSelectionY
        } else if aboveSelectionY - baseHeight/2 > safeAreaTop + 100 {
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
            // Sürüklenebilir alan (Drag Handle + Action Bar)
            draggableArea
            
            // Çeviri alanı - animasyonlu açılış (bağımsız scroll)
            if showTranslation {
                translationArea
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.95, anchor: .top)),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
        }
        .frame(width: popupWidth)
        .background { liquidGlassBackground }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        .shadow(color: .indigo.opacity(0.1), radius: 40, x: 0, y: 20)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showTranslation)
    }
    
    // MARK: - Draggable Area (sadece bu alan sürüklenebilir)
    
    private var draggableArea: some View {
        VStack(spacing: 0) {
            dragHandle
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
    
    // MARK: - Liquid Glass Background
    
    private var liquidGlassBackground: some View {
        LiquidGlassBackground(cornerRadius: cornerRadius, intensity: .medium, accentColor: .indigo)
    }
    
    // MARK: - Main Action Bar
    
    private var mainActionBar: some View {
        HStack(spacing: 6) {
            // Vurgulama renkleri
            ForEach(highlightColors, id: \.self) { colorHex in
                Button {
                    onHighlight(colorHex)
                } label: {
                    Circle()
                        .fill(Color(hex: colorHex) ?? .yellow)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.6), lineWidth: 0.5)
                        )
                }
            }
            
            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)
            
            // Çevir butonu
            CompactActionButton(
                icon: showTranslation ? "character.bubble.fill" : "character.bubble",
                isActive: showTranslation
            ) {
                toggleTranslation()
            }
            
            // AI butonu
            CompactActionButton(icon: "sparkles", isActive: false) {
                onAskAI()
            }
            
            // Kopyala butonu
            CompactActionButton(icon: "doc.on.doc", isActive: false) {
                copySelection()
            }
            
            // Diğer menü
            Menu {
                if onAddNote != nil {
                    Button {
                        showNoteSheet = true
                    } label: {
                        Label("Not Ekle", systemImage: "note.text")
                    }
                }
                
                Button {
                    shareText()
                } label: {
                    Label("Paylaş", systemImage: "square.and.arrow.up")
                }
            } label: {
                CompactActionLabel(icon: "ellipsis")
            }
            
            Divider()
                .frame(height: 20)
                .padding(.horizontal, 4)
            
            // Kapat butonu
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
    
    // MARK: - Translation Area
    
    private var translationArea: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 12)
            
            if isTranslating {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.indigo)
                    
                    Text("Çevriliyor...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 14)
                
            } else if let translated = translatedText {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(translated)
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
                .frame(maxHeight: 100) // Max 4-5 satır, içerik daha azsa küçülür
                
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
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
        translationTask?.cancel()
        onDismiss()
    }
    
    private func toggleTranslation() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showTranslation.toggle()
        }
        
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

// MARK: - Compact Action Button

struct CompactActionButton: View {
    let icon: String
    var isActive: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isActive ? .indigo : .primary)
                .frame(width: 36, height: 36)
                .background {
                    if isActive {
                        Circle()
                            .fill(Color.indigo.opacity(0.15))
                            .overlay(
                                Circle()
                                    .stroke(Color.indigo.opacity(0.3), lineWidth: 1)
                            )
                    } else {
                        Circle()
                            .fill(Color(.tertiarySystemBackground).opacity(0.6))
                    }
                }
        }
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }
}

struct CompactActionLabel: View {
    let icon: String
    
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: 36, height: 36)
            .background(Color(.tertiarySystemBackground).opacity(0.6))
            .clipShape(Circle())
    }
}

// MARK: - Add Note Sheet
struct AddNoteSheet: View {
    let selectedText: String
    @Binding var noteText: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Seçilen Metin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(selectedText)
                        .font(.subheadline)
                        .lineLimit(3)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notunuz")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    TextEditor(text: $noteText)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.top)
            .navigationTitle("Not Ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("İptal", action: onCancel)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kaydet") {
                        onSave(noteText)
                    }
                    .disabled(noteText.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Color Extension
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
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
