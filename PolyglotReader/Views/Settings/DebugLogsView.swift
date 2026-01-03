import SwiftUI

struct DebugLogsView: View {
    @ObservedObject private var loggingService = LoggingService.shared
    @State private var selectedLevel: LogLevel?
    @State private var searchText = ""
    @State private var showShareSheet = false
    
    var filteredLogs: [LogEntry] {
        loggingService.filteredLogs(level: selectedLevel, source: searchText)
            .reversed() // En yeni loglar üstte
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Stats Bar
                HStack(spacing: 20) {
                    StatBadge(count: loggingService.logs.count, label: "Toplam", color: .gray)
                    StatBadge(count: loggingService.errorCount, label: "Hata", color: .red)
                    StatBadge(count: loggingService.warningCount, label: "Uyarı", color: .orange)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                
                // Filters
                VStack(spacing: 12) {
                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Kaynak ara...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(10)
                    .background(Color(.tertiarySystemBackground))
                    .cornerRadius(10)
                    
                    // Level Filter
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(label: "Tümü", isSelected: selectedLevel == nil) {
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
                        Text("Log bulunamadı")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
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
            .navigationTitle("Debug Logları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showShareSheet = true
                        } label: {
                            Label("Logları Paylaş", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(role: .destructive) {
                            loggingService.clearLogs()
                        } label: {
                            Label("Logları Temizle", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
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
    
    var backgroundColor: Color {
        switch entry.level {
        case .error: return .red.opacity(0.1)
        case .warning: return .orange.opacity(0.1)
        default: return Color(.tertiarySystemBackground)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.level.emoji)
                    .font(.caption)
                
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
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            }
        }
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
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
                .background(isSelected ? Color.indigo : Color(.tertiarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
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
