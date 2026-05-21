import Foundation
import SwiftData

/// A user-configured daily time limit for a specific domain.
///
/// When users spend more than `dailyLimitSeconds` on a domain within a rolling
/// 24-hour window, the page is blurred with a dismissible banner. Users can
/// snooze the limit up to 3 times per day, each extending by 5 minutes.
///
/// ## Overview
///
/// Time limits provide Screen Time-like functionality:
/// - Set per-domain limits (e.g., 30 minutes on twitter.com)
/// - Visual blur + banner when exceeded
/// - Limited snooze extensions per day
///
/// ## Usage
///
/// ```swift
/// let limit = DomainTimeLimit(domain: "twitter.com", dailyLimitSeconds: 1800)
/// limit.isEnabled = true
///
/// // Check if user can snooze
/// if limit.canSnooze {
///     limit.useSnooze()
/// }
/// ```
@Model
final class DomainTimeLimit {
    #Index<DomainTimeLimit>(
        [\.domain],
    )

    // MARK: - Constants

    /// Maximum number of snooze extensions allowed per rolling 24-hour window.
    static let maxSnoozesPerDay = 3

    /// Duration of each snooze extension in seconds (5 minutes).
    static let snoozeExtensionSeconds = 300

    /// Rolling window duration in seconds (24 hours).
    ///
    /// Matches `DomainTimeTracker.rollingWindowSeconds`.
    static let rollingWindowSeconds: TimeInterval = 24 * 60 * 60

    // MARK: - Properties

    /// Unique identifier for this limit.
    @Attribute(.unique, .preserveValueOnDeletion)
    var id: UUID

    /// The registrable domain this limit applies to.
    ///
    /// Uses the same normalization as `DomainTimeEntry` for consistency.
    @Attribute(.unique)
    var domain: String

    /// The daily time limit in seconds.
    ///
    /// Common values:
    /// - 900: 15 minutes
    /// - 1800: 30 minutes
    /// - 3600: 1 hour
    /// - 7200: 2 hours
    var dailyLimitSeconds: Int

    /// Whether this limit is currently active.
    ///
    /// Users can disable limits temporarily without deleting them.
    var isEnabled: Bool

    /// Number of snooze extensions used in the current 24-hour window.
    ///
    /// Reset automatically when `lastSnoozeReset` is older than 24 hours.
    var snoozesUsedToday: Int

    /// When the snooze count was last reset.
    ///
    /// Used to determine when to reset `snoozesUsedToday`.
    /// If nil, the first snooze will set this to the current date.
    var lastSnoozeReset: Date?

    // MARK: - Initialization

    /// Creates a new time limit for a domain.
    ///
    /// - Parameters:
    ///   - domain: The registrable domain to limit
    ///   - dailyLimitSeconds: Maximum seconds allowed per rolling 24-hour window
    init(domain: String, dailyLimitSeconds: Int) {
        self.id = UUID()
        self.domain = domain
        self.dailyLimitSeconds = dailyLimitSeconds
        self.isEnabled = true
        self.snoozesUsedToday = 0
        self.lastSnoozeReset = nil
    }
}

// MARK: - Snooze Management

extension DomainTimeLimit {
    /// Whether the user can still snooze this limit today.
    var canSnooze: Bool {
        // Check if reset is needed first
        if needsSnoozeReset {
            return true
        }
        return snoozesUsedToday < Self.maxSnoozesPerDay
    }

    /// Number of snooze extensions remaining today.
    var snoozesRemaining: Int {
        if needsSnoozeReset {
            return Self.maxSnoozesPerDay
        }
        return max(0, Self.maxSnoozesPerDay - snoozesUsedToday)
    }

    /// Whether the snooze count should be reset.
    private var needsSnoozeReset: Bool {
        guard let lastReset = lastSnoozeReset else { return true }
        return Date().timeIntervalSince(lastReset) >= Self.rollingWindowSeconds
    }

    /// Uses one snooze extension.
    ///
    /// - Returns: `true` if snooze was used, `false` if none remaining.
    @discardableResult
    func useSnooze() -> Bool {
        // Reset if needed
        if needsSnoozeReset {
            snoozesUsedToday = 0
            lastSnoozeReset = Date()
        }

        guard canSnooze else { return false }
        snoozesUsedToday += 1
        return true
    }

    /// The effective limit in seconds, including any active snooze extensions.
    ///
    /// If snoozes have been used, each adds 5 minutes to the effective limit.
    var effectiveLimitSeconds: Int {
        dailyLimitSeconds + (snoozesUsedToday * Self.snoozeExtensionSeconds)
    }
}

// MARK: - Display Helpers

extension DomainTimeLimit {
    /// Human-readable limit duration (e.g., "30 minutes", "1 hour").
    var formattedLimit: String {
        TimeInterval(dailyLimitSeconds).formattedDuration
    }
}
