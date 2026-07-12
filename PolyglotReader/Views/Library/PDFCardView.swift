import SwiftUI

// MARK: - PDF Card View (Grid)
struct PDFCardView: View {
    let file: PDFDocumentMetadata
    let onTap: () -> Void
    let onDelete: () -> Void
    var onMoveToFolder: ((Folder?) -> Void)?
    var onRename: (() -> Void)?
    var onShare: (() -> Void)?
    var onToggleFavorite: (() -> Void)?
    var availableFolders: [Folder] = []
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var isThumbnailLoading: Bool = false

    @State private var showDeleteConfirmation = false
    @State private var isPressed = false
    @State private var showInfoSheet = false

    var body: some View {
        if isSelectionMode {
            // No context menu / delete dialog while selecting — tap toggles selection.
            cardButton
        } else {
            cardButton
                // Karttan klasör kartına sürükle-bırak taşıma
                .draggable(file.id)
                .contextMenu {
                    Button {
                        showInfoSheet = true
                    } label: {
                        Label("file_info.action".localized, systemImage: "info.circle")
                    }

                    if let onToggleFavorite = onToggleFavorite {
                        Button(action: onToggleFavorite) {
                            Label(
                                file.isFavorite
                                    ? "library.favorite.remove".localized
                                    : "library.favorite.add".localized,
                                systemImage: file.isFavorite ? "star.slash" : "star"
                            )
                        }
                    }

                    if let onRename = onRename {
                        Button(action: onRename) {
                            Label("library.action.rename".localized, systemImage: "pencil")
                        }
                    }

                    if let onShare = onShare {
                        Button(action: onShare) {
                            Label("common.share".localized, systemImage: "square.and.arrow.up")
                        }
                    }

                    if let onMoveToFolder = onMoveToFolder, !availableFolders.isEmpty {
                        Menu {
                            Button {
                                onMoveToFolder(nil)
                            } label: {
                                Label("library.root_folder".localized, systemImage: "house")
                            }

                            ForEach(availableFolders) { folder in
                                Button {
                                    onMoveToFolder(folder)
                                } label: {
                                    Label(folder.name, systemImage: folder.sfSymbol)
                                }
                            }
                        } label: {
                            Label("pdf_card.move_to_folder".localized, systemImage: "folder")
                        }

                        Divider()
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("common.delete".localized, systemImage: "trash")
                    }
                }
                .confirmationDialog(
                    "library.delete.confirm".localized,
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("common.delete".localized, role: .destructive, action: onDelete)
                    Button("common.cancel".localized, role: .cancel) {}
                }
                .sheet(isPresented: $showInfoSheet) {
                    FileInfoSheet(file: file)
                }
        }
    }

    private var cardButton: some View {
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
            .overlay {
                if isSelectionMode {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? Color.indigo : Color.clear, lineWidth: 2.5)
                }
            }
            .overlay(alignment: .topLeading) {
                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? Color.indigo : Color.white.opacity(0.9))
                        .background(Circle().fill(.ultraThinMaterial))
                        .padding(8)
                        .accessibilityHidden(true)
                } else if file.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.yellow)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.ultraThinMaterial))
                        .padding(8)
                        .accessibilityLabel("library.favorite".localized)
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(DSPressableButtonStyle())
        .accessibilityAddTraits(isSelectionMode && isSelected ? [.isSelected] : [])
    }

    // MARK: - Thumbnail View
    private var thumbnailView: some View {
        ZStack(alignment: .top) {
            // PDF Thumbnail veya placeholder
            if let uiImage = ThumbnailImageProvider.image(for: file.id, data: file.thumbnailData) {
                // Sayfanın üst kısmını göster (başlık görünsün)
                GeometryReader { geo in
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width)
                        .frame(height: geo.size.height, alignment: .top)
                }
                .transition(.opacity)
            } else if isThumbnailLoading {
                SkeletonBlock()
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
                        .symbolRenderingMode(.hierarchical)
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

            // Okuma ilerlemesi (sayfa sayısı biliniyorsa)
            if let progress = file.readingProgress {
                HStack(spacing: 6) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(progress >= 0.999 ? .green : .indigo)

                    Text("library.progress.percent".localized(with: Int(progress * 100)))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("library.accessibility.reading_progress".localized(with: Int(progress * 100)))
            }

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
                            Text("library.tags.more".localized(with: file.tags.count - 3))
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

// MARK: - PDF List Row View
struct PDFListRowView: View {
    let file: PDFDocumentMetadata
    let onTap: () -> Void
    let onDelete: () -> Void
    var onMoveToFolder: ((Folder?) -> Void)?
    var onRename: (() -> Void)?
    var onShare: (() -> Void)?
    var onToggleFavorite: (() -> Void)?
    var availableFolders: [Folder] = []
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var isThumbnailLoading: Bool = false

    @State private var showDeleteConfirmation = false
    @State private var showInfoSheet = false

    var body: some View {
        if isSelectionMode {
            rowButton
        } else {
            rowButton
                .draggable(file.id)
                .contextMenu {
                    Button {
                        showInfoSheet = true
                    } label: {
                        Label("file_info.action".localized, systemImage: "info.circle")
                    }

                    if let onToggleFavorite = onToggleFavorite {
                        Button(action: onToggleFavorite) {
                            Label(
                                file.isFavorite
                                    ? "library.favorite.remove".localized
                                    : "library.favorite.add".localized,
                                systemImage: file.isFavorite ? "star.slash" : "star"
                            )
                        }
                    }

                    if let onRename = onRename {
                        Button(action: onRename) {
                            Label("library.action.rename".localized, systemImage: "pencil")
                        }
                    }

                    if let onShare = onShare {
                        Button(action: onShare) {
                            Label("common.share".localized, systemImage: "square.and.arrow.up")
                        }
                    }

                    if let onMoveToFolder = onMoveToFolder, !availableFolders.isEmpty {
                        Menu {
                            Button {
                                onMoveToFolder(nil)
                            } label: {
                                Label("library.root_folder".localized, systemImage: "house")
                            }

                            ForEach(availableFolders) { folder in
                                Button {
                                    onMoveToFolder(folder)
                                } label: {
                                    Label(folder.name, systemImage: folder.sfSymbol)
                                }
                            }
                        } label: {
                            Label("pdf_card.move_to_folder".localized, systemImage: "folder")
                        }

                        Divider()
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("common.delete".localized, systemImage: "trash")
                    }
                }
                .confirmationDialog(
                    "library.delete.confirm".localized,
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("common.delete".localized, role: .destructive, action: onDelete)
                    Button("common.cancel".localized, role: .cancel) {}
                }
                .sheet(isPresented: $showInfoSheet) {
                    FileInfoSheet(file: file)
                }
        }
    }

    private var rowButton: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                if isSelectionMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(isSelected ? Color.indigo : Color.secondary)
                        .accessibilityHidden(true)
                }

                // Thumbnail
                listThumbnail

                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        if file.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                                .accessibilityLabel("library.favorite".localized)
                        }

                        Text(file.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }

                    HStack(spacing: 6) {
                        Text(file.formattedSize)
                            .fontWeight(.medium)

                        Circle()
                            .fill(.secondary)
                            .frame(width: 3, height: 3)

                        Text(file.formattedDate)

                        if let progress = file.readingProgress {
                            Circle()
                                .fill(.secondary)
                                .frame(width: 3, height: 3)

                            Text("library.progress.percent".localized(with: Int(progress * 100)))
                                .fontWeight(.medium)
                                .foregroundStyle(progress >= 0.999 ? .green : .indigo)
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let progress = file.readingProgress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(progress >= 0.999 ? .green : .indigo)
                            .accessibilityLabel("library.accessibility.reading_progress".localized(with: Int(progress * 100)))
                    }

                    // Etiketler — grid kartıyla bilgi eşitliği (satırda kompakt: 2 + sayaç)
                    if !file.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(file.tags.prefix(2)) { tag in
                                HStack(spacing: 2) {
                                    Circle()
                                        .fill(Color(hex: tag.color) ?? .green)
                                        .frame(width: 4, height: 4)
                                    Text(tag.name)
                                        .lineLimit(1)
                                }
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((Color(hex: tag.color) ?? .green).opacity(0.15))
                                .foregroundStyle(Color(hex: tag.color) ?? .green)
                                .clipShape(Capsule())
                            }

                            if file.tags.count > 2 {
                                Text("library.tags.more".localized(with: file.tags.count - 2))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
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
            .overlay {
                if isSelectionMode && isSelected {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.indigo, lineWidth: 2)
                }
            }
        }
        .buttonStyle(DSPressableButtonStyle())
        .accessibilityAddTraits(isSelectionMode && isSelected ? [.isSelected] : [])
    }

    // MARK: - List Thumbnail
    private var listThumbnail: some View {
        ZStack(alignment: .top) {
            if let uiImage = ThumbnailImageProvider.image(for: file.id, data: file.thumbnailData) {
                GeometryReader { geo in
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width)
                        .frame(height: geo.size.height, alignment: .top)
                }
                .transition(.opacity)
            } else if isThumbnailLoading {
                SkeletonBlock()
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
