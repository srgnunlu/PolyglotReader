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
        Group {
            switch phase {
            case .loading:
                loadingView
            case .translated(let text):
                translatedContentView(text)
            case .failed:
                errorView
            }
        }
        .frame(maxHeight: maxHeight)
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
}
