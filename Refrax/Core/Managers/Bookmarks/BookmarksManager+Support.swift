import Foundation

// MARK: - Supporting Types

/// Cache key for favorites invalidation.
struct FavoritesCacheKey: Equatable {
    let count: Int
    let lastModified: Date
    let favoriteIDs: Set<UUID>
}

// MARK: - Helper: Timeout

/// Execute an async operation with a timeout.
func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T,
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        // Add the operation task
        group.addTask {
            try await operation()
        }

        // Add timeout task
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError()
        }

        // Return first completed result
        if let result = try await group.next() {
            group.cancelAll()
            return result
        }

        throw TimeoutError()
    }
}

/// Error thrown when an operation times out.
struct TimeoutError: Error {}
