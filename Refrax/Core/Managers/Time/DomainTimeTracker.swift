import Foundation
import Observation
import SwiftData

// Tracks time spent on domains and enforces time limits.
//
// ## Overview
//
// `DomainTimeTracker` provides two key features:
// 1. **Time Tracking**: Records time spent per domain using a rolling 24-hour window
// 2. **Time Limits**: Enforces user-configured daily limits with snooze functionality
//
// ## Architecture
//
// All persistence operations are performed by `DomainTimeTrackerActor` on a background
// thread. The main tracker maintains only:
// - Active session state (in-memory, transient)
// - Cached UI state for the current domain (observed by views)
//
// This ensures tab switches never block on SwiftData operations.
//
// ## Time Tracking
//
// Time is tracked per registrable domain (e.g., "twitter.com"), not per-tab or per-URL.
// Sessions start when a tab becomes visible and end when it becomes hidden.
// Sessions shorter than 5 seconds are discarded to avoid noise from quick tab switches.
//
// ## Time Limits
//
// Users can configure daily limits per domain. When exceeded:
// - Page content is blurred
// - A banner appears with time spent information
// - Users can snooze (up to 3x per day, 5 minutes each)
// - Users can close the tab
//
// ## Integration
//
// Called from `WebPage.onBecameVisible()` / `onBecameHidden()`:
// ```swift
// func onBecameVisible() {
//     timeTracker.startSession(for: url)
// }
//
// func onBecameHidden() {
//     timeTracker.endCurrentSession()
// }
// ```

@Observable
final class DomainTimeTracker {
    // MARK: - Constants

    /// Rolling window duration in seconds (24 hours).
    static let rollingWindowSeconds: TimeInterval = 24 * 60 * 60

    /// Minimum session duration to record (5 seconds).
    ///
    /// Shorter sessions are discarded to avoid noise from quick tab switches.
    private static let minimumSessionDuration: TimeInterval = 5

    // MARK: - Background Actor

    /// Background actor for all persistence operations.
    @ObservationIgnored
    private var backgroundActor: DomainTimeTrackerActor?

    // MARK: - Session State

    /// Active session tracking (transient, not persisted).
    ///
    /// Only one session can be active at a time since only one tab is visible.
    @ObservationIgnored
    private var activeSession: (domain: String, startTime: Date)?

    // MARK: - Cached UI State

    /// The domain of the currently visible tab.
    private(set) var currentDomain: String?

    /// Cached limit for the current domain.
    private(set) var currentDomainLimit: DomainTimeLimitData?

    /// Cached time spent on current domain today.
    private(set) var currentDomainTimeToday: TimeInterval = 0

    /// Whether the current domain's limit has been exceeded.
    ///
    /// This is a cached stored property updated by `refreshCurrentDomainState()`,
    /// not a computed property. This ensures the TimeLimitModifier only re-renders
    /// when the exceeded state actually changes, not on every time update.
    /// The TimeLimitOverlayContainer (which shows when exceeded) separately
    /// observes `currentDomainTimeToday` for display.
    private(set) var isCurrentDomainLimitExceeded: Bool = false

    // MARK: - Initialization

    init() {
        // Background actor is initialized via deferred setup after first frame
    }

    /// Initializes the background actor for persistence operations.
    ///
    /// Call this after first frame renders to avoid blocking app launch.
    func initializeBackgroundActor(modelContainer: ModelContainer) {
        backgroundActor = DomainTimeTrackerActor(modelContainer: modelContainer)
    }

    // MARK: - Session Management

    /// Starts a new time tracking session for a URL.
    ///
    /// Ends any existing session before starting the new one.
    ///
    /// - Parameter url: The URL of the page becoming visible.
    func startSession(for url: URL) {
        guard let domain = url.registrableDomain else { return }

        // End any existing session first
        endCurrentSession()

        // Start new session
        activeSession = (domain, Date())
        currentDomain = domain

        // Refresh cached state asynchronously (non-blocking)
        Task {
            await refreshCurrentDomainState()
        }
    }

    /// Ends the current tracking session.
    ///
    /// Persistence happens asynchronously on the background actor.
    func endCurrentSession() {
        guard let session = activeSession else { return }

        let duration = Date().timeIntervalSince(session.startTime)

        // Only record sessions longer than minimum duration
        if duration >= Self.minimumSessionDuration {
            // Fire-and-forget background persistence
            Task {
                await backgroundActor?.recordSession(
                    domain: session.domain,
                    startTime: session.startTime,
                    duration: duration,
                )
            }
        }

        activeSession = nil
    }

    /// Updates the cached state for the current domain.
    ///
    /// Called asynchronously when session starts or after snooze.
    @MainActor
    func refreshCurrentDomainState() async {
        guard let domain = currentDomain, let actor = backgroundActor else {
            currentDomainTimeToday = 0
            currentDomainLimit = nil
            isCurrentDomainLimitExceeded = false
            return
        }

        // Fetch data from background actor
        let timeToday = await actor.timeSpent(on: domain)
        let limit = await actor.limit(for: domain)

        // Add current active session time
        currentDomainTimeToday = timeToday + activeSessionTime
        currentDomainLimit = limit

        // Update exceeded state
        if let limit, limit.isEnabled {
            isCurrentDomainLimitExceeded = currentDomainTimeToday >= TimeInterval(limit.effectiveLimitSeconds)
        } else {
            isCurrentDomainLimitExceeded = false
        }
    }

    /// Current active session time (for UI display).
    private var activeSessionTime: TimeInterval {
        guard let session = activeSession else { return 0 }
        return Date().timeIntervalSince(session.startTime)
    }

    // MARK: - Time Queries

    /// Calculates total time spent on a domain within the rolling window.
    ///
    /// Includes:
    /// - All persisted entries within the window
    /// - Current active session time (if same domain)
    ///
    /// - Parameters:
    ///   - domain: The registrable domain to query.
    ///   - window: Time window in seconds (default: 24 hours).
    /// - Returns: Total time spent in seconds.
    func timeSpent(on domain: String, in window: TimeInterval = rollingWindowSeconds) async -> TimeInterval {
        guard let actor = backgroundActor else { return 0 }

        var total = await actor.timeSpent(on: domain, in: window)

        // Add current active session if same domain
        if let session = activeSession, session.domain == domain {
            total += Date().timeIntervalSince(session.startTime)
        }

        return total
    }

    /// Gets all domains with recorded time in the rolling window.
    ///
    /// - Returns: Dictionary of domain to time spent.
    func allDomainsTimeSpent() async -> [String: TimeInterval] {
        guard let actor = backgroundActor else { return [:] }

        var result = await actor.allDomainsTimeSpent()

        // Add current active session
        if let session = activeSession {
            result[session.domain, default: 0] += Date().timeIntervalSince(session.startTime)
        }

        return result
    }

    // MARK: - Limit Management

    /// Gets the time limit for a domain, if one exists.
    ///
    /// - Parameter domain: The registrable domain.
    /// - Returns: The limit data, or nil if none configured.
    func limit(for domain: String) async -> DomainTimeLimitData? {
        await backgroundActor?.limit(for: domain)
    }

    /// Gets all configured time limits.
    ///
    /// - Returns: Array of all domain time limits.
    func allLimits() async -> [DomainTimeLimitData] {
        await backgroundActor?.allLimits() ?? []
    }

    /// Creates or updates a time limit for a domain.
    ///
    /// - Parameters:
    ///   - domain: The registrable domain.
    ///   - limitSeconds: Daily limit in seconds.
    ///   - enabled: Whether the limit is active.
    /// - Returns: The created or updated limit data.
    @discardableResult
    func setLimit(for domain: String, limitSeconds: Int, enabled: Bool = true) async -> DomainTimeLimitData? {
        guard let actor = backgroundActor else { return nil }
        let result = await actor.setLimit(for: domain, limitSeconds: limitSeconds, enabled: enabled)

        // Refresh current domain state if this affects it
        if domain == currentDomain {
            await refreshCurrentDomainState()
        }

        return result
    }

    /// Removes the time limit for a domain.
    ///
    /// - Parameter domain: The registrable domain.
    func removeLimit(for domain: String) async {
        await backgroundActor?.removeLimit(for: domain)

        // Refresh current domain state if this affects it
        if domain == currentDomain {
            await refreshCurrentDomainState()
        }
    }

    /// Uses a snooze extension for the current domain.
    ///
    /// - Returns: `true` if snooze was used, `false` if none remaining.
    @discardableResult
    func useSnoozeForCurrentDomain() async -> Bool {
        guard let domain = currentDomain, let actor = backgroundActor else {
            return false
        }

        let success = await actor.useSnooze(for: domain)
        if success {
            await refreshCurrentDomainState()
        }
        return success
    }

    // MARK: - Maintenance

    /// Removes entries older than the retention period.
    ///
    /// Called by `ScheduledTasksManager` on the hourly schedule.
    func pruneOldEntries() {
        Task {
            await backgroundActor?.pruneOldEntries()
        }
    }
}
