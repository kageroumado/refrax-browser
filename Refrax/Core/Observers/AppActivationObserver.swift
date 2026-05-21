import AppKit
import Observation

/// Observes app activation events for use by scheduled tasks and archive expiration.
///
/// This observer tracks when Refrax becomes the frontmost application, publishing
/// activation events via an AsyncSequence and storing the last activation timestamp.
///
/// ## Overview
///
/// Archive expiration requires knowing when the user last actively used the app.
/// Tabs archived before the last activation have been "seen" by the user, so their
/// expiration timer can start. Tabs archived after remain unexpired until the next
/// activation, preventing silent disappearance during idle periods.
///
/// ```swift
/// let observer = AppActivationObserver()
///
/// // Check last activation
/// if let lastActive = observer.lastActivationTime {
///     let idleTime = Date().timeIntervalSince(lastActive)
/// }
///
/// // Subscribe to activations
/// for await date in observer.activations {
///     print("App activated at \(date)")
/// }
/// ```
///
/// ## Integration
///
/// - ``ScheduledTasksManager`` iterates ``activations`` to trigger tasks on activation
/// - ``TabArchiveManager`` uses ``lastActivationTime`` for expiration logic
@Observable
final class AppActivationObserver {
    // MARK: - State

    /// Whether the app is currently active (frontmost).
    ///
    /// Updated on both activation and deactivation events. Initialized to false
    /// until the first activation event is observed.
    private(set) var isAppActive: Bool = false

    /// The timestamp of the most recent app activation.
    ///
    /// `nil` until the app is activated for the first time after this observer is created.
    /// Use this to determine if archived tabs have been "seen" by the user.
    private(set) var lastActivationTime: Date?

    // MARK: - Async Sequence

    /// An async sequence that emits when the app becomes active.
    ///
    /// Each element is the activation timestamp. Use this with `for await` to
    /// react to activation events in a structured concurrency context.
    ///
    /// - Note: Each call creates a new stream subscription. The stream finishes
    ///   when this observer is deallocated.
    func makeActivationsStream() -> AsyncStream<Date> {
        let (stream, continuation) = AsyncStream.makeStream(of: Date.self)
        let id = UUID()
        continuations[id] = continuation

        continuation.onTermination = { @Sendable [weak self] _ in
            DispatchQueue.main.async { self?.continuations.removeValue(forKey: id) }
        }

        return stream
    }

    // MARK: - Private

    @ObservationIgnored
    private var continuations: [UUID: AsyncStream<Date>.Continuation] = [:]

    /// The activation notification observer token.
    ///
    /// Marked `nonisolated(unsafe)` to allow cleanup in deinit, which is nonisolated.
    /// Safe because: initialized once in `init` (on MainActor), only read in `deinit`.
    @ObservationIgnored
    private nonisolated(unsafe) var activationObserver: (any NSObjectProtocol)?

    /// The deactivation notification observer token.
    @ObservationIgnored
    private nonisolated(unsafe) var deactivationObserver: (any NSObjectProtocol)?

    // MARK: - Initialization

    init() {
        setupObserver()
    }

    deinit {
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = deactivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    private func setupObserver() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main,
        ) { [weak self] notification in
            guard let self else { return }

            // Check if the activated app is Refrax
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
                app.bundleIdentifier == Bundle.main.bundleIdentifier
            else {
                return
            }

            MainActor.assumeIsolated {
                self.handleActivation()
            }
        }

        deactivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main,
        ) { [weak self] notification in
            guard let self else { return }

            // Check if the deactivated app is Refrax
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication,
                app.bundleIdentifier == Bundle.main.bundleIdentifier
            else {
                return
            }

            MainActor.assumeIsolated {
                self.handleDeactivation()
            }
        }
    }

    private func handleActivation() {
        isAppActive = true

        let now = Date()
        lastActivationTime = now

        // Notify all subscribers
        for continuation in continuations.values {
            continuation.yield(now)
        }

        Logger.debug("App activated", category: Logger.tabs)
    }

    private func handleDeactivation() {
        isAppActive = false
        Logger.debug("App deactivated", category: Logger.tabs)
    }
}
