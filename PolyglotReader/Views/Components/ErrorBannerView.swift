import SwiftUI

struct ErrorBannerView: View {
    let banner: ErrorHandlingService.ErrorBanner
    let onDismiss: () -> Void

    private var accentColor: Color {
        banner.isCritical ? DSColor.danger : DSColor.warning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: banner.isCritical ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(accentColor)

                Text(banner.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(NSLocalizedString("error.action.dismiss", comment: "")))
            }

            Text(banner.message)
                .font(.subheadline)
                .foregroundStyle(.primary)

            if let suggestion = banner.suggestion, !suggestion.isEmpty {
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                if let retryAction = banner.retryAction {
                    Button(NSLocalizedString("error.action.retry", comment: "")) {
                        retryAction()
                        onDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
                }

                if let helpAction = banner.helpAction {
                    Button(NSLocalizedString("error.action.help", comment: "")) {
                        helpAction()
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                }
            }
        }
        .padding(14)
        .dsGlass(.banner, shape: .rounded(DSRadius.medium), tint: accentColor)
        .dsShadow(.card, tint: accentColor)
        .padding(.horizontal, DSSpacing.md)
        .padding(.top, 10)
        // Banner'lar kullanıcı-tetikli işlemlerin sonucudur; belirme anında
        // tek bir hata haptic'i.
        .onAppear { DSHaptics.error() }
    }
}

#Preview {
    ErrorBannerView(
        banner: ErrorHandlingService.ErrorBanner(
            id: UUID(),
            title: "Hata",
            message: "Örnek hata mesajı",
            suggestion: "Lütfen tekrar deneyin.",
            retryAction: {},
            helpAction: {},
            isCritical: false
        )
    ) {}
}
