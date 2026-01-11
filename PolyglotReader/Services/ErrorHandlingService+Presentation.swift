import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

extension ErrorHandlingService {
    enum PresentationStyle {
        case banner
        case alert
    }

    struct ErrorPresentation {
        let id: UUID
        let style: PresentationStyle
        let title: String
        let message: String
        let suggestion: String?
        let retryAction: (() -> Void)?
        let helpAction: (() -> Void)?
        let isCritical: Bool
        let signature: String
    }

    func shouldNotifyUser(
        appError: AppError,
        severity: ErrorSeverity,
        context: ErrorContext
    ) -> Bool {
        if context.isSilent || !context.notifyUser {
            return false
        }
        if case .network(let reason, _) = appError, reason == .cancelled {
            return false
        }
        return severity != .debug
    }

    func shouldSuppressPresentation(signature: String) -> Bool {
        let now = Date()
        recentSignatures = recentSignatures.filter { now.timeIntervalSince($0.value) < 60 }
        if let lastShown = recentSignatures[signature],
           now.timeIntervalSince(lastShown) < suppressionWindow {
            return true
        }
        recentSignatures[signature] = now
        return false
    }

    func buildPresentation(
        for appError: AppError,
        severity: ErrorSeverity,
        context: ErrorContext
    ) -> ErrorPresentation {
        let isCritical = severity == .critical
        let titleKey = isCritical ? "error.title.critical" : "error.title"
        let title = AppLocalization.string(titleKey)
        let style: PresentationStyle = isCritical || !appError.isRetryable ? .alert : .banner

        return ErrorPresentation(
            id: UUID(),
            style: style,
            title: title,
            message: appError.errorDescription ?? AppLocalization.string("error.unknown"),
            suggestion: appError.recoverySuggestion,
            retryAction: context.retryAction,
            helpAction: context.helpAction ?? { [weak self] in self?.openSupport() },
            isCritical: isCritical,
            signature: appError.signature
        )
    }

    func enqueuePresentation(_ presentation: ErrorPresentation) {
        if banner != nil || alert != nil {
            pendingPresentations.append(presentation)
            return
        }
        present(presentation)
    }

    func present(_ presentation: ErrorPresentation) {
        switch presentation.style {
        case .banner:
            banner = ErrorBanner(
                id: presentation.id,
                title: presentation.title,
                message: presentation.message,
                suggestion: presentation.suggestion,
                retryAction: presentation.retryAction,
                helpAction: presentation.helpAction,
                isCritical: presentation.isCritical
            )
            scheduleBannerDismissal()
        case .alert:
            alert = ErrorAlert(
                id: presentation.id,
                title: presentation.title,
                message: presentation.message,
                suggestion: presentation.suggestion,
                retryAction: presentation.retryAction,
                helpAction: presentation.helpAction,
                isCritical: presentation.isCritical
            )
        }
    }

    func presentNextIfNeeded() {
        guard banner == nil, alert == nil, let next = pendingPresentations.first else { return }
        pendingPresentations.removeFirst()
        present(next)
    }

    func scheduleBannerDismissal() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(bannerDuration * 1_000_000_000))
            if banner != nil {
                dismissBanner()
            }
        }
    }

    private func openSupport() {
        guard let supportURL else { return }
        #if canImport(UIKit)
        UIApplication.shared.open(supportURL)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(supportURL)
        #endif
    }
}
