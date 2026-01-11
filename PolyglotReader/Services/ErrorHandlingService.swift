import Combine
import Foundation

@MainActor
final class ErrorHandlingService: ObservableObject {
    static let shared = ErrorHandlingService()

    @Published var banner: ErrorBanner?
    @Published var alert: ErrorAlert?

    var onAnalyticsEvent: ((ErrorAnalyticsEvent) -> Void)?
    var onCrashReport: ((CrashReport) -> Void)?

    var recentSignatures: [String: Date] = [:]
    var pendingPresentations: [ErrorPresentation] = []
    var isConfigured = false
    var stateSnapshot = AppStateSnapshot(timestamp: Date())
    let suppressionWindow: TimeInterval = 2.5
    let bannerDuration: TimeInterval = 4.0
    let stateStorageKey = "polyglotreader.app_state_snapshot"
    let supportURL = URL(string: "https://polyglotreader.app/support")

    private init() {
        stateSnapshot = loadPersistedState() ?? AppStateSnapshot(timestamp: Date())
    }
}
