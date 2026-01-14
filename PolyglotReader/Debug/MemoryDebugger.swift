import Foundation
import UIKit

// MARK: - Memory Debugger
/// Centralized memory debugging utility for development builds.
/// Tracks ViewModel lifecycle, memory warnings, and provides debug information.
/// All functionality is conditionally compiled and only active in DEBUG builds.
#if DEBUG
@MainActor
final class MemoryDebugger {
    static let shared = MemoryDebugger()

    // MARK: - Tracking

    /// Active ViewModel instances with their names
    private var activeInstances: [String: Int] = [:]

    /// Recent deinit logs (last 50)
    private var deinitLogs: [(timestamp: Date, name: String)] = []
    private let maxLogCount = 50

    /// Memory warning count
    private(set) var memoryWarningCount = 0

    private init() {
        setupMemoryWarningObserver()
        logInfo("MemoryDebugger", "Memory Debugger başlatıldı ✅")
    }

    // MARK: - Memory Warning Observer

    private func setupMemoryWarningObserver() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }

    @objc private func handleMemoryWarning() {
        memoryWarningCount += 1
        let stats = getStats()
        logWarning(
            "MemoryDebugger",
            "⚠️ Bellek Uyarısı #\(memoryWarningCount)",
            details: """
            Aktif VM'ler: \(stats.totalInstances)
            Dağılım: \(activeInstances.map { "\($0.key): \($0.value)" }.joined(separator: ", "))
            """
        )
    }

    // MARK: - Lifecycle Tracking

    /// Log ViewModel initialization
    func logInit(_ object: AnyObject) {
        let name = String(describing: type(of: object))
        activeInstances[name, default: 0] += 1
        logDebug("MemoryDebugger", "[INIT] \(name)", details: "Toplam: \(activeInstances[name] ?? 0)")
    }

    /// Log ViewModel deinitialization
    func logDeinit(_ object: AnyObject) {
        let name = String(describing: type(of: object))
        activeInstances[name, default: 0] -= 1

        // Remove from dictionary if count is 0
        if activeInstances[name] == 0 {
            activeInstances.removeValue(forKey: name)
        }

        // Add to logs
        deinitLogs.append((timestamp: Date(), name: name))
        if deinitLogs.count > maxLogCount {
            deinitLogs.removeFirst()
        }

        logInfo("MemoryDebugger", "[DEINIT] \(name) ✅", details: "Kalan: \(activeInstances[name] ?? 0)")
    }

    // MARK: - Statistics

    struct MemoryStats {
        let totalInstances: Int
        let instancesByType: [String: Int]
        let recentDeinits: [(timestamp: Date, name: String)]
        let memoryWarnings: Int
    }

    func getStats() -> MemoryStats {
        MemoryStats(
            totalInstances: activeInstances.values.reduce(0, +),
            instancesByType: activeInstances,
            recentDeinits: Array(deinitLogs.suffix(10)),
            memoryWarnings: memoryWarningCount
        )
    }

    /// Check for potential leaks (instances that should be 0)
    func checkForLeaks() -> [String] {
        activeInstances.filter { $0.value > 0 }.map { $0.key }
    }

    /// Reset all tracking (useful for testing)
    func reset() {
        activeInstances.removeAll()
        deinitLogs.removeAll()
        memoryWarningCount = 0
        logDebug("MemoryDebugger", "Tracking sıfırlandı")
    }
}
#endif

// MARK: - No-op Implementation for Release Builds
#if !DEBUG
@MainActor
final class MemoryDebugger {
    static let shared = MemoryDebugger()
    private init() {}

    func logInit(_ object: AnyObject) {}
    func logDeinit(_ object: AnyObject) {}
}
#endif
