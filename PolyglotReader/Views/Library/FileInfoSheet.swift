import SwiftUI

// MARK: - File Info Sheet
/// Context menüdeki "Bilgi" — dosyanın eldeki tüm meta verisini gösterir;
/// ek sorgu atmaz.
struct FileInfoSheet: View {
    let file: PDFDocumentMetadata
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            if let uiImage = ThumbnailImageProvider.image(for: file.id, data: file.thumbnailData) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Color(.secondarySystemBackground)
                                Image(systemName: "doc.text.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 56, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .lineLimit(3)

                            if file.isFavorite {
                                Label("library.favorite".localized, systemImage: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("file_info.section.general".localized) {
                    LabeledContent("file_info.size".localized, value: file.formattedSize)
                    if let pageCount = file.pageCount {
                        LabeledContent("file_info.page_count".localized, value: "\(pageCount)")
                    }
                    if let category = file.aiCategory, !category.isEmpty {
                        LabeledContent("file_info.ai_category".localized, value: category)
                    }
                }

                Section("file_info.section.dates".localized) {
                    LabeledContent("file_info.added".localized, value: file.formattedDate)
                    if let lastOpened = file.lastOpenedAt {
                        LabeledContent("file_info.last_opened".localized) {
                            Text(lastOpened, format: .relative(presentation: .named))
                        }
                    }
                }

                if let progress = file.readingProgress {
                    Section("file_info.section.reading".localized) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let page = file.lastReadPage, let total = file.pageCount {
                                Text(
                                    "file_info.page_progress".localized(
                                        with: page, total, Int(progress * 100)
                                    )
                                )
                                .font(.subheadline)
                            }
                            ProgressView(value: progress)
                                .tint(progress >= 0.999 ? .green : DSColor.brand)
                        }
                        .padding(.vertical, 2)
                    }
                }

                if !file.tags.isEmpty {
                    Section("library.tags".localized) {
                        FlowTagList(tags: file.tags)
                    }
                }

                if let summary = file.summary, !summary.isEmpty {
                    Section("file_info.section.summary".localized) {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("file_info.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done".localized) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Flow Tag List
/// Bilgi sheet'inde etiket kapsülleri (tek satır, yatay kaydırmalı).
private struct FlowTagList: View {
    let tags: [Tag]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags) { tag in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: tag.color) ?? .green)
                            .frame(width: 6, height: 6)
                        Text(tag.name)
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((Color(hex: tag.color) ?? .green).opacity(0.15))
                    .foregroundStyle(Color(hex: tag.color) ?? .green)
                    .clipShape(Capsule())
                }
            }
        }
    }
}
