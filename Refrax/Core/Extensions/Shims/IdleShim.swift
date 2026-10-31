import AppKit
import CoreGraphics
import Foundation

/// The system's idle state as `idle.queryState` reports it: `locked` while the screen is
/// locked or the session is switched away, `idle` once no input has arrived for the
/// extension's detection interval, `active` otherwise.
///
/// Password managers lock their vaults on `idle` and `locked`, so these come from the system:
/// input idle time from the window server, the lock from the screen-lock and session
/// notifications.
final class IdleMonitor {
    enum State: String {
        case active
        case idle
        case locked
    }

    private enum Notifications {
        static let screenLocked = Notification.Name("com.apple.screenIsLocked")
        static let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")
    }

    private enum Timing {
        /// How often a waiting extension's state is checked; input has no notification.
        static let check = Duration.seconds(1)
    }

    private(set) var isLocked: Bool
    private let idleSeconds: () -> TimeInterval
    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    /// Creates a monitor.
    ///
    /// - Parameters:
    ///   - lockNotifications: Where `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked`
    ///     arrive: the distributed center, or a private one in tests.
    ///   - workspaceNotifications: Where session switches arrive.
    ///   - idleSeconds: Seconds since the last input event.
    ///   - isLocked: Whether the screen is locked now.
    init(
        lockNotifications: NotificationCenter = DistributedNotificationCenter.default(),
        workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
        idleSeconds: @escaping () -> TimeInterval = IdleMonitor.systemIdleSeconds,
        isLocked: Bool = IdleMonitor.screenIsLocked(),
    ) {
        self.idleSeconds = idleSeconds
        self.isLocked = isLocked
        observe(Notifications.screenLocked, in: lockNotifications, locked: true)
        observe(Notifications.screenUnlocked, in: lockNotifications, locked: false)
        observe(NSWorkspace.sessionDidResignActiveNotification, in: workspaceNotifications, locked: true)
        observe(NSWorkspace.sessionDidBecomeActiveNotification, in: workspaceNotifications, locked: false)
    }

    isolated deinit {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
    }

    private func observe(_ name: Notification.Name, in center: NotificationCenter, locked: Bool) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLocked = locked
            }
        }
        observers.append((center, token))
    }

    /// The state for an extension whose detection interval is `detectionInterval` seconds.
    func state(detectionInterval: TimeInterval) -> State {
        if isLocked {
            return .locked
        }
        return idleSeconds() >= detectionInterval ? .idle : .active
    }

    /// Waits until the state differs from `state`, for at most `limit`, and returns the state
    /// then.
    func nextState(after state: State, detectionInterval: TimeInterval, limit: Duration) async -> State {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline, !Task.isCancelled {
            let current = self.state(detectionInterval: detectionInterval)
            if current != state {
                return current
            }
            try? await Task.sleep(for: Timing.check)
        }
        return self.state(detectionInterval: detectionInterval)
    }

    /// Seconds since the user last pressed a key, moved the pointer or clicked.
    nonisolated static func systemIdleSeconds() -> TimeInterval {
        // ~0 is kCGAnyInputEventType.
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Whether the login window covers the session now.
    nonisolated static func screenIsLocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}

/// Backs `browser.idle` in extension pages with ``IdleMonitor``.
///
/// `queryState` answers at once. `waitForChange` holds the reply until the state differs from
/// the one the page last saw, or ``Limits/longestWait`` passes, so `onStateChanged` fires on
/// transitions without the page polling.
final class IdleShim: ExtensionShim {
    /// The state source; replaced in tests.
    lazy var monitor = IdleMonitor()

    private enum Limits {
        /// Chrome's floor for a detection interval.
        static let shortestInterval: TimeInterval = 15
        static let defaultInterval: TimeInterval = 60
        static let longestWait = Duration.seconds(60)
    }

    func handle(method: String, args: [String: Any], extensionID _: String) async throws -> Any? {
        let interval = max(Limits.shortestInterval, (args["detectionInterval"] as? Double) ?? Limits.defaultInterval)
        switch method {
        case "queryState":
            return monitor.state(detectionInterval: interval).rawValue
        case "waitForChange":
            let last = (args["state"] as? String).flatMap(IdleMonitor.State.init(rawValue:)) ?? .active
            return await monitor.nextState(after: last, detectionInterval: interval, limit: Limits.longestWait).rawValue
        default:
            throw ShimError.unsupportedMethod("idle.\(method)")
        }
    }
}
