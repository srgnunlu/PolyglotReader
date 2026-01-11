import Foundation

extension ErrorHandlingService {
    func log(appError: AppError, severity: ErrorSeverity, context: ErrorContext) {
        let message = appError.errorDescription ?? AppLocalization.string("error.unknown")
        let details = appError.underlyingError?.localizedDescription

        switch severity {
        case .debug:
            Logger.debug(context.source, message, details: details)
        case .warning:
            Logger.warning(context.source, message, details: details)
        case .error:
            Logger.error(context.source, message, error: appError.underlyingError)
        case .critical:
            Logger.critical(context.source, message, error: appError.underlyingError)
        }
    }

    func sendAnalytics(appError: AppError, severity: ErrorSeverity, context: ErrorContext) {
        guard let onAnalyticsEvent else { return }
        let event = ErrorAnalyticsEvent(
            id: UUID(),
            timestamp: Date(),
            category: appError.category,
            severity: severity,
            message: appError.errorDescription ?? AppLocalization.string("error.unknown"),
            source: context.source,
            operation: context.operation,
            isRetryable: appError.isRetryable,
            underlyingType: appError.underlyingError.map { String(describing: type(of: $0)) }
        )
        onAnalyticsEvent(event)
    }
}
