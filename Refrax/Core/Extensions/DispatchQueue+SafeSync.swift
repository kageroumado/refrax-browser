import Foundation

/// Provides synchronous access to MainActor-isolated closures from any context.
///
/// This helper addresses the common pattern where legacy callbacks may or may
/// not be on the main thread, but the code inside needs MainActor isolation.
///
/// - If already on main thread: Uses `MainActor.assumeIsolated` (no thread hop)
/// - If on background thread: Uses `DispatchQueue.main.sync` (synchronous dispatch)
///
/// ## When to Use
///
/// Use this when you're in a callback that *might* be on main thread but you're
/// not certain. For callbacks where the thread is documented/guaranteed:
///
/// - **Guaranteed main thread** (e.g., `NotificationCenter` with `queue: .main`,
///   AppKit delegate methods): Use `MainActor.assumeIsolated` directly.
/// - **Guaranteed background thread**: Use `DispatchQueue.main.async` or
///   `DispatchQueue.main.sync` directly.
/// - **Uncertain**: Use this helper.
///
/// ## Safety
///
/// This is safe from deadlocks because:
/// - If on main thread, we don't dispatch at all
/// - If on background thread, `sync` to main is safe (main never waits on background)
///
/// The only deadlock risk with `DispatchQueue.main.sync` is when called from
/// the main thread itself (which we explicitly avoid).
enum MainActorSync {
    /// Runs the closure synchronously on the MainActor.
    ///
    /// If already on the main thread, executes via `MainActor.assumeIsolated`.
    /// Otherwise, dispatches synchronously to the main queue.
    ///
    /// - Parameter work: The MainActor-isolated work to execute.
    /// - Returns: The result of the work.
    @discardableResult
    static func run<T: Sendable>(_ work: @MainActor () -> T) -> T {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                work()
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    work()
                }
            }
        }
    }

    /// Runs the throwing closure synchronously on the MainActor.
    ///
    /// If already on the main thread, executes via `MainActor.assumeIsolated`.
    /// Otherwise, dispatches synchronously to the main queue.
    ///
    /// - Parameter work: The MainActor-isolated throwing work to execute.
    /// - Returns: The result of the work.
    /// - Throws: Any error thrown by the work.
    static func run<T: Sendable>(_ work: @MainActor () throws -> T) throws -> T {
        if Thread.isMainThread {
            try MainActor.assumeIsolated {
                try work()
            }
        } else {
            try DispatchQueue.main.sync {
                try MainActor.assumeIsolated {
                    try work()
                }
            }
        }
    }

    /// Runs the closure synchronously on the MainActor without a return value.
    ///
    /// This variant avoids Sendable constraints since there's no value to transfer
    /// across isolation boundaries.
    ///
    /// - Parameter work: The MainActor-isolated work to execute.
    static func run(_ work: @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                work()
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    work()
                }
            }
        }
    }
}
