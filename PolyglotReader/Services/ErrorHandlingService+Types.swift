import Foundation

extension ErrorHandlingService {
    struct ErrorContext {
        let source: String
        let operation: String?
        let notifyUser: Bool
        let isSilent: Bool
        let retryAction: (() -> Void)?
        let helpAction: (() -> Void)?
        let metadata: [String: String]

        init(
            source: String,
            operation: String? = nil,
            notifyUser: Bool = true,
            isSilent: Bool = false,
            metadata: [String: String] = [:],
            retryAction: (() -> Void)? = nil,
            helpAction: (() -> Void)? = nil
        ) {
            self.source = source
            self.operation = operation
            self.notifyUser = notifyUser
            self.isSilent = isSilent
            self.metadata = metadata
            self.retryAction = retryAction
            self.helpAction = helpAction
        }

        static func silent(source: String, operation: String? = nil) -> ErrorContext {
            ErrorContext(source: source, operation: operation, notifyUser: false, isSilent: true)
        }
    }

    struct ErrorBanner: Identifiable {
        let id: UUID
        let title: String
        let message: String
        let suggestion: String?
        let retryAction: (() -> Void)?
        let helpAction: (() -> Void)?
        let isCritical: Bool
    }

    struct ErrorAlert: Identifiable {
        let id: UUID
        let title: String
        let message: String
        let suggestion: String?
        let retryAction: (() -> Void)?
        let helpAction: (() -> Void)?
        let isCritical: Bool
    }

    struct ErrorAnalyticsEvent {
        let id: UUID
        let timestamp: Date
        let category: AppError.Category
        let severity: ErrorSeverity
        let message: String
        let source: String
        let operation: String?
        let isRetryable: Bool
        let underlyingType: String?
    }

    struct CrashReport {
        let id: UUID
        let timestamp: Date
        let signal: Int32?
        let exceptionName: String?
        let exceptionReason: String?
        let stackTrace: [String]
        let appState: AppStateSnapshot?
    }

    struct AppStateSnapshot: Codable {
        var timestamp: Date
        var currentScreen: String?
        var selectedTab: Int?
        var isAuthenticated: Bool?
        var lastErrorSignature: String?
        var lastErrorMessage: String?
    }

    enum ErrorSeverity: String {
        case debug
        case warning
        case error
        case critical
    }
}
