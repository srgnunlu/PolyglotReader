import Foundation

extension ErrorHandlingService {
    // MARK: - Retry Logic

    nonisolated static func retry<T>(
        policy: ErrorRetryPolicy = .standard,
        operation: () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var lastError: Error?

        while attempt < policy.maxAttempts {
            attempt += 1
            do {
                return try await operation()
            } catch {
                lastError = error
                let appError = mapToAppError(error)
                guard appError.isRetryable, attempt < policy.maxAttempts else {
                    throw appError
                }

                let delay = min(policy.maxDelay, policy.baseDelay * pow(2.0, Double(attempt - 1)))
                let jitter = Double.random(in: 0...policy.jitter)
                let sleepTime = delay + jitter
                try? await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000))
            }
        }

        throw mapToAppError(lastError ?? AppError.unknown(message: AppLocalization.string("error.unknown")))
    }
}
