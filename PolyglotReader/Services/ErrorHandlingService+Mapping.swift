import Foundation

extension ErrorHandlingService {
    // MARK: - Mapping

    nonisolated static func mapToAppError(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }

        if let geminiError = error as? GeminiError {
            return mapGeminiError(geminiError)
        }

        if let supabaseError = error as? SupabaseError {
            return mapSupabaseError(supabaseError)
        }

        if let ragError = error as? RAGError {
            return mapRAGError(ragError)
        }

        if let urlError = error as? URLError {
            return mapURLError(urlError)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return mapURLError(URLError(URLError.Code(rawValue: nsError.code)))
        }

        return AppError.unknown(
            message: AppLocalization.string("error.unknown"),
            recoverySuggestion: AppLocalization.string("recovery.general.retry"),
            underlying: error
        )
    }

    nonisolated static func severity(for appError: AppError) -> ErrorSeverity {
        switch appError {
        case .network(let reason, _):
            return reason == .cancelled ? .debug : .warning
        case .authentication:
            return .warning
        case .storage(let reason, _):
            switch reason {
            case .corrupted:
                return .error
            default:
                return .error
            }
        case .ai(let reason, _):
            switch reason {
            case .quotaExceeded:
                return .error
            default:
                return .warning
            }
        case .pdf(let reason, _):
            switch reason {
            case .memoryLimit:
                return .critical
            default:
                return .error
            }
        case .unknown:
            return .error
        }
    }

    // MARK: - Mapping Helpers

    nonisolated private static func mapGeminiError(_ error: GeminiError) -> AppError {
        switch error {
        case .noResponse:
            return .ai(reason: .noResponse, underlying: error)
        case .parseError:
            return .ai(reason: .parseFailed, underlying: error)
        case .sessionNotInitialized:
            return .ai(reason: .unavailable, underlying: error)
        case .rateLimitExceeded:
            return .ai(reason: .rateLimited, underlying: error)
        case .quotaExhausted:
            return .ai(reason: .quotaExceeded, underlying: error)
        case .networkUnavailable:
            return .network(reason: .unavailable, underlying: error)
        }
    }

    nonisolated private static func mapSupabaseError(_ error: SupabaseError) -> AppError {
        switch error {
        case .invalidConfiguration:
            return .storage(reason: .readFailed, underlying: error)
        case .authenticationRequired:
            return .authentication(reason: .required, underlying: error)
        case .networkError(let underlying):
            return .network(reason: .unavailable, underlying: underlying)
        case .databaseError:
            return .storage(reason: .readFailed, underlying: error)
        case .storageError:
            return .storage(reason: .writeFailed, underlying: error)
        case .encodingError, .decodingError:
            return .storage(reason: .corrupted, underlying: error)
        case .notFound:
            return .storage(reason: .notFound, underlying: error)
        case .unknown:
            return .unknown(
                message: AppLocalization.string("error.unknown"),
                recoverySuggestion: AppLocalization.string("recovery.general.retry"),
                underlying: error
            )
        }
    }

    nonisolated private static func mapRAGError(_ error: RAGError) -> AppError {
        switch error {
        case .embeddingFailed:
            return .ai(reason: .unavailable, underlying: error)
        case .searchFailed, .hybridSearchFailed:
            return .storage(reason: .readFailed, underlying: error)
        case .notIndexed:
            return .storage(reason: .notFound, underlying: error)
        case .rerankFailed, .tokenLimitExceeded:
            return .ai(reason: .parseFailed, underlying: error)
        }
    }

    nonisolated private static func mapURLError(_ error: URLError) -> AppError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
            return .network(reason: .unavailable, underlying: error)
        case .timedOut:
            return .network(reason: .timeout, underlying: error)
        case .cancelled:
            return .network(reason: .cancelled, underlying: error)
        default:
            return .network(reason: .invalidResponse, underlying: error)
        }
    }
}
