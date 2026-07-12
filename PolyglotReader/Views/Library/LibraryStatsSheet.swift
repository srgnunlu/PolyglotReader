import SwiftUI
import Combine

// MARK: - Stats Button
/// Filtre çubuğundaki istatistik pill'i; sheet'ini kendi içinde yönetir.
struct LibraryStatsButton: View {
    @ObservedObject var viewModel: LibraryViewModel
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Image(systemName: "chart.bar.xaxis")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(Color(.tertiarySystemBackground))
                }
        }
        .buttonStyle(DSPressableButtonStyle())
        .foregroundStyle(Color.secondary)
        .accessibilityLabel("library.stats.accessibility".localized)
        .sheet(isPresented: $showSheet) {
            LibraryStatsSheet(stats: viewModel.libraryStats)
        }
    }
}

// MARK: - Stats Sheet
/// Kütüphane özeti: dosya/sayfa toplamları, okuma durumu, haftalık aktivite.
/// Tüm değerler istemcide hesaplanır (LibraryViewModel.libraryStats).
struct LibraryStatsSheet: View {
    let stats: LibraryViewModel.LibraryStats
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("library.title".localized) {
                    statRow("doc.text.fill", .indigo, "library.stats.total_files".localized, "\(stats.totalFiles)")
                    statRow("internaldrive.fill", .gray, "library.stats.total_size".localized, stats.formattedTotalSize)
                    if stats.totalPages > 0 {
                        statRow("book.pages.fill", .brown, "library.stats.total_pages".localized, "\(stats.totalPages)")
                    }
                    statRow("tag.fill", .green, "library.stats.tag_count".localized, "\(stats.tagCount)")
                    statRow("star.fill", .yellow, "library.favorite".localized, "\(stats.favoriteCount)")
                }

                Section("library.stats.reading".localized) {
                    if stats.pagesRead > 0 {
                        statRow("eye.fill", .blue, "library.stats.pages_read".localized, "\(stats.pagesRead)")
                    }
                    statRow(
                        "checkmark.circle.fill", .green,
                        "library.stats.completed".localized, "\(stats.completedCount)"
                    )
                    statRow(
                        "bookmark.circle.fill", .orange,
                        "library.stats.in_progress".localized, "\(stats.inProgressCount)"
                    )
                    statRow("calendar", .red, "library.stats.opened_this_week".localized, "\(stats.openedThisWeek)")
                }

                if !stats.recentlyRead.isEmpty {
                    Section("library.stats.recently_read".localized) {
                        ForEach(stats.recentlyRead) { file in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(file.name)
                                    .font(.subheadline)
                                    .lineLimit(1)

                                if let progress = file.readingProgress {
                                    HStack(spacing: 8) {
                                        ProgressView(value: progress)
                                            .tint(DSColor.brand)

                                        Text("library.progress.percent".localized(with: Int(progress * 100)))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("library.stats.title".localized)
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

    private func statRow(_ icon: String, _ color: Color, _ title: String, _ value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 26)

            Text(title)

            Spacer()

            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
