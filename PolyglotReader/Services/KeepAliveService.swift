import Foundation
import Combine
import Supabase

/// Service to keep Supabase project active by periodically pinging the backend
/// Prevents free-tier projects from being paused due to inactivity
@MainActor
final class KeepAliveService: ObservableObject {
    // MARK: - Singleton

    static let shared = KeepAliveService()

    // MARK: - Published Properties

    @Published var lastPingDate: Date?
    @Published var lastPingStatus: PingStatus = .idle
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "keepAliveEnabled")
            if isEnabled {
                logInfo("KeepAliveService", "KeepAlive enabled")
            } else {
                logInfo("KeepAliveService", "KeepAlive disabled")
            }
        }
    }

    // MARK: - Types

    enum PingStatus: Equatable {
        case idle
        case pinging
        case success(Date)
        case failed(String)

        var displayText: String {
            switch self {
            case .idle:
                return "Henüz ping gönderilmedi"
            case .pinging:
                return "Ping gönderiliyor..."
            case .success(let date):
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                return "Başarılı: \(formatter.string(from: date))"
            case .failed(let error):
                return "Hata: \(error)"
            }
        }
    }

    // MARK: - Properties

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        // Load saved preference (default: enabled)
        self.isEnabled = UserDefaults.standard.object(forKey: "keepAliveEnabled") as? Bool ?? true

        // Load last ping date
        if let lastPingTimestamp = UserDefaults.standard.object(forKey: "lastPingDate") as? TimeInterval {
            let date = Date(timeIntervalSince1970: lastPingTimestamp)
            self.lastPingDate = date
            self.lastPingStatus = .success(date)
        }

        logDebug("KeepAliveService", "KeepAliveService initialized - enabled: \(isEnabled)")
    }

    // MARK: - Public Methods

    /// Sends a ping to Supabase to keep the project active
    func ping() async {
        guard isEnabled else {
            logDebug("KeepAliveService", "KeepAlive ping skipped - service is disabled")
            return
        }

        lastPingStatus = .pinging
        logInfo("KeepAliveService", "Sending keep-alive ping to Supabase...")

        do {
            // Simple health check: verify we can connect to Supabase
            // We'll do a minimal database query
            let userId = SupabaseService.shared.currentUser?.id

            if let userId = userId {
                // If user is logged in, fetch their files count (minimal query)
                _ = try await SupabaseService.shared.client.database
                    .from("files")
                    .select("id", head: true, count: .exact)
                    .eq("user_id", value: userId)
                    .execute()
                    .count
            } else {
                // If no user, just check if we can connect to auth
                _ = try await SupabaseService.shared.client.auth.session
            }

            let now = Date()
            lastPingDate = now
            lastPingStatus = .success(now)

            // Save to UserDefaults
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "lastPingDate")

            logInfo("KeepAliveService", "✅ Keep-alive ping successful")

        } catch {
            let errorMessage = error.localizedDescription
            lastPingStatus = .failed(errorMessage)
            logWarning("KeepAliveService", "❌ Keep-alive ping failed: \(errorMessage)")
        }
    }

    /// Performs an automatic ping if enough time has passed since last ping
    /// Recommended to call on app launch
    func pingIfNeeded() async {
        guard isEnabled else { return }

        // Check if we should ping (if more than 24 hours since last ping)
        if let lastPing = lastPingDate {
            let hoursSinceLastPing = Date().timeIntervalSince(lastPing) / 3600

            if hoursSinceLastPing < 24 {
                logDebug("KeepAliveService", "Keep-alive ping not needed - last ping was \(Int(hoursSinceLastPing)) hours ago")
                return
            }
        }

        // Ping is needed
        await ping()
    }

    /// Returns how many days until Supabase would pause the project
    var daysUntilPause: Int? {
        guard let lastPing = lastPingDate else { return nil }

        let daysSinceLastPing = Int(Date().timeIntervalSince(lastPing) / 86400)
        let daysRemaining = 7 - daysSinceLastPing

        return max(0, daysRemaining)
    }
}