import Foundation
import IOKit
import LocalAuthentication
import Observation
import OpenDirectory

/// Manages Touch ID/password authentication for locked spaces.
///
/// `SpaceLockManager` provides biometric protection for sensitive spaces:
/// - Tracks which spaces are currently unlocked (global across all windows)
/// - Handles LAContext authentication with password fallback
/// - Auto-locks spaces on app background timeout, screen lock, or system sleep
/// - Monitors system idle time for inactivity-based auto-lock
///
/// ## Global Unlock State
///
/// Unlock state is global across all windows. When a space is unlocked
/// in one window, it's accessible in all windows until auto-lock triggers.
///
/// ## Auto-Lock Behavior
///
/// Spaces automatically re-lock when:
/// - System idle time exceeds the configured timeout
/// - App loses focus (for spaces with "onLoseFocus" timeout)
/// - Mac screen locks (immediate)
/// - System sleeps (all spaces lock immediately)
/// - User manually locks via context menu
///
/// ## Dependency Injection
///
/// Wire up `activationObserver` and `systemSleepObserver` in AppDelegate,
/// then call `start()` to begin observation.
@Observable
final class SpaceLockManager {
    // MARK: - State

    /// Space IDs that are currently unlocked.
    ///
    /// This is global across all windows. Authentication in one window
    /// unlocks the space everywhere.
    private(set) var unlockedSpaceIDs: Set<UUID> = []

    /// Tracks when each space was unlocked and its effective timeout.
    /// Used for per-space auto-lock timing.
    @ObservationIgnored
    private var spaceUnlockInfo: [UUID: SpaceUnlockInfo] = [:]

    /// Last user activity timestamp for timeout calculation.
    private var lastActivityTime: Date = .init()

    // MARK: - Dependencies

    private let settings: BrowserSettings

    /// Factory for creating LAContext instances (injectable for testing).
    @ObservationIgnored
    private let laContextFactory: () -> LAContext

    /// The centralized app activation observer.
    ///
    /// Must be set before calling `start()`. Wired up in AppDelegate.
    var activationObserver: AppActivationObserver?

    /// The centralized system sleep/screen lock observer.
    ///
    /// Must be set before calling `start()`. Wired up in AppDelegate.
    var systemSleepObserver: SystemSleepObserver?

    // MARK: - Auto-Lock Timer

    @ObservationIgnored
    private var autoLockTimer: Timer?

    @ObservationIgnored
    private var backgroundedAt: Date?

    // MARK: - Idle Time Monitoring

    /// Timer for periodic idle time checks.
    @ObservationIgnored
    private var idleCheckTimer: Timer?

    /// Interval for idle time polling (seconds).
    private let idleCheckInterval: TimeInterval = 15

    // MARK: - Observation Tasks

    @ObservationIgnored
    private var activationObservationTask: Task<Void, Never>?

    @ObservationIgnored
    private var sleepObservationTask: Task<Void, Never>?

    @ObservationIgnored
    private var screenLockObservationTask: Task<Void, Never>?

    @ObservationIgnored
    private var isRunning = false

    // MARK: - Initialization

    /// Creates a new space lock manager.
    ///
    /// - Parameters:
    ///   - settings: Browser settings for default lock timeout.
    ///   - laContextFactory: Factory for creating LAContext instances. Defaults to
    ///     creating real LAContext objects. Override for testing.
    init(
        settings: BrowserSettings,
        laContextFactory: @escaping () -> LAContext = { LAContext() },
    ) {
        self.settings = settings
        self.laContextFactory = laContextFactory
    }

    isolated deinit {
        activationObservationTask?.cancel()
        sleepObservationTask?.cancel()
        screenLockObservationTask?.cancel()
        idleCheckTimer?.invalidate()
        autoLockTimer?.invalidate()
    }

    // MARK: - Lifecycle

    /// Starts monitoring app state and system events for auto-lock.
    ///
    /// Safe to call multiple times; subsequent calls are no-ops.
    /// Requires `activationObserver` and `systemSleepObserver` to be set before calling.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        startActivationObservation()
        startSleepObservation()
        startIdleTimeMonitoring()

        Logger.info("SpaceLockManager started", category: Logger.security)
    }

    /// Stops monitoring and releases resources.
    func stop() {
        guard isRunning else { return }
        isRunning = false

        activationObservationTask?.cancel()
        activationObservationTask = nil

        sleepObservationTask?.cancel()
        sleepObservationTask = nil

        screenLockObservationTask?.cancel()
        screenLockObservationTask = nil

        stopIdleTimeMonitoring()
        cancelAutoLockTimer()
    }

    // MARK: - Authentication

    /// Checks if a space requires authentication to access.
    ///
    /// - Parameter space: The space to check.
    /// - Returns: `true` if the space has locking enabled and is not currently unlocked.
    func requiresAuth(for space: Space) -> Bool {
        space.isLockEnabled && !unlockedSpaceIDs.contains(space.id)
    }

    /// Authenticates to unlock a space.
    ///
    /// Uses Touch ID if available, with automatic password fallback via
    /// `LAPolicy.deviceOwnerAuthentication`.
    ///
    /// - Parameter space: The space to unlock.
    /// - Returns: The authentication result.
    func authenticate(for space: Space) async -> AuthenticationResult {
        // No auth needed if lock not enabled
        guard space.isLockEnabled else {
            return .success
        }

        // Already unlocked this session
        if unlockedSpaceIDs.contains(space.id) {
            return .success
        }

        let context = laContextFactory()
        var error: NSError?

        // Check if authentication is available
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            let reason = error?.localizedDescription ?? "Authentication unavailable"
            Logger.error("LAContext unavailable: \(reason)", category: Logger.security)
            return .unavailable(reason: reason)
        }

        // Build localized reason with space name
        let spaceName = space.name.isEmpty ? "this space" : "\"\(space.name)\""
        let localizedReason = "unlock \(spaceName)"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: localizedReason,
            )

            if success {
                markUnlocked(space: space)
                return .success
            } else {
                return .failed
            }
        } catch let authError as LAError {
            return handleLAError(authError)
        } catch {
            Logger.error("Unexpected auth error: \(error)", category: Logger.security)
            return .failed
        }
    }

    /// Authenticates before allowing security-sensitive operations.
    ///
    /// Unlike `authenticate(for:)`, this does NOT mark the space as unlocked.
    /// Use this for operations that require auth but shouldn't grant access,
    /// such as disabling the lock feature.
    ///
    /// - Parameter space: The space requiring authentication.
    /// - Returns: The authentication result.
    func authenticateToModifyLockSettings(for space: Space) async -> AuthenticationResult {
        let context = laContextFactory()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            let reason = error?.localizedDescription ?? "Authentication unavailable"
            Logger.error("LAContext unavailable: \(reason)", category: Logger.security)
            return .unavailable(reason: reason)
        }

        let spaceName = space.name.isEmpty ? "this space" : "\"\(space.name)\""
        let localizedReason = "Disable lock for \(spaceName)"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: localizedReason,
            )
            return success ? .success : .failed
        } catch let authError as LAError {
            return handleLAError(authError)
        } catch {
            Logger.error("Unexpected auth error: \(error)", category: Logger.security)
            return .failed
        }
    }

    /// Handles LAError cases and maps them to AuthenticationResult.
    private func handleLAError(_ error: LAError) -> AuthenticationResult {
        switch error.code {
        case .userCancel:
            return .cancelled
        case .userFallback:
            // With deviceOwnerAuthentication, this shouldn't happen
            // as password fallback is automatic
            return .failed
        case .biometryNotAvailable, .biometryNotEnrolled:
            return .unavailable(reason: "Touch ID not available")
        case .biometryLockout:
            return .unavailable(reason: "Touch ID is locked. Please use your password.")
        case .systemCancel, .appCancel:
            return .failed
        case .invalidContext:
            return .failed
        default:
            Logger.warning("Unhandled LAError: \(error.code.rawValue)", category: Logger.security)
            return .failed
        }
    }

    // MARK: - Password Authentication

    /// Validates the current user's macOS password without showing system UI.
    ///
    /// Uses OpenDirectory to verify against local user records. This enables
    /// inline password entry in the lock overlay without triggering LAContext
    /// system dialogs.
    ///
    /// - Parameter password: The password to validate.
    /// - Returns: `true` if the password is correct for the current user.
    private func validateMacOSPassword(_ password: String) -> Bool {
        do {
            let node = try ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeLocalNodes))
            let record = try node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
            try record.verifyPassword(password)
            return true
        } catch {
            Logger.debug("Password validation failed: \(error.localizedDescription)", category: Logger.security)
            return false
        }
    }

    /// Authenticates a space using a password.
    ///
    /// Validates the password against the current macOS user account and unlocks
    /// the space if successful. This provides inline authentication without
    /// system dialogs.
    ///
    /// - Parameters:
    ///   - password: The user's macOS password.
    ///   - space: The space to unlock.
    /// - Returns: The authentication result.
    func authenticateWithPassword(_ password: String, for space: Space) -> AuthenticationResult {
        guard space.isLockEnabled else { return .success }

        if unlockedSpaceIDs.contains(space.id) {
            return .success
        }

        guard !password.isEmpty else { return .failed }

        if validateMacOSPassword(password) {
            markUnlocked(space: space)
            Logger.info("Space unlocked via password: \(space.name)", category: Logger.security)
            return .success
        } else {
            return .failed
        }
    }

    // MARK: - Lock/Unlock Actions

    /// Marks a space as unlocked after successful LocalAuthenticationView auth.
    ///
    /// Called by LockedSpaceOverlayView when LocalAuthenticationView succeeds.
    /// This properly records the unlock info for auto-lock timing.
    ///
    /// - Parameter space: The space to mark as unlocked.
    func markUnlockedFromLocalAuthenticationView(space: Space) {
        markUnlocked(space: space)
        Logger.info("Space unlocked via Touch ID (LocalAuthenticationView): \(space.name)", category: Logger.security)
    }

    /// Marks a newly created space as unlocked without requiring authentication.
    ///
    /// When a user creates a space with lock enabled, they should be able to use it
    /// immediately without authenticating. The space will lock after the configured
    /// timeout or when manually locked.
    ///
    /// - Parameter space: The newly created space to mark as unlocked.
    func markUnlockedForNewSpace(space: Space) {
        guard space.isLockEnabled else { return }
        markUnlocked(space: space)
        Logger.info("New space marked unlocked: \(space.name)", category: Logger.security)
    }

    /// Internal helper to mark a space as unlocked and record unlock info.
    private func markUnlocked(space: Space) {
        unlockedSpaceIDs.insert(space.id)
        lastActivityTime = Date()

        let effectiveTimeout = space.lockTimeoutOverride ?? settings.defaultLockTimeout
        spaceUnlockInfo[space.id] = SpaceUnlockInfo(
            unlockedAt: Date(),
            effectiveTimeout: effectiveTimeout,
        )
        Logger.info("Space unlocked: \(space.name) (timeout: \(effectiveTimeout)s)", category: Logger.security)
    }

    /// Manually locks a specific space.
    ///
    /// - Parameter space: The space to lock.
    func lock(space: Space) {
        unlockedSpaceIDs.remove(space.id)
        spaceUnlockInfo.removeValue(forKey: space.id)
        Logger.info("Space manually locked: \(space.name)", category: Logger.security)
    }

    /// Locks all spaces immediately.
    ///
    /// Called on system sleep, screen lock, or as needed.
    func lockAll() {
        let count = unlockedSpaceIDs.count
        unlockedSpaceIDs.removeAll()
        spaceUnlockInfo.removeAll()
        if count > 0 {
            Logger.info("All spaces locked (\(count) were unlocked)", category: Logger.security)
        }
    }

    // MARK: - Activity Tracking

    /// Records user activity to reset the auto-lock timer.
    ///
    /// Call this when the user interacts with an unlocked space.
    func recordActivity() {
        lastActivityTime = Date()
    }

    // MARK: - Observation Setup

    /// Starts observing the activation observer's `isAppActive` property.
    private func startActivationObservation() {
        guard let observer = activationObserver else {
            Logger.warning("activationObserver not set, app activation tracking disabled", category: Logger.security)
            return
        }

        let changes = Observations { observer.isAppActive }
        activationObservationTask = Task { [weak self] in
            for await isActive in changes {
                guard let self else { return }
                if isActive {
                    handleAppActivated()
                } else {
                    handleAppDeactivated()
                }
            }
        }
    }

    /// Starts observing the system sleep observer's state.
    private func startSleepObservation() {
        guard let observer = systemSleepObserver else {
            Logger.warning("systemSleepObserver not set, sleep/screen lock tracking disabled", category: Logger.security)
            return
        }

        // Lock all spaces on system sleep
        let sleepChanges = Observations { observer.isSystemSleeping }
        sleepObservationTask = Task { [weak self] in
            for await isSleeping in sleepChanges {
                guard let self else { return }
                if isSleeping {
                    lockAll()
                    stopIdleTimeMonitoring()
                } else {
                    startIdleTimeMonitoring()
                }
            }
        }

        // Lock all spaces on screen lock
        let lockChanges = Observations { observer.isScreenLocked }
        screenLockObservationTask = Task { [weak self] in
            for await isLocked in lockChanges {
                guard let self else { return }
                if isLocked {
                    lockAll()
                }
            }
        }
    }

    // MARK: - App Activation Handlers

    private func handleAppActivated() {
        cancelAutoLockTimer()
        checkAutoLockExpiry()
        backgroundedAt = nil
    }

    private func handleAppDeactivated() {
        backgroundedAt = Date()

        // Lock spaces with "onLoseFocus" timeout immediately
        lockSpacesWithImmediateTimeout()

        startAutoLockTimer()
    }

    /// Locks all spaces that have the "onLoseFocus" timeout (-1).
    private func lockSpacesWithImmediateTimeout() {
        var spacesToLock: [UUID] = []

        for (spaceID, info) in spaceUnlockInfo {
            if info.effectiveTimeout == LockTimeout.onLoseFocus.rawValue {
                spacesToLock.append(spaceID)
            }
        }

        for spaceID in spacesToLock {
            unlockedSpaceIDs.remove(spaceID)
            spaceUnlockInfo.removeValue(forKey: spaceID)
            Logger.info("Space locked (app lost focus): \(spaceID)", category: Logger.security)
        }
    }

    // MARK: - Auto-Lock Timer

    private func startAutoLockTimer() {
        autoLockTimer?.invalidate()

        // Find the minimum remaining time among unlocked spaces
        let now = Date()
        var minRemainingTime: TimeInterval = .infinity

        for (_, unlockInfo) in spaceUnlockInfo {
            let timeout = TimeInterval(unlockInfo.effectiveTimeout)
            // Skip "never" (0), "onLoseFocus" (-1), and invalid values
            guard timeout > 0, timeout < TimeInterval(Int.max) else { continue }

            let elapsed = now.timeIntervalSince(unlockInfo.unlockedAt)
            let remaining = max(timeout - elapsed, 0)
            minRemainingTime = min(minRemainingTime, remaining)
        }

        // Fall back to global default if no spaces are tracked
        if minRemainingTime == .infinity {
            let timeout = TimeInterval(settings.defaultLockTimeout)
            guard timeout > 0, timeout < TimeInterval(Int.max) else { return }
            minRemainingTime = timeout
        }

        guard minRemainingTime > 0 else {
            // Already expired, check immediately when active
            return
        }

        autoLockTimer = Timer.scheduledTimer(withTimeInterval: minRemainingTime, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.checkAutoLockExpiry()
                    // Restart timer for any remaining spaces
                    self?.startAutoLockTimer()
                }
            }
        }
    }

    private func cancelAutoLockTimer() {
        autoLockTimer?.invalidate()
        autoLockTimer = nil
    }

    private func checkAutoLockExpiry() {
        let now = Date()
        var spacesToLock: [UUID] = []

        // Check each unlocked space against its individual timeout
        for (spaceID, unlockInfo) in spaceUnlockInfo {
            let timeout = TimeInterval(unlockInfo.effectiveTimeout)
            // Skip "never" (0), "onLoseFocus" (-1), and invalid values
            guard timeout > 0, timeout < TimeInterval(Int.max) else { continue }

            if now.timeIntervalSince(unlockInfo.unlockedAt) >= timeout {
                spacesToLock.append(spaceID)
            }
        }

        // Lock expired spaces
        for spaceID in spacesToLock {
            unlockedSpaceIDs.remove(spaceID)
            spaceUnlockInfo.removeValue(forKey: spaceID)
            Logger.info("Space auto-locked (timeout expired): \(spaceID)", category: Logger.security)
        }
    }

    // MARK: - Idle Time Monitoring

    /// Starts periodic idle time checking.
    private func startIdleTimeMonitoring() {
        guard idleCheckTimer == nil else { return }

        // Check every 15 seconds - balance between responsiveness and battery
        idleCheckTimer = Timer.scheduledTimer(withTimeInterval: idleCheckInterval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.checkIdleTimeExpiry()
                }
            }
        }
        idleCheckTimer?.tolerance = 3 // Allow system batching
    }

    /// Stops periodic idle time checking.
    private func stopIdleTimeMonitoring() {
        idleCheckTimer?.invalidate()
        idleCheckTimer = nil
    }

    /// Checks if any spaces should be locked due to system inactivity.
    private func checkIdleTimeExpiry() {
        // Don't check during sleep
        guard systemSleepObserver?.isSystemSleeping != true else { return }

        let idleSeconds = getSystemIdleTime()
        guard idleSeconds > 0 else { return } // IOKit failed, skip

        var spacesToLock: [UUID] = []

        for (spaceID, info) in spaceUnlockInfo {
            let timeout = info.effectiveTimeout
            // Skip "never" (0) and "onLoseFocus" (-1)
            guard timeout > 0 else { continue }

            // Lock at 90% of timeout (defensive - idle time isn't exact)
            if idleSeconds >= Double(timeout) * 0.9 {
                spacesToLock.append(spaceID)
            }
        }

        for spaceID in spacesToLock {
            unlockedSpaceIDs.remove(spaceID)
            spaceUnlockInfo.removeValue(forKey: spaceID)
            Logger.info("Space locked due to inactivity: \(spaceID)", category: Logger.security)
        }
    }

    /// Gets the system idle time in seconds using IOKit HIDIdleTime.
    ///
    /// - Returns: The idle time in seconds, or 0 if IOKit fails.
    private func getSystemIdleTime() -> TimeInterval {
        var iterator: io_iterator_t = 0

        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem"),
            &iterator,
        ) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return 0 }
        defer { IOObjectRelease(entry) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            entry,
            &properties,
            kCFAllocatorDefault,
            0,
        ) == KERN_SUCCESS,
            let dict = properties?.takeRetainedValue() as? [String: Any],
            let idleTime = dict["HIDIdleTime"] as? UInt64 else {
            return 0
        }

        // HIDIdleTime is in nanoseconds
        return TimeInterval(idleTime) / 1_000_000_000
    }
}

// MARK: - Space Unlock Info

/// Tracks unlock state for per-space timeout calculation.
private struct SpaceUnlockInfo {
    /// When the space was unlocked.
    let unlockedAt: Date

    /// Effective timeout in seconds (space override or global default).
    let effectiveTimeout: Int
}

// MARK: - Authentication Result

/// Result of a space authentication attempt.
enum AuthenticationResult: Equatable, Sendable {
    /// Authentication succeeded, space is now unlocked.
    case success

    /// Authentication failed (wrong password/fingerprint).
    case failed

    /// User cancelled the authentication prompt.
    case cancelled

    /// Authentication is unavailable on this system.
    case unavailable(reason: String)
}

// MARK: - Test Helpers

#if DEBUG
    extension SpaceLockManager {
        /// Test helper to directly mark a space as unlocked.
        func testOnly_markUnlocked(_ spaceID: UUID) {
            unlockedSpaceIDs.insert(spaceID)
        }

        /// Test helper to get last activity time.
        var testOnly_lastActivityTime: Date {
            lastActivityTime
        }

        /// Test helper to set last activity time.
        func testOnly_setLastActivityTime(_ date: Date) {
            lastActivityTime = date
        }

        /// Test helper to manually trigger auto-lock expiry check.
        func testOnly_checkAutoLockExpiry() {
            checkAutoLockExpiry()
        }

        /// Test helper to check if auto-lock timer is running.
        var testOnly_isAutoLockTimerActive: Bool {
            autoLockTimer?.isValid ?? false
        }
    }
#endif
