import SwiftUI

struct DebugLogsView: View {
    @ObservedObject private var loggingService = LoggingService.shared
    @State private var selectedLevel: LogLevel?
    @State private var searchText = ""
    @State private var showShareSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var filteredLogs: [LogEntry] {
        loggingService.filteredLogs(level: selectedLevel, source: searchText)
            .reversed() // En yeni loglar üstte
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Stats Bar
                HStack(spacing: 20) {
                    StatBadge(count: loggingService.logs.count, label: "debug.logs.total".localized, color: .gray)
                    StatBadge(count: loggingService.errorCount, label: "debug.logs.errors".localized, color: .red)
                    StatBadge(count: loggingService.warningCount, label: "debug.logs.warnings".localized, color: .orange)
                }
                .padding()
                .background(Color(.secondarySystemBackground))

                // Filters
                VStack(spacing: 12) {
                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        TextField("debug.logs.search_source".localized, text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(10)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(10)
                    .accessibilityIdentifier("log_search_field")

                    // Level Filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(label: "debug.logs.all".localized, isSelected: selectedLevel == nil) {
                                selectedLevel = nil
                            }

                            ForEach(LogLevel.allCases, id: \.self) { level in
                                FilterChip(
                                    label: "\(level.emoji) \(level.rawValue)",
                                    isSelected: selectedLevel == level
                                ) {
                                    selectedLevel = level
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // Log List
                if filteredLogs.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 50))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("debug.logs.empty".localized)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredLogs) { entry in
                                LogEntryRow(entry: entry)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("debug.logs.title".localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showShareSheet = true
                        } label: {
                            Label("debug.logs.export".localized, systemImage: "square.and.arrow.up")
                        }

                        Button(role: .destructive) {
                            loggingService.clearLogs()
                        } label: {
                            Label("debug.logs.clear".localized, systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("debug.logs.filter".localized)
                    .accessibilityIdentifier("logs_menu_button")
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = loggingService.getLogFileURL() {
                    ShareSheet(items: [url])
                } else {
                    ShareSheet(items: [loggingService.exportLogsAsText()])
                }
            }
        }
    }
}

// MARK: - Log Entry Row
struct LogEntryRow: View {
    let entry: LogEntry
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var backgroundColor: Color {
        switch entry.level {
        case .error: return .red.opacity(0.1)
        case .critical: return .red.opacity(0.2)
        case .warning: return .orange.opacity(0.1)
        default: return Color(.tertiarySystemBackground)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.level.emoji)
                    .font(.caption)
                    .accessibilityHidden(true)

                Text(entry.formattedTimestamp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Text(entry.source)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.indigo)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.indigo.opacity(0.1))
                    .cornerRadius(4)

                Spacer()

                if entry.details != nil {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }

            Text(entry.message)
                .font(.subheadline)
                .lineLimit(isExpanded ? nil : 2)

            if isExpanded, let details = entry.details {
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemBackground))
                    .cornerRadius(6)
            }
        }
        .padding(12)
        .background(backgroundColor)
        .cornerRadius(12)
        .contentShape(Rectangle())
        .onTapGesture {
            if entry.details != nil {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.level.rawValue): \(entry.source), \(entry.message)")
        .accessibilityHint(entry.details != nil ? "accessibility.double_tap".localized : "")
        .accessibilityValue(isExpanded ? "accessibility.expanded".localized : "")
    }
}

// MARK: - Stat Badge
struct StatBadge: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) \(label)")
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minHeight: 44)
                .background(isSelected ? Color.indigo : Color(.tertiarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    DebugLogsView()
}
