import SwiftUI

// MARK: - Reader Rendering Overlay
/// PDF render tamamlanana kadar gösterilen katman: disk cache'de ilk sayfa
/// görseli varsa onu (instant feedback), yoksa spinner gösterir.
struct ReaderRenderingOverlay: View {
    let cachedFirstPageImage: UIImage?

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            // Eğer disk cache'de ilk sayfa varsa, onu göster (instant feedback)
            if let cachedImage = cachedFirstPageImage {
                GeometryReader { geometry in
                    Image(uiImage: cachedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .background(Color.white)
                        .overlay(alignment: .bottom) {
                            // Subtle loading indicator at bottom
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Yükleniyor...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 20)
                        }
                }
            } else {
                // Cache'de yoksa normal spinner göster
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Sayfa hazırlanıyor...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
