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

    // MARK: - Network-Aware Retry

    /// Retry with network awareness - returns early if offline
    /// - Parameters:
    ///   - policy: The retry policy to use
    ///   - offlineError: Error to throw when offline (default: network error)
    ///   - operation: The async operation to perform
    /// - Returns: The result of the operation
    /// - Throws: Error if operation fails or device is offline
    @MainActor
    static func retryWithNetworkCheck<T>(
        policy: ErrorRetryPolicy = .userAction,
        offlineError: AppError? = nil,
        operation: () async throws -> T
    ) async throws -> T {
        // Check network status first
        guard NetworkMonitor.shared.isConnected else {
            let error = offlineError ?? AppError.network(
                reason: .unavailable
            )
            throw error
        }

        // Proceed with retry logic
        return try await retry(policy: policy, operation: operation)
    }

    /// Retry operation with fallback to offline queue
    /// - Parameters:
    ///   - policy: The retry policy to use
    ///   - operationType: The sync operation type for queueing
    ///   - fileId: Optional file ID for context
    ///   - payload: Closure to generate payload data for queueing
    ///   - operation: The async operation to perform
    /// - Returns: The result of the operation, or nil if queued
    @MainActor
    static func retryOrQueue<T>(
        policy: ErrorRetryPolicy = .userAction,
        operationType: SyncOperationType,
        fileId: String? = nil,
        payload: () throws -> Data,
        operation: () async throws -> T
    ) async throws -> T? {
        // If offline, queue immediately
        guard NetworkMonitor.shared.isConnected else {
            do {
                let data = try payload()
                SyncQueue.shared.enqueue(type: operationType, payload: data, fileId: fileId)
                return nil
            } catch {
                throw AppError.unknown(message: "Çevrimdışı işlem kuyruğa eklenemedi")
            }
        }

        // Try the operation with retry
        do {
            return try await retry(policy: policy, operation: operation)
        } catch {
            let appError = mapToAppError(error)

            // If network error, queue for later
            if case .network = appError {
                do {
                    let data = try payload()
                    SyncQueue.shared.enqueue(type: operationType, payload: data, fileId: fileId)
                    return nil
                } catch {
                    throw appError
                }
            }

            throw appError
        }
    }
}
