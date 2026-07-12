import SwiftUI
import Combine

// MARK: - Continue Reading Strip
/// Ana klasörün üstünde "Kaldığın yerden devam" şeridi: son açılan, henüz
/// bitmemiş dosyalar yatay kaydırmalı mini kartlarla listelenir.
struct ContinueReadingStrip: View {
    let files: [PDFDocumentMetadata]
    var onOpen: (PDFDocumentMetadata) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "book.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSColor.brand)

                Text("library.continue_reading".localized)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(files) { file in
                        ContinueReadingCard(file: file) {
                            onOpen(file)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Continue Reading Card
private struct ContinueReadingCard: View {
    let file: PDFDocumentMetadata
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Mini thumbnail
                ZStack {
                    if let uiImage = ThumbnailImageProvider.image(for: file.id, data: file.thumbnailData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        LinearGradient(
                            colors: [.indigo.opacity(0.1), .purple.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: "doc.text.fill")
                            .font(.caption)
                            .foregroundStyle(.indigo.opacity(0.6))
                    }
                }
                .frame(width: 34, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    if let page = file.lastReadPage, let total = file.pageCount, total > 0 {
                        Text("library.page_of".localized(with: page, total))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    if let progress = file.readingProgress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(DSColor.brand)
                            .frame(width: 110)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: 210, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DSColor.brand.opacity(0.15), lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(DSPressableButtonStyle())
        .accessibilityLabel(
            "library.continue_reading.accessibility".localized(with: file.name)
        )
    }
}
