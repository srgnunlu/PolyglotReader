import SwiftUI

// MARK: - Memory Debug View
/// Debug view for memory monitoring in Settings.
/// Only available in DEBUG builds.
#if DEBUG
struct MemoryDebugView: View {
    @State private var stats: MemoryDebugger.MemoryStats?
    @State private var cacheStats: CacheStats?
    @State private var refreshTrigger = false

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        List {
            // MARK: - Overview Section
            Section {
                HStack {
                    Label("Aktif ViewModel'ler", systemImage: "rectangle.stack")
                    Spacer()
                    Text("\(stats?.totalInstances ?? 0)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("Bellek Uyarıları", systemImage: "exclamationmark.triangle")
                    Spacer()
                    Text("\(stats?.memoryWarnings ?? 0)")
                        .foregroundColor(stats?.memoryWarnings ?? 0 > 0 ? .orange : .secondary)
                }
            } header: {
                Text("Genel Bakış")
            }

            // MARK: - Active Instances Section
            if let instancesByType = stats?.instancesByType, !instancesByType.isEmpty {
                Section {
                    ForEach(instancesByType.sorted(by: { $0.key < $1.key }), id: \.key) { name, count in
                        HStack {
                            Text(name.replacingOccurrences(of: "ViewModel", with: "VM"))
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Text("\(count)")
                                .foregroundColor(count > 1 ? .orange : .green)
                                .fontWeight(count > 1 ? .bold : .regular)
                        }
                    }
                } header: {
                    Text("Aktif Örnekler")
                } footer: {
                    if let leaks = stats?.instancesByType.filter({ $0.value > 1 }), !leaks.isEmpty {
                        Text("⚠️ Birden fazla örnek potansiyel sızıntı olabilir")
                            .foregroundColor(.orange)
                    }
                }
            }

            // MARK: - Recent Deinits Section
            if let recentDeinits = stats?.recentDeinits, !recentDeinits.isEmpty {
                Section {
                    ForEach(recentDeinits.reversed(), id: \.timestamp) { item in
                        HStack {
                            Text(dateFormatter.string(from: item.timestamp))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(item.name.replacingOccurrences(of: "ViewModel", with: "VM"))
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                } header: {
                    Text("Son Temizlenenler")
                }
            }

            // MARK: - Cache Section
            if let cache = cacheStats {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Thumbnail: \(cache.thumbnailCountLimit) öğe, \(cache.thumbnailCostLimit / 1024 / 1024)MB")
                        Text("PDF Sayfa: \(cache.pdfPageCountLimit) öğe, \(cache.pdfPageCostLimit / 1024 / 1024)MB")
                        Text("Görsel: \(cache.imageCountLimit) öğe, \(cache.imageCostLimit / 1024 / 1024)MB")
                    }
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                } header: {
                    Text("Cache Limitleri")
                }
            }

            // MARK: - Actions Section
            Section {
                Button {
                    CacheService.shared.clearAllCaches()
                    refreshStats()
                } label: {
                    Label("Tüm Cache'i Temizle", systemImage: "trash")
                }

                Button {
                    simulateMemoryWarning()
                } label: {
                    Label("Bellek Uyarısı Simüle Et", systemImage: "exclamationmark.triangle")
                }
                .foregroundColor(.orange)
            } header: {
                Text("Eylemler")
            }
        }
        .navigationTitle("Bellek Debug")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    refreshStats()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear {
            refreshStats()
        }
    }

    private func refreshStats() {
        Task { @MainActor in
            stats = MemoryDebugger.shared.getStats()
            cacheStats = CacheService.shared.getStats()
        }
    }

    private func simulateMemoryWarning() {
        NotificationCenter.default.post(
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            refreshStats()
        }
    }
}

#Preview {
    NavigationStack {
        MemoryDebugView()
    }
}
#endif
