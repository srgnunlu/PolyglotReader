import Foundation

/// Central application error type for consistent handling and localization.
enum AppError: Error, LocalizedError {
    case network(reason: NetworkReason, underlying: Error? = nil)
    case authentication(reason: AuthReason, underlying: Error? = nil)
    case storage(reason: StorageReason, underlying: Error? = nil)
    case ai(reason: AIReason, underlying: Error? = nil)
    case pdf(reason: PDFReason, underlying: Error? = nil)
    case unknown(message: String, recoverySuggestion: String? = nil, underlying: Error? = nil)

    enum Category: String {
        case network
        case authentication
        case storage
        case ai
        case pdf
        case unknown
    }

    enum NetworkReason: Equatable {
        case unavailable
        case timeout
        case invalidResponse
        case server(statusCode: Int?)
        case rateLimited(retryAfter: TimeInterval?)
        case cancelled
    }

    enum AuthReason {
        case required
        case expired
        case invalidCredentials
        case forbidden
    }

    enum StorageReason {
        case notFound
        case accessDenied
        case quotaExceeded
        case writeFailed
        case readFailed
        case corrupted
    }

    enum AIReason {
        case noResponse
        case parseFailed
        case rateLimited
        case quotaExceeded
        case unavailable
    }

    enum PDFReason {
        case corrupted
        case empty
        case encrypted
        case tooLarge
        case renderFailed
        case memoryLimit
        case unsupported
    }

    var errorDescription: String? {
        userMessage
    }

    var recoverySuggestion: String? {
        userRecoverySuggestion
    }

    var category: Category {
        switch self {
        case .network:
            return .network
        case .authentication:
            return .authentication
        case .storage:
            return .storage
        case .ai:
            return .ai
        case .pdf:
            return .pdf
        case .unknown:
            return .unknown
        }
    }

    var underlyingError: Error? {
        switch self {
        case .network(_, let underlying),
             .authentication(_, let underlying),
             .storage(_, let underlying),
             .ai(_, let underlying),
             .pdf(_, let underlying):
            return underlying
        case .unknown(_, _, let underlying):
            return underlying
        }
    }

    var isRetryable: Bool {
        switch self {
        case .network(let reason, _):
            switch reason {
            case .cancelled:
                return false
            default:
                return true
            }
        case .authentication(let reason, _):
            return reason == .expired
        case .storage(let reason, _):
            switch reason {
            case .quotaExceeded, .accessDenied, .corrupted:
                return false
            default:
                return true
            }
        case .ai(let reason, _):
            switch reason {
            case .rateLimited, .unavailable:
                return true
            case .quotaExceeded:
                return false
            default:
                return true
            }
        case .pdf(let reason, _):
            switch reason {
            case .corrupted, .empty, .unsupported, .encrypted, .tooLarge, .memoryLimit:
                return false
            case .renderFailed:
                return true
            }
        case .unknown:
            return false
        }
    }

    var signature: String {
        switch self {
        case .network(let reason, _):
            return "network.\(reason.signature)"
        case .authentication(let reason, _):
            return "auth.\(reason.signature)"
        case .storage(let reason, _):
            return "storage.\(reason.signature)"
        case .ai(let reason, _):
            return "ai.\(reason.signature)"
        case .pdf(let reason, _):
            return "pdf.\(reason.signature)"
        case .unknown(let message, _, _):
            return "unknown.\(message)"
        }
    }

    private var userMessage: String {
        switch self {
        case .network(let reason, _):
            return reason.userMessage
        case .authentication(let reason, _):
            return reason.userMessage
        case .storage(let reason, _):
            return reason.userMessage
        case .ai(let reason, _):
            return reason.userMessage
        case .pdf(let reason, _):
            return reason.userMessage
        case .unknown(let message, _, _):
            return message.isEmpty ? AppLocalization.string("error.unknown") : message
        }
    }

    private var userRecoverySuggestion: String? {
        switch self {
        case .network(let reason, _):
            return reason.recoverySuggestion
        case .authentication(let reason, _):
            return reason.recoverySuggestion
        case .storage(let reason, _):
            return reason.recoverySuggestion
        case .ai(let reason, _):
            return reason.recoverySuggestion
        case .pdf(let reason, _):
            return reason.recoverySuggestion
        case .unknown(_, let suggestion, _):
            return suggestion ?? AppLocalization.string("recovery.general.retry")
        }
    }
}

private extension AppError.NetworkReason {
    var signature: String {
        switch self {
        case .unavailable: return "unavailable"
        case .timeout: return "timeout"
        case .invalidResponse: return "invalid_response"
        case .server(let statusCode):
            return "server_\(statusCode ?? 0)"
        case .rateLimited:
            return "rate_limited"
        case .cancelled:
            return "cancelled"
        }
    }

    var userMessage: String {
        switch self {
        case .unavailable:
            return AppLocalization.string("error.network.unavailable")
        case .timeout:
            return AppLocalization.string("error.network.timeout")
        case .invalidResponse:
            return AppLocalization.string("error.network.invalid_response")
        case .server(let statusCode):
            if let statusCode {
                return AppLocalization.string("error.network.server_error", statusCode)
            }
            return AppLocalization.string("error.network.server_error_generic")
        case .rateLimited:
            return AppLocalization.string("error.network.rate_limited")
        case .cancelled:
            return AppLocalization.string("error.network.cancelled")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .rateLimited:
            return AppLocalization.string("recovery.network.wait_retry")
        case .cancelled:
            return nil
        default:
            return AppLocalization.string("recovery.network.check_connection")
        }
    }
}

private extension AppError.AuthReason {
    var signature: String {
        switch self {
        case .required: return "required"
        case .expired: return "expired"
        case .invalidCredentials: return "invalid_credentials"
        case .forbidden: return "forbidden"
        }
    }

    var userMessage: String {
        switch self {
        case .required:
            return AppLocalization.string("error.auth.required")
        case .expired:
            return AppLocalization.string("error.auth.expired")
        case .invalidCredentials:
            return AppLocalization.string("error.auth.invalid")
        case .forbidden:
            return AppLocalization.string("error.auth.forbidden")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .invalidCredentials, .expired, .required:
            return AppLocalization.string("recovery.auth.sign_in")
        case .forbidden:
            return AppLocalization.string("recovery.auth.permissions")
        }
    }
}

private extension AppError.StorageReason {
    var signature: String {
        switch self {
        case .notFound: return "not_found"
        case .accessDenied: return "access_denied"
        case .quotaExceeded: return "quota"
        case .writeFailed: return "write_failed"
        case .readFailed: return "read_failed"
        case .corrupted: return "corrupted"
        }
    }

    var userMessage: String {
        switch self {
        case .notFound:
            return AppLocalization.string("error.storage.not_found")
        case .accessDenied:
            return AppLocalization.string("error.storage.access_denied")
        case .quotaExceeded:
            return AppLocalization.string("error.storage.quota")
        case .writeFailed:
            return AppLocalization.string("error.storage.write_failed")
        case .readFailed:
            return AppLocalization.string("error.storage.read_failed")
        case .corrupted:
            return AppLocalization.string("error.storage.corrupted")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .quotaExceeded:
            return AppLocalization.string("recovery.storage.free_space")
        case .accessDenied:
            return AppLocalization.string("recovery.storage.permissions")
        case .notFound:
            return AppLocalization.string("recovery.storage.retry")
        case .corrupted:
            return AppLocalization.string("recovery.storage.restore")
        default:
            return AppLocalization.string("recovery.general.retry")
        }
    }
}

private extension AppError.AIReason {
    var signature: String {
        switch self {
        case .noResponse: return "no_response"
        case .parseFailed: return "parse_failed"
        case .rateLimited: return "rate_limited"
        case .quotaExceeded: return "quota"
        case .unavailable: return "unavailable"
        }
    }

    var userMessage: String {
        switch self {
        case .noResponse:
            return AppLocalization.string("error.ai.no_response")
        case .parseFailed:
            return AppLocalization.string("error.ai.parse_failed")
        case .rateLimited:
            return AppLocalization.string("error.ai.rate_limited")
        case .quotaExceeded:
            return AppLocalization.string("error.ai.quota")
        case .unavailable:
            return AppLocalization.string("error.ai.unavailable")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .rateLimited, .unavailable:
            return AppLocalization.string("recovery.ai.retry_later")
        case .quotaExceeded:
            return AppLocalization.string("recovery.ai.quota")
        default:
            return AppLocalization.string("recovery.general.retry")
        }
    }
}

private extension AppError.PDFReason {
    var signature: String {
        switch self {
        case .corrupted: return "corrupted"
        case .empty: return "empty"
        case .encrypted: return "encrypted"
        case .tooLarge: return "too_large"
        case .renderFailed: return "render_failed"
        case .memoryLimit: return "memory_limit"
        case .unsupported: return "unsupported"
        }
    }

    var userMessage: String {
        switch self {
        case .corrupted:
            return AppLocalization.string("error.pdf.corrupted")
        case .empty:
            return AppLocalization.string("error.pdf.empty")
        case .encrypted:
            return AppLocalization.string("error.pdf.encrypted")
        case .tooLarge:
            return AppLocalization.string("error.pdf.too_large")
        case .renderFailed:
            return AppLocalization.string("error.pdf.render_failed")
        case .memoryLimit:
            return AppLocalization.string("error.pdf.memory")
        case .unsupported:
            return AppLocalization.string("error.pdf.unsupported")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .tooLarge:
            return AppLocalization.string("recovery.pdf.reduce_size")
        case .encrypted:
            return AppLocalization.string("recovery.pdf.decrypt")
        case .renderFailed:
            return AppLocalization.string("recovery.general.retry")
        default:
            return AppLocalization.string("recovery.pdf.try_another")
        }
    }
}
