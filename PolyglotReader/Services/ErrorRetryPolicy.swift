import Foundation

struct ErrorRetryPolicy {
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let jitter: TimeInterval

    nonisolated static let standard = ErrorRetryPolicy(
        maxAttempts: 3,
        baseDelay: 0.6,
        maxDelay: 6.0,
        jitter: 0.3
    )

    /// Policy for user-initiated actions (3 retries, exponential backoff: 1s, 2s, 4s, max 30s)
    nonisolated static let userAction = ErrorRetryPolicy(
        maxAttempts: 3,
        baseDelay: 1.0,
        maxDelay: 30.0,
        jitter: 0.5
    )

    /// Policy for background operations (5 retries, exponential backoff: 1s, 2s, 4s, 8s, max 30s)
    nonisolated static let background = ErrorRetryPolicy(
        maxAttempts: 5,
        baseDelay: 1.0,
        maxDelay: 30.0,
        jitter: 0.5
    )
}
