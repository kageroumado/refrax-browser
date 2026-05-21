import AppKit
import Foundation
import Observation

/// Manages page activity state for accurate history time-spent tracking.
///
/// `HistoryActivityManager` centralizes the complex visibility logic that determines
/// when a page should accumulate browsing time. It observes:
/// - App active/inactive state
/// - System sleep/wake cycles
/// - Window key status
/// - Per-page visibility (registered by `WebViewContainer`)
///
/// A page is considered "active" when ALL conditions are met:
/// - The app is frontmost (active)
/// - The system is not sleeping
/// - The page's window is key
/// - The page's view is visible (registered)
///
/// ## Usage
///
/// ```swift
/// let manager = HistoryActivityManager()
/// manager.start()
///
/// // When a page becomes visible in a window
/// manager.registerPage(pageID, windowID: windowID)
///
/// // When the window becomes key
/// manager.updateWindowKey(windowID: windowID, isKey: true)
///
/// // Check if time should be tracked
/// if manager.isPageActive(pageID) {
///     // Accumulate time...
/// }
/// ```
///
/// ## Time Tracking Integration
///
/// Rather than calling `WebPage.onBecameVisible()` directly, views should register
/// with this manager. The manager tracks state transitions and provides a callback
/// mechanism to notify when a page's activity state changes.
@Observable
final class HistoryActivityManager {
    // MARK: - Activity State

    /// Whether the application is currently active (frontmost).
    private(set) var isAppActive: Bool = true

    /// Whether the system is sleeping.
    private(set) var isSystemSleeping: Bool = false

    // MARK: - Page Registration

    /// Tracks which pages are currently visible and in which windows.
    /// Key: PageID, Value: Set of WindowIDs displaying this page.
    /// A page can be visible in multiple windows simultaneously.
    private var visiblePages: [UUID: Set<ObjectIdentifier>] = [:]

    /// Tracks which windows are currently key.
    private var keyWindows: Set<ObjectIdentifier> = []

    /// Tracks the last known activity state for each page to detect transitions.
    private var pageActivityStates: [UUID: Bool] = [:]

    /// Callback invoked when a page's activity state changes.
    ///
    /// Parameters: (pageID, isNowActive)
    var onPageActivityChanged: ((UUID, Bool) -> Void)?

    // MARK: - Dependencies

    /// The centralized app activation observer.
    ///
    /// Must be set before calling `start()`. Wired up in AppDelegate.
    var activationObserver: AppActivationObserver?

    /// The centralized system sleep observer.
    ///
    /// Must be set before calling `start()`. Wired up in AppDelegate.
    var systemSleepObserver: SystemSleepObserver?

    // MARK: - Private State

    @ObservationIgnored
    private var isRunning = false

    @ObservationIgnored
    private var appStateObservationTask: Task<Void, Never>?

    @ObservationIgnored
    private var sleepObservationTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {}

    // MARK: - Lifecycle

    /// Starts monitoring app and system state.
    ///
    /// Safe to call multiple times; subsequent calls are no-ops.
    /// Requires `activationObserver` to be set before calling.
    func start() {
        guard !isRunning else { return }
        isRunning = true

        startAppStateObservation()
        startSleepObservation()

        Logger.info("History activity manager started", category: Logger.data)
    }

    /// Stops monitoring and releases resources.
    func stop() {
        guard isRunning else { return }
        isRunning = false

        // Stop observing app activation state
        appStateObservationTask?.cancel()
        appStateObservationTask = nil

        // Stop observing sleep state
        sleepObservationTask?.cancel()
        sleepObservationTask = nil

        Logger.info("History activity manager stopped", category: Logger.data)
    }

    // MARK: - Page Registration

    /// Registers a page as visible in a window.
    ///
    /// Call when a `WebViewContainer` appears. The page will be considered for
    /// activity tracking based on the combined app/window/system state.
    ///
    /// A page can be visible in multiple windows simultaneously. Time is tracked
    /// once per page (not per window) while at least one displaying window is key.
    ///
    /// - Parameters:
    ///   - pageID: The tab page's unique identifier.
    ///   - windowID: The window's object identifier.
    func registerPage(_ pageID: UUID, windowID: ObjectIdentifier) {
        let wasActive = isPageActive(pageID)
        visiblePages[pageID, default: []].insert(windowID)

        let isNowActive = isPageActive(pageID)
        if wasActive != isNowActive {
            pageActivityStates[pageID] = isNowActive
            onPageActivityChanged?(pageID, isNowActive)
        }
    }

    /// Unregisters a page from a specific window.
    ///
    /// Call when a `WebViewContainer` disappears. The page remains registered
    /// if it's still visible in other windows.
    ///
    /// - Parameters:
    ///   - pageID: The tab page's unique identifier.
    ///   - windowID: The window's object identifier.
    func unregisterPage(_ pageID: UUID, windowID: ObjectIdentifier) {
        let wasActive = isPageActive(pageID)

        visiblePages[pageID]?.remove(windowID)
        if visiblePages[pageID]?.isEmpty == true {
            visiblePages.removeValue(forKey: pageID)
            pageActivityStates.removeValue(forKey: pageID)
        }

        let isNowActive = isPageActive(pageID)
        if wasActive != isNowActive {
            onPageActivityChanged?(pageID, isNowActive)
        }
    }

    /// Updates the key window state.
    ///
    /// Call when a window becomes or resigns key status.
    ///
    /// - Parameters:
    ///   - windowID: The window's object identifier.
    ///   - isKey: Whether the window is now key.
    func updateWindowKey(windowID: ObjectIdentifier, isKey: Bool) {
        // Find all pages visible in this window
        let affectedPages = visiblePages.filter { $0.value.contains(windowID) }.map(\.key)

        // Capture old states
        var oldStates: [UUID: Bool] = [:]
        for pageID in affectedPages {
            oldStates[pageID] = isPageActive(pageID)
        }

        // Update key window set
        if isKey {
            keyWindows.insert(windowID)
        } else {
            keyWindows.remove(windowID)
        }

        // Notify affected pages of state changes
        for pageID in affectedPages {
            let wasActive = oldStates[pageID] ?? false
            let isNowActive = isPageActive(pageID)
            if wasActive != isNowActive {
                pageActivityStates[pageID] = isNowActive
                onPageActivityChanged?(pageID, isNowActive)
            }
        }
    }

    // MARK: - Activity Queries

    /// Returns whether a page is currently active (should accumulate time).
    ///
    /// A page is active when:
    /// - The app is active
    /// - The system is not sleeping
    /// - The page is registered (visible in at least one window)
    /// - At least one of the page's windows is key
    ///
    /// - Parameter pageID: The tab page's unique identifier.
    /// - Returns: `true` if time should be tracked for this page.
    func isPageActive(_ pageID: UUID) -> Bool {
        guard isAppActive, !isSystemSleeping else { return false }
        guard let windowIDs = visiblePages[pageID] else { return false }
        // Page is active if any of its visible windows is key
        return !windowIDs.isDisjoint(with: keyWindows)
    }

    /// Returns whether global conditions allow any time tracking.
    ///
    /// This is a quick check for periodic update tasks to avoid work
    /// when no tracking is possible.
    var canTrackTime: Bool {
        isAppActive && !isSystemSleeping
    }

    // MARK: - Private Setup

    /// Starts observing the activation observer's `isAppActive` property.
    private func startAppStateObservation() {
        guard let activationObserver else {
            Logger.warning("activationObserver not set, app state tracking disabled", category: Logger.data)
            return
        }

        // Sync initial state
        isAppActive = activationObserver.isAppActive

        let changes = Observations { activationObserver.isAppActive }

        appStateObservationTask = Task { [weak self] in
            for await newValue in changes {
                guard let self else { return }
                if newValue != isAppActive {
                    isAppActive = newValue
                    notifyAllPagesOfStateChange()
                }
            }
        }
    }

    /// Starts observing the system sleep observer's state.
    private func startSleepObservation() {
        guard let observer = systemSleepObserver else {
            Logger.warning("systemSleepObserver not set, sleep tracking disabled", category: Logger.data)
            return
        }

        let changes = Observations { observer.isSystemSleeping }
        sleepObservationTask = Task { [weak self] in
            for await isSleeping in changes {
                guard let self else { return }
                if isSleeping {
                    handleSystemWillSleep()
                } else {
                    handleSystemDidWake()
                }
            }
        }
    }

    // MARK: - State Change Handlers

    private func handleSystemWillSleep() {
        guard !isSystemSleeping else { return }
        isSystemSleeping = true
        Logger.debug("System will sleep", category: Logger.data)
        notifyAllPagesOfStateChange()
    }

    private func handleSystemDidWake() {
        guard isSystemSleeping else { return }
        isSystemSleeping = false
        Logger.debug("System did wake", category: Logger.data)
        notifyAllPagesOfStateChange()
    }

    /// Notifies all registered pages of potential activity state changes.
    private func notifyAllPagesOfStateChange() {
        for pageID in visiblePages.keys {
            let wasActive = pageActivityStates[pageID] ?? false
            let isNowActive = isPageActive(pageID)
            if wasActive != isNowActive {
                pageActivityStates[pageID] = isNowActive
                onPageActivityChanged?(pageID, isNowActive)
            }
        }
    }
}

// MARK: - Test Helpers

#if REFRAX_TESTS
    extension HistoryActivityManager {
        /// Sets the app active state for testing purposes.
        ///
        /// - Parameter active: Whether the app should be considered active.
        func setAppActiveForTesting(_ active: Bool) {
            if active != isAppActive {
                isAppActive = active
                notifyAllPagesOfStateChange()
            }
        }

        /// Sets the system sleeping state for testing purposes.
        ///
        /// - Parameter sleeping: Whether the system should be considered sleeping.
        func setSystemSleepingForTesting(_ sleeping: Bool) {
            if sleeping != isSystemSleeping {
                isSystemSleeping = sleeping
                notifyAllPagesOfStateChange()
            }
        }
    }
#endif
