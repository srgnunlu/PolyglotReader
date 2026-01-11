import SwiftUI

// MARK: - Image Share Sheet
struct ImageShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Fullscreen Image View
struct FullscreenImageView: View {
    let image: UIImage
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = lastScale * value
                        }
                        .onEnded { _ in
                            lastScale = scale
                            // Minimum ve maksimum zoom sınırları
                            if scale < 1 {
                                withAnimation(.spring()) {
                                    scale = 1
                                    lastScale = 1
                                }
                            } else if scale > 5 {
                                withAnimation(.spring()) {
                                    scale = 5
                                    lastScale = 5
                                }
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring()) {
                        if scale > 1 {
                            scale = 1
                            lastScale = 1
                        } else {
                            scale = 2
                            lastScale = 2
                        }
                    }
                }

            VStack {
                HStack {
                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.white.opacity(0.8))
                            .shadow(color: .black.opacity(0.3), radius: 4)
                    }
                    .padding()
                }

                Spacer()
            }
        }
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()

        ImageSelectionPopup(
            imageInfo: PDFImageInfo(
                image: UIImage(systemName: "photo") ?? UIImage(),
                rect: .zero,
                screenRect: CGRect(x: 100, y: 200, width: 200, height: 200),
                pageNumber: 1
            ),
            onDismiss: {},
            onAskAI: {}
        )
    }
}
