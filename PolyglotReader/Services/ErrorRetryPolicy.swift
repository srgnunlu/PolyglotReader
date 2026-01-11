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
}
