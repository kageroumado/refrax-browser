import AppKit
import Foundation
import Observation

/// Observes system sleep/wake state and screen lock status.
///
/// Provides observable state for other managers to react to:
/// - Sleep/wake cycles via NSWorkspace notifications
/// - Screen lock/unlock via distributed notifications
///
/// ## Integration
///
/// Wire dependencies in AppDelegate and use `Observations` to react to state changes:
///
/// ```swift
/// let sleepChanges = Observations { sleepObserver.isSystemSleeping }
/// Task {
///     for await isSleeping in sleepChanges {
///         if isSleeping { pauseWork() }
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// All notification handlers dispatch to the main queue and use
/// `MainActor.assumeIsolated` for synchronous access from main thread.
@Observable
final class SystemSleepObserver {
    // MARK: - State

    /// Whether the system is currently sleeping.
    private(set) var isSystemSleeping: Bool = false

    /// Whether the screen is currently locked.
    private(set) var isScreenLocked: Bool = false

    // MARK: - Private

    @ObservationIgnored
    private nonisolated(unsafe) var sleepObserver: (any NSObjectProtocol)?

    @ObservationIgnored
    private nonisolated(unsafe) var wakeObserver: (any NSObjectProtocol)?

    @ObservationIgnored
    private nonisolated(unsafe) var screenLockObserver: (any NSObjectProtocol)?

    @ObservationIgnored
    private nonisolated(unsafe) var screenUnlockObserver: (any NSObjectProtocol)?

    // MARK: - Initialization

    init() {
        setupObservers()
    }

    deinit {
        let workspace = NSWorkspace.shared.notificationCenter
        if let o = sleepObserver { workspace.removeObserver(o) }
        if let o = wakeObserver { workspace.removeObserver(o) }

        let distributed = DistributedNotificationCenter.default()
        if let o = screenLockObserver { distributed.removeObserver(o) }
        if let o = screenUnlockObserver { distributed.removeObserver(o) }
    }

    // MARK: - Setup

    private func setupObservers() {
        let workspace = NSWorkspace.shared.notificationCenter

        sleepObserver = workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.isSystemSleeping = true
                Logger.debug("System will sleep", category: Logger.security)
            }
        }

        wakeObserver = workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.isSystemSleeping = false
                Logger.debug("System did wake", category: Logger.security)
            }
        }

        let distributed = DistributedNotificationCenter.default()

        screenLockObserver = distributed.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.isScreenLocked = true
                Logger.debug("Screen locked", category: Logger.security)
            }
        }

        screenUnlockObserver = distributed.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.isScreenLocked = false
                Logger.debug("Screen unlocked", category: Logger.security)
            }
        }
    }
}
