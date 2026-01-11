import SwiftUI

// MARK: - PDF Card View (Grid)
struct PDFCardView: View {
    let file: PDFDocumentMetadata
    let onTap: () -> Void
    let onDelete: () -> Void
    var onMoveToFolder: ((Folder?) -> Void)?
    var availableFolders: [Folder] = []

    @State private var showDeleteConfirmation = false
    @State private var isPressed = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Thumbnail Area
                thumbnailView
                    .frame(height: 130)
                    .clipped()

                // Info Area
                infoArea
            }
            .background {
                LiquidGlassBackground(
                    cornerRadius: 20,
                    intensity: .medium,
                    accentColor: .indigo
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PDFCardButtonStyle())
        .contextMenu {
            if let onMoveToFolder = onMoveToFolder, !availableFolders.isEmpty {
                Menu {
                    Button {
                        onMoveToFolder(nil)
                    } label: {
                        Label("Ana Klasör", systemImage: "house")
                    }

                    ForEach(availableFolders) { folder in
                        Button {
                            onMoveToFolder(folder)
                        } label: {
                            Label(folder.name, systemImage: folder.sfSymbol)
                        }
                    }
                } label: {
                    Label("Klasöre Taşı", systemImage: "folder")
                }

                Divider()
            }

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Sil", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Bu dosyayı silmek istediğinizden emin misiniz?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive, action: onDelete)
            Button("İptal", role: .cancel) {}
        }
    }

    // MARK: - Thumbnail View
    private var thumbnailView: some View {
        ZStack(alignment: .top) {
            // PDF Thumbnail veya placeholder
            if let thumbnailData = file.thumbnailData,
               let uiImage = UIImage(data: thumbnailData) {
                // Sayfanın üst kısmını göster (başlık görünsün)
                GeometryReader { geo in
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width)
                        .frame(height: geo.size.height, alignment: .top)
                }
            } else {
                // Gradient arka plan
                LinearGradient(
                    colors: [
                        Color.indigo.opacity(0.08),
                        Color.purple.opacity(0.05),
                        Color.indigo.opacity(0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // PDF Icon
                VStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.indigo.opacity(0.7), .purple.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text("PDF")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.indigo.opacity(0.5))
                }
            }

            // Üst gradient overlay (okunabilirlik için)
            VStack {
                LinearGradient(
                    colors: [.black.opacity(0.15), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 30)

                Spacer()
            }

            // Alt gradient overlay
            VStack {
                Spacer()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.2)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
            }
        }
    }

    // MARK: - Info Area
    private var infoArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(file.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                Text(file.formattedDate)

                Spacer()

                Text(file.formattedSize)
                    .fontWeight(.medium)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Etiketler
            if !file.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(file.tags.prefix(3)) { tag in
                            HStack(spacing: 2) {
                                Circle()
                                    .fill(Color(hex: tag.color) ?? .green)
                                    .frame(width: 4, height: 4)
                                Text(tag.name)
                            }
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background((Color(hex: tag.color) ?? .green).opacity(0.15))
                            .foregroundStyle(Color(hex: tag.color) ?? .green)
                            .clipShape(Capsule())
                        }

                        if file.tags.count > 3 {
                            Text("+\(file.tags.count - 3)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - PDF Card Button Style
struct PDFCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - PDF List Row View
struct PDFListRowView: View {
    let file: PDFDocumentMetadata
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Thumbnail
                listThumbnail

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text(file.formattedSize)
                            .fontWeight(.medium)

                        Circle()
                            .fill(.secondary)
                            .frame(width: 3, height: 3)

                        Text(file.formattedDate)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background {
                LiquidGlassBackground(
                    cornerRadius: 16,
                    intensity: .light,
                    accentColor: .indigo
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PDFCardButtonStyle())
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Sil", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Bu dosyayı silmek istediğinizden emin misiniz?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive, action: onDelete)
            Button("İptal", role: .cancel) {}
        }
    }

    // MARK: - List Thumbnail
    private var listThumbnail: some View {
        ZStack(alignment: .top) {
            if let thumbnailData = file.thumbnailData,
               let uiImage = UIImage(data: thumbnailData) {
                GeometryReader { geo in
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width)
                        .frame(height: geo.size.height, alignment: .top)
                }
            } else {
                LinearGradient(
                    colors: [.indigo.opacity(0.1), .purple.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image(systemName: "doc.text.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.indigo.opacity(0.6))
            }
        }
        .frame(width: 50, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white.opacity(0.3), lineWidth: 0.5)
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

        VStack(spacing: 24) {
            // Grid Card
            HStack(spacing: 16) {
                PDFCardView(
                    file: PDFDocumentMetadata(
                        id: "1",
                        name: "Örnek Doküman.pdf",
                        size: 2456789,
                        uploadedAt: Date(),
                        storagePath: "/path"
                    ),
                    onTap: {},
                    onDelete: {}
                )
                .frame(width: 170)

                PDFCardView(
                    file: PDFDocumentMetadata(
                        id: "2",
                        name: "Uzun İsimli PDF.pdf",
                        size: 1234567,
                        uploadedAt: Date(),
                        storagePath: "/path"
                    ),
                    onTap: {},
                    onDelete: {}
                )
                .frame(width: 170)
            }

            // List Row
            PDFListRowView(
                file: PDFDocumentMetadata(
                    id: "3",
                    name: "Çok Uzun İsimli Bir Doküman Örneği.pdf",
                    size: 1234567,
                    uploadedAt: Date(),
                    storagePath: "/path"
                ),
                onTap: {},
                onDelete: {}
            )
            .padding(.horizontal)
        }
        .padding()
    }
}
