import SwiftUI

// MARK: - Flippable PDF Card View
/// PDF kartı için 3D flip animasyonlu wrapper
/// Sağ üstteki sparkle butonuyla kart çevrilir ve AI özeti gösterilir
struct FlippablePDFCardView: View {
    let file: PDFDocumentMetadata
    let onTap: () -> Void
    let onDelete: () -> Void
    /// Async: kart, üretim bitene (veya hata alana) kadar spinner gösterir,
    /// sonra durumu sıfırlar — başarısızlıkta sonsuz "hazırlanıyor" kalmaz.
    let onGenerateSummary: (_ force: Bool) async -> Void
    var onMoveToFolder: ((Folder?) -> Void)?
    var onRename: (() -> Void)?
    var onShare: (() -> Void)?
    var onToggleFavorite: (() -> Void)?
    var availableFolders: [Folder] = []
    var isThumbnailLoading: Bool = false

    @State private var isFlipped = false
    @State private var flipProgress: CGFloat = 0
    @State private var isGeneratingSummary = false

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
        .onChange(of: isFlipped) { newValue in
            if newValue && file.summary == nil && !isGeneratingSummary {
                generateSummary(force: false)
            }
        }
    }

    /// Üretimi başlatır ve tamamlanınca (başarı ya da hata) spinner durumunu kapatır.
    private func generateSummary(force: Bool) {
        isGeneratingSummary = true
        Task {
            await onGenerateSummary(force)
            isGeneratingSummary = false
        }
    }

    // MARK: - Front Side (Thumbnail)
    private var frontSide: some View {
        PDFCardView(
            file: file,
            onTap: onTap,
            onDelete: onDelete,
            onMoveToFolder: onMoveToFolder,
            onRename: onRename,
            onShare: onShare,
            onToggleFavorite: onToggleFavorite,
            availableFolders: availableFolders,
            isThumbnailLoading: isThumbnailLoading
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
                            generateSummary(force: true)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var loadingView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [DSColor.aiAccent.opacity(0.1), DSColor.brand.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)

                sparklePulse
            }

            Text("pdf_card.summary.loading".localized)
                .font(Font.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// AI özeti hazırlanırken sparkle nabzı — dikkat döngüsü PhaseAnimator'da;
    /// Reduce Motion'da statik parlak hal.
    @ViewBuilder
    private var sparklePulse: some View {
        let icon = Image(systemName: "sparkle")
            .font(.title3.weight(.medium))
            .foregroundStyle(
                LinearGradient(
                    colors: [DSColor.aiAccent, DSColor.brand],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

        if reduceMotion {
            icon
        } else {
            icon.phaseAnimator([false, true]) { view, pulsing in
                view
                    .scaleEffect(pulsing ? 1.15 : 0.9)
                    .opacity(pulsing ? 1 : 0.6)
            } animation: { _ in
                .easeInOut(duration: 0.8)
            }
        }
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

            Text("pdf_card.summary.empty".localized)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Button {
                generateSummary(force: false)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 10, weight: .bold))
                    Text("pdf_card.summary.generate".localized)
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

    // MARK: - Category Detection
    private func detectCategory(from summary: String) -> DocumentCategory? {
        let lowercased = summary.lowercased()

        if lowercased.contains("tıp") || lowercased.contains("sağlık") ||
           lowercased.contains("tedavi") || lowercased.contains("hastalık") ||
           lowercased.contains("ilaç") {
            return .medical
        } else if lowercased.contains("hukuk") || lowercased.contains("mahkeme") ||
                  lowercased.contains("kanun") || lowercased.contains("sözleşme") ||
                  lowercased.contains("dava") {
            return .legal
        } else if lowercased.contains("finans") || lowercased.contains("ekonomi") ||
                  lowercased.contains("borsa") || lowercased.contains("yatırım") ||
                  lowercased.contains("banka") {
            return .finance
        } else if lowercased.contains("akademik") || lowercased.contains("araştırma") ||
                  lowercased.contains("bilimsel") || lowercased.contains("makale") ||
                  lowercased.contains("tez") {
            return .academic
        } else if lowercased.contains("teknik") || lowercased.contains("mühendislik") ||
                  lowercased.contains("yazılım") || lowercased.contains("algoritma") {
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
        case .medical: return "pdf_card.category.medical".localized
        case .legal: return "pdf_card.category.legal".localized
        case .finance: return "pdf_card.category.finance".localized
        case .academic: return "pdf_card.category.academic".localized
        case .technical: return "pdf_card.category.technical".localized
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
                    summary: """
                    Bu doküman, kronik hastalıkların tedavisinde kullanılan yeni ilaç tedavilerini \
                    incelemektedir. Araştırma, klinik deney sonuçlarını ve hasta takip verilerini içermektedir.
                    """
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
