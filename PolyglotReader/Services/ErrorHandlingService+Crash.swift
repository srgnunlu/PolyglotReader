import Darwin
import Foundation

extension ErrorHandlingService {
    func handleUncaughtException(_ exception: NSException) {
        let report = CrashReport(
            id: UUID(),
            timestamp: Date(),
            signal: nil,
            exceptionName: exception.name.rawValue,
            exceptionReason: exception.reason,
            stackTrace: exception.callStackSymbols,
            appState: stateSnapshot
        )

        let reason = exception.reason ?? ""
        logCritical("CrashHandler", "Uncaught exception: \(exception.name.rawValue) \(reason)")
        onCrashReport?(report)
        persistState(stateSnapshot)
    }

    func handleFatalSignal(_ signal: Int32) {
        let report = CrashReport(
            id: UUID(),
            timestamp: Date(),
            signal: signal,
            exceptionName: nil,
            exceptionReason: nil,
            stackTrace: Thread.callStackSymbols,
            appState: stateSnapshot
        )

        logCritical("CrashHandler", "Fatal signal: \(signal)")
        onCrashReport?(report)
        persistState(stateSnapshot)
    }

    func registerSignalHandlers() {
        signal(SIGABRT, Self.signalHandler)
        signal(SIGILL, Self.signalHandler)
        signal(SIGSEGV, Self.signalHandler)
        signal(SIGBUS, Self.signalHandler)
        signal(SIGFPE, Self.signalHandler)
    }

    static let signalHandler: @convention(c) (Int32) -> Void = { signal in
        Task { @MainActor in
            ErrorHandlingService.shared.handleFatalSignal(signal)
        }
    }
}
