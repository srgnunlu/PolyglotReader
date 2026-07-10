import SwiftUI

// MARK: - Detail Phase

/// Derinlik katmanı durumu: kullanıcı "Detay" kolunu çekene kadar `idle` kalır.
enum TranslationDetailPhase: Equatable {
    case idle
    case loading
    case loaded(DetailedTranslationResult)
    case failed
}

// MARK: - Detail Toggle

/// Popup'ın altındaki "Detay" çekme kolu — LingQ modeli: isteyene derinlik,
/// istemeyene hız. Yalnızca çeviri tamamlandıktan sonra görünür.
struct TranslationPopupDetailToggle: View {
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))

                Text(isExpanded ? "Detayı gizle" : "Detay")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(DSColor.brand)
            .frame(maxWidth: .infinity)
            .frame(height: TranslationPopupLayout.detailToggleHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Çeviri detayını gizle" : "Çeviri detayını göster")
    }
}

// MARK: - Detail Panel

/// Genişleyen derinlik katmanı: tam bağlam çevirisi, alternatif anlamlar ve
/// "Sohbete taşı" CTA'sı.
struct TranslationPopupDetailPanel: View {
    let phase: TranslationDetailPhase
    let onRetry: () -> Void
    let onAskAI: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, DSSpacing.sm)

            switch phase {
            case .idle, .loading:
                loadingRow
            case .loaded(let detail):
                detailContent(detail)
            case .failed:
                failedRow
            }
        }
    }

    // MARK: - Loading

    private var loadingRow: some View {
        VStack(spacing: DSSpacing.xs) {
            TranslationWaveIndicator()

            Text("Ayrıntılar getiriliyor...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.md)
    }

    // MARK: - Loaded

    private func detailContent(_ detail: DetailedTranslationResult) -> some View {
        VStack(spacing: DSSpacing.sm) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    sectionLabel("Bağlam çevirisi")

                    Text(detail.contextualTranslation)
                        .font(DSFont.translation)
                        .foregroundStyle(.primary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !detail.alternatives.isEmpty {
                        sectionLabel("Alternatif anlamlar")
                        alternativeChips(detail.alternatives)
                    }
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.xs)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 132)

            if let onAskAI {
                askAIButton(onAskAI)
            }
        }
        .padding(.bottom, DSSpacing.sm)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(DSFont.meta.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func alternativeChips(_ alternatives: [String]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: DSSpacing.xs)],
            alignment: .leading,
            spacing: DSSpacing.xs
        ) {
            ForEach(alternatives, id: \.self) { alternative in
                Text(alternative)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, DSSpacing.xxs + 2)
                    .frame(maxWidth: .infinity)
                    .background(Capsule().fill(DSColor.brand.opacity(0.12)))
                    .foregroundStyle(DSColor.brand)
            }
        }
    }

    private func askAIButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "message.fill")
                    .font(.caption.weight(.semibold))

                Text("Sohbete taşı")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.xs + 2)
            .background(Capsule().fill(DSColor.brandGradient))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DSSpacing.md)
        .accessibilityLabel("Seçimi sohbete taşı")
    }

    // MARK: - Failed

    private var failedRow: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(DSColor.warning)

            Text("Detay alınamadı")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Tekrar Dene", action: onRetry)
                .font(.caption.weight(.medium))
                .foregroundStyle(DSColor.brand)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
    }
}

// MARK: - Preview

#Preview("Loaded") {
    TranslationPopupDetailPanel(
        phase: .loaded(DetailedTranslationResult(
            contextualTranslation: "Yapay zekanın dermatolojiye entegrasyonu, tanı doğruluğunu ve"
                + " tedavi planlamasını geliştirmek için umut verici bir sınır sunuyor.",
            alternatives: ["bütünleşme", "entegrasyon", "birleştirme"]
        )),
        onRetry: {},
        onAskAI: {}
    )
    .frame(width: 340)
    .translationPopupSurface()
    .padding()
}

#Preview("Loading") {
    TranslationPopupDetailPanel(phase: .loading, onRetry: {}, onAskAI: {})
        .frame(width: 340)
        .translationPopupSurface()
        .padding()
}
