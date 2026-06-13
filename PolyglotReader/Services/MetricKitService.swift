import Foundation

#if canImport(MetricKit) && os(iOS)
import MetricKit

/// Privacy-friendly, SDK-free crash & diagnostic reporting via Apple's MetricKit.
///
/// MetricKit delivers aggregated metric and diagnostic payloads (including crash,
/// hang, and disk-write-exception diagnostics with symbolicated call stacks) once
/// per day, or on the next launch after a crash. We forward a concise summary to
/// `LoggingService` so production issues are observable without a third-party SDK.
final class MetricKitService: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricKitService()

    private override init() {
        super.init()
    }

    /// Registers as a MetricKit subscriber. Safe to call once at launch.
    func start() {
        MXMetricManager.shared.add(self)
        logInfo("MetricKit", "MetricKit aboneliği başlatıldı")
    }

    // MARK: - MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            logInfo(
                "MetricKit",
                "Metric payload alındı",
                details: "appVersion: \(payload.latestApplicationVersion)"
            )
        }
    }

    @available(iOS 14.0, *)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            logCrashDiagnostics(payload.crashDiagnostics)
            logHangDiagnostics(payload.hangDiagnostics)
        }
    }

    // MARK: - Diagnostic Logging

    @available(iOS 14.0, *)
    private func logCrashDiagnostics(_ diagnostics: [MXCrashDiagnostic]?) {
        guard let diagnostics, !diagnostics.isEmpty else { return }

        for crash in diagnostics {
            let exceptionType = crash.exceptionType?.stringValue ?? "?"
            let signal = crash.signal?.stringValue ?? "?"
            let termination = crash.terminationReason ?? "?"
            logCritical(
                "MetricKit",
                "Crash teşhisi: exceptionType=\(exceptionType) signal=\(signal) " +
                    "termination=\(termination) appVersion=\(crash.applicationVersion)"
            )
        }
    }

    @available(iOS 14.0, *)
    private func logHangDiagnostics(_ diagnostics: [MXHangDiagnostic]?) {
        guard let diagnostics, !diagnostics.isEmpty else { return }

        for hang in diagnostics {
            logWarning(
                "MetricKit",
                "Hang teşhisi",
                details: "duration: \(hang.hangDuration), appVersion: \(hang.applicationVersion)"
            )
        }
    }
}
#endif
