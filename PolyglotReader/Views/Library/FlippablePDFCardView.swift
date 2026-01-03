import SwiftUI

// MARK: - Flippable PDF Card View
/// PDF kartı için 3D flip animasyonlu wrapper
/// Long press + drag ile kartı çevirerek AI özetini gösterir
struct FlippablePDFCardView: View {
    let file: PDFDocumentMetadata
    let onTap: () -> Void
    let onDelete: () -> Void
    let onGenerateSummary: (_ force: Bool) -> Void
    var onMoveToFolder: ((Folder?) -> Void)? = nil
    var availableFolders: [Folder] = []
    
    @State private var isFlipped = false
    @State private var flipProgress: CGFloat = 0
    @State private var isDragging = false
    @State private var isGeneratingSummary = false
    
    private let flipThreshold: CGFloat = 0.5
    private let cardHeight: CGFloat = 210
    
    var body: some View {
        ZStack {
            // Arka yüz (Özet)
            backSide
                .opacity(flipProgress > 0.5 ? 1 : 0)
                .rotation3DEffect(
                    .degrees(180),
                    axis: (x: 0, y: 1, z: 0)
                )
            
            // Ön yüz (Thumbnail)
            frontSide
                .opacity(flipProgress <= 0.5 ? 1 : 0)
        }
        .frame(height: cardHeight)
        .rotation3DEffect(
            .degrees(flipProgress * 180),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.5
        )
        .compositingGroup() // Opacity ve blending optimizasyonu
        .gesture(flipGesture)
        .onChange(of: isFlipped) { newValue in
            if newValue && file.summary == nil && !isGeneratingSummary {
                isGeneratingSummary = true
                onGenerateSummary(false)
            }
        }
    }
    
    // MARK: - Front Side (Thumbnail)
    private var frontSide: some View {
        PDFCardView(
            file: file,
            onTap: onTap,
            onDelete: onDelete,
            onMoveToFolder: onMoveToFolder,
            availableFolders: availableFolders
        )
            .overlay(alignment: .topTrailing) {
                // Minimal AI Summary Button
                Button {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        isFlipped = true
                        flipProgress = 1.0
                    }
                } label: {
                    Image(systemName: "sparkle")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.purple.opacity(0.9),
                                            Color.indigo.opacity(0.85)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .shadow(color: .purple.opacity(0.35), radius: 6, x: 0, y: 3)
                        }
                        .overlay {
                            Circle()
                                .stroke(.white.opacity(0.25), lineWidth: 0.5)
                        }
                }
                .padding(8)
            }
    }
    
    // MARK: - Back Side (Summary)
    private var backSide: some View {
        ZStack {
            // Liquid Glass Background
            LiquidGlassBackground(
                cornerRadius: 20,
                intensity: .medium,
                accentColor: .purple
            )
            
            // Content
            VStack(alignment: .leading, spacing: 0) {
                // Doğrudan özet içeriği
                summaryContent
            }
            
            // Üst köşede geri dön göstergesi
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .frame(width: 20, height: 20)
                        .background {
                            Circle()
                                .fill(.ultraThinMaterial)
                        }
                }
                .padding(10)
                Spacer()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
        .onTapGesture {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                isFlipped = false
                flipProgress = 0
            }
        }
    }
    
    // MARK: - Summary Content
    private var summaryContent: some View {
        Group {
            if let summary = file.summary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    // Özet metni - elegant tipografi
                    ScrollView(.vertical, showsIndicators: false) {
                        Text(summary)
                            .font(.system(size: 12, weight: .regular, design: .serif))
                            .italic()
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.primary, .primary.opacity(0.85)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Alt kısım: kategori ve yenile butonu
                    HStack(spacing: 8) {
                        if let category = detectCategory(from: summary) {
                            categoryBadge(category)
                        }

                        Spacer()

                        // Yeniden oluştur butonu
                        Button {
                            isGeneratingSummary = true
                            onGenerateSummary(true)
                        } label: {
                            Image(systemName: "arrow.trianglehead.2.clockwise")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.purple.opacity(0.7))
                                .padding(6)
                                .background {
                                    Circle()
                                        .fill(.purple.opacity(0.1))
                                }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            } else if isGeneratingSummary {
                loadingView
            } else {
                emptyStateView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Loading View
    @State private var isRotating = false
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            // Animated shimmer effect
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.1), .indigo.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                Image(systemName: "sparkle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(isRotating ? 1.15 : 0.9)
                    .opacity(isRotating ? 1 : 0.6)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isRotating)
            }
            
            Text("Özet hazırlanıyor...")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isRotating = true }
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.quote")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple.opacity(0.5), .indigo.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Henüz özet yok")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            
            Button {
                isGeneratingSummary = true
                onGenerateSummary(false)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10, weight: .bold))
                    Text("Oluştur")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .indigo],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .purple.opacity(0.3), radius: 6, x: 0, y: 3)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Category Badge
    private func categoryBadge(_ category: DocumentCategory) -> some View {
        HStack(spacing: 4) {
            Image(systemName: category.icon)
                .font(.caption2)
            Text(category.displayName)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(category.color.opacity(0.15))
        .foregroundStyle(category.color)
        .clipShape(Capsule())
    }
    
    // MARK: - Flip Gesture
    private var flipGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 20))
            .onChanged { value in
                switch value {
                case .first(true):
                    // Long press başladı
                    withAnimation(.easeOut(duration: 0.1)) {
                        isDragging = true
                    }
                case .second(true, let drag):
                    guard let drag = drag else { return }
                    // Drag ile flip progress güncelle
                    let dragAmount = drag.translation.width
                    let newProgress = min(1.0, abs(dragAmount) / 100)
                    
                    withAnimation(.interactiveSpring()) {
                        flipProgress = isFlipped ? (1.0 - newProgress) : newProgress
                    }
                default:
                    break
                }
            }
            .onEnded { value in
                isDragging = false
                
                // Threshold'u geçtiyse flip yap
                if flipProgress > flipThreshold {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                        isFlipped = true
                        flipProgress = 1.0
                    }
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isFlipped = false
                        flipProgress = 0
                    }
                }
            }
    }
    
    // MARK: - Category Detection
    private func detectCategory(from summary: String) -> DocumentCategory? {
        let lowercased = summary.lowercased()
        
        if lowercased.contains("tıp") || lowercased.contains("sağlık") || lowercased.contains("tedavi") || lowercased.contains("hastalık") || lowercased.contains("ilaç") {
            return .medical
        } else if lowercased.contains("hukuk") || lowercased.contains("mahkeme") || lowercased.contains("kanun") || lowercased.contains("sözleşme") || lowercased.contains("dava") {
            return .legal
        } else if lowercased.contains("finans") || lowercased.contains("ekonomi") || lowercased.contains("borsa") || lowercased.contains("yatırım") || lowercased.contains("banka") {
            return .finance
        } else if lowercased.contains("akademik") || lowercased.contains("araştırma") || lowercased.contains("bilimsel") || lowercased.contains("makale") || lowercased.contains("tez") {
            return .academic
        } else if lowercased.contains("teknik") || lowercased.contains("mühendislik") || lowercased.contains("yazılım") || lowercased.contains("algoritma") {
            return .technical
        }
        
        return nil
    }
}

// MARK: - Document Category
enum DocumentCategory {
    case medical
    case legal
    case finance
    case academic
    case technical
    
    var displayName: String {
        switch self {
        case .medical: return "Tıbbi"
        case .legal: return "Hukuki"
        case .finance: return "Finansal"
        case .academic: return "Akademik"
        case .technical: return "Teknik"
        }
    }
    
    var icon: String {
        switch self {
        case .medical: return "cross.case.fill"
        case .legal: return "building.columns.fill"
        case .finance: return "chart.line.uptrend.xyaxis"
        case .academic: return "graduationcap.fill"
        case .technical: return "gearshape.2.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .medical: return .red
        case .legal: return .orange
        case .finance: return .green
        case .academic: return .blue
        case .technical: return .purple
        }
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        LinearGradient(
            colors: [.blue.opacity(0.1), .purple.opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        
        HStack(spacing: 16) {
            // Özetsiz kart
            FlippablePDFCardView(
                file: PDFDocumentMetadata(
                    id: "1",
                    name: "Örnek Doküman.pdf",
                    size: 2456789,
                    uploadedAt: Date(),
                    storagePath: "/path"
                ),
                onTap: {},
                onDelete: {},
                onGenerateSummary: { _ in }
            )
            .frame(width: 170)
            
            // Özetli kart
            FlippablePDFCardView(
                file: PDFDocumentMetadata(
                    id: "2",
                    name: "Tıbbi Rapor.pdf",
                    size: 1234567,
                    uploadedAt: Date(),
                    storagePath: "/path",
                    summary: "Bu doküman, kronik hastalıkların tedavisinde kullanılan yeni ilaç tedavilerini incelemektedir. Araştırma, klinik deney sonuçlarını ve hasta takip verilerini içermektedir."
                ),
                onTap: {},
                onDelete: {},
                onGenerateSummary: { _ in }
            )
            .frame(width: 170)
        }
        .padding()
    }
}
