import Foundation

extension ErrorHandlingService {
    // MARK: - Public API

    func handle(_ error: Error, context: ErrorContext) {
        let appError = Self.mapToAppError(error)
        let severity = Self.severity(for: appError)
        let signature = appError.signature

        recordStateForError(appError)
        log(appError: appError, severity: severity, context: context)
        sendAnalytics(appError: appError, severity: severity, context: context)

        guard shouldNotifyUser(appError: appError, severity: severity, context: context) else { return }
        guard !shouldSuppressPresentation(signature: signature) else { return }

        let presentation = buildPresentation(
            for: appError,
            severity: severity,
            context: context
        )
        enqueuePresentation(presentation)
    }

    func dismissBanner() {
        banner = nil
        presentNextIfNeeded()
    }

    func dismissAlert() {
        alert = nil
        presentNextIfNeeded()
    }

    func configureGlobalHandlers() {
        guard !isConfigured else { return }
        isConfigured = true

        NSSetUncaughtExceptionHandler { exception in
            Task { @MainActor in
                ErrorHandlingService.shared.handleUncaughtException(exception)
            }
        }

        registerSignalHandlers()
    }

    func recordAppState(
        currentScreen: String? = nil,
        selectedTab: Int? = nil,
        isAuthenticated: Bool? = nil
    ) {
        if let currentScreen {
            stateSnapshot.currentScreen = currentScreen
        }
        if let selectedTab {
            stateSnapshot.selectedTab = selectedTab
        }
        if let isAuthenticated {
            stateSnapshot.isAuthenticated = isAuthenticated
        }
        stateSnapshot.timestamp = Date()
        persistState(stateSnapshot)
    }

    func resetStateSnapshot() {
        stateSnapshot = AppStateSnapshot(timestamp: Date())
        persistState(stateSnapshot)
    }
}
