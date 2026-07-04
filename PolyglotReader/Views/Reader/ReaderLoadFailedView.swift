import SwiftUI

// MARK: - Reader Load Failed View
/// Doküman indirilemediğinde gösterilen hata durumu (yeniden dene + kapat).
struct ReaderLoadFailedView: View {
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundStyle(.red)

            Text("PDF Yüklenemedi")
                .font(.title2)
                .fontWeight(.bold)

            Text("Lütfen tekrar deneyin")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                onRetry()
            } label: {
                Text("Yeniden Dene")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.indigo)
                    .foregroundStyle(.white)
                    .cornerRadius(12)
            }

            Button("Kapat") {
                onClose()
            }
            .foregroundStyle(.secondary)
        }
    }
}
