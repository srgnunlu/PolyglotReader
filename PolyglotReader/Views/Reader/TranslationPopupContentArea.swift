import SwiftUI

// MARK: - Phase

/// QuickTranslationPopup içerik durumu
enum TranslationPopupPhase: Equatable {
    case loading
    case translated(String)
    case failed
}

// MARK: - Content Area

/// Popup içerik alanı: yükleniyor / çeviri sonucu / hata
struct TranslationPopupContentArea: View {
    let phase: TranslationPopupPhase
    let maxHeight: CGFloat

    var body: some View {
        ZStack {
            switch phase {
            case .loading:
                loadingView
                    .transition(.opacity)
            case .translated(let text):
                translatedContentView(text)
                    .transition(.opacity)
            case .failed:
                errorView
                    .transition(.opacity)
            }
        }
        .frame(maxHeight: maxHeight)
        .dsAnimation(DSMotion.smooth, value: phase)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: DSSpacing.sm) {
            TranslationWaveIndicator()

            Text("translation.loading".localized)
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
                .font(DSFont.translation)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)
                .contentTransition(.opacity)
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.visible)
    }

    // MARK: - Error View

    private var errorView: some View {
        VStack(spacing: DSSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(DSColor.warning)

            Text("translation.failed".localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Translation Wave Indicator

/// Markalı bekleme anı: spinner yerine soldan sağa süpüren gradyan ışık
/// çizgisi — "çeviri dalgası". Reduce Motion açıkken statik çizgiye düşer.
struct TranslationWaveIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let trackWidth: CGFloat = 96
    private let trackHeight: CGFloat = 4
    private let sweepWidth: CGFloat = 40

    var body: some View {
        Capsule()
            .fill(DSColor.brand.opacity(0.18))
            .overlay(alignment: .leading) {
                if reduceMotion {
                    Capsule()
                        .fill(DSColor.brandGradient)
                        .opacity(0.8)
                } else {
                    Capsule()
                        .fill(DSColor.brandGradient)
                        .frame(width: sweepWidth)
                        .phaseAnimator([false, true]) { sweep, phase in
                            sweep.offset(x: phase ? trackWidth - sweepWidth : 0)
                        } animation: { _ in
                            .easeInOut(duration: 0.7)
                        }
                }
            }
            .frame(width: trackWidth, height: trackHeight)
            .clipShape(Capsule())
            .accessibilityHidden(true)
    }
}
