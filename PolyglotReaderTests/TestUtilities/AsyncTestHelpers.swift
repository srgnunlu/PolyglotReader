import Foundation
import XCTest
import Combine

/// Async test helpers for handling asynchronous operations in tests
enum AsyncTestHelpers {
    
    /// Wait for a condition to become true with timeout
    /// - Parameters:
    ///   - condition: Closure that returns true when condition is met
    ///   - timeout: Maximum time to wait
    ///   - pollInterval: How often to check the condition
    /// - Throws: XCTFail if timeout exceeded
    static func waitForCondition(
        _ condition: @escaping () -> Bool,
        timeout: TimeInterval = 2.0,
        pollInterval: TimeInterval = 0.1,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        let start = Date()
        
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timeout waiting for condition", file: file, line: line)
                return
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }
    
    /// Wait for an async operation to complete with timeout
    /// - Parameters:
    ///   - timeout: Maximum time to wait
    ///   - operation: Async operation to perform
    /// - Returns: Result of the operation
    static func withTimeout<T>(
        _ timeout: TimeInterval = 5.0,
        operation: @escaping () async throws -> T,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw AsyncTestError.timeout
            }
            
            guard let result = try await group.next() else {
                throw AsyncTestError.noResult
            }
            
            group.cancelAll()
            return result
        }
    }
    
    enum AsyncTestError: Error {
        case timeout
        case noResult
    }
}

// MARK: - Combine Test Helpers

extension XCTestCase {
    
    /// Wait for a publisher to emit a value
    /// - Parameters:
    ///   - publisher: The publisher to observe
    ///   - timeout: Maximum time to wait
    /// - Returns: The emitted value
    func awaitPublisher<T: Publisher>(
        _ publisher: T,
        timeout: TimeInterval = 1.0,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> T.Output where T.Failure == Never {
        var result: T.Output?
        let expectation = expectation(description: "Publisher emits value")
        
        let cancellable = publisher
            .first()
            .sink { value in
                result = value
                expectation.fulfill()
            }
        
        wait(for: [expectation], timeout: timeout)
        cancellable.cancel()
        
        guard let output = result else {
            XCTFail("Publisher did not emit value", file: file, line: line)
            throw AsyncTestHelpers.AsyncTestError.noResult
        }
        
        return output
    }
    
    /// Collect all values from a publisher over a time period
    /// - Parameters:
    ///   - publisher: The publisher to observe
    ///   - duration: Time to collect values
    /// - Returns: Array of collected values
    func collectPublisher<T: Publisher>(
        _ publisher: T,
        for duration: TimeInterval = 0.5,
        file: StaticString = #file,
        line: UInt = #line
    ) -> [T.Output] where T.Failure == Never {
        var results: [T.Output] = []
        let expectation = expectation(description: "Collect values")
        expectation.isInverted = true
        
        let cancellable = publisher
            .sink { value in
                results.append(value)
            }
        
        wait(for: [expectation], timeout: duration)
        cancellable.cancel()
        
        return results
    }
}

// MARK: - Memory Leak Detection

extension XCTestCase {
    
    /// Track an object for memory leaks
    /// - Parameters:
    ///   - instance: The object to track
    ///   - file: Source file
    ///   - line: Source line
    func trackForMemoryLeaks(
        _ instance: AnyObject,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        addTeardownBlock { [weak instance] in
            XCTAssertNil(
                instance,
                "Instance should have been deallocated. Potential memory leak.",
                file: file,
                line: line
            )
        }
    }
}
