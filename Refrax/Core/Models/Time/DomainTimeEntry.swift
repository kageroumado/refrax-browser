import Foundation
import SwiftData

/// A record of time spent on a specific domain within a time window.
///
/// Each entry represents a single session (from becoming visible to becoming hidden).
/// Entries are aggregated per-domain using a rolling 24-hour window to calculate
/// total daily time spent.
///
/// ## Overview
///
/// Time entries enable:
/// - Displaying "Time today: 45m" in tab tooltips
/// - Enforcing daily time limits per domain
/// - Tracking browsing habits over time
///
/// ## Lifecycle
///
/// 1. Created when user switches to a tab showing a domain
/// 2. Duration recorded when switching away or closing tab
/// 3. Pruned automatically after 48 hours
///
/// - Note: Sessions shorter than 5 seconds are not recorded to avoid noise
///   from quick tab switches.
@Model
final class DomainTimeEntry {
    #Index<DomainTimeEntry>(
        [\.domain],
        [\.startTime],
        [\.domain, \.startTime],
    )

    // MARK: - Properties

    /// Unique identifier for this entry.
    @Attribute(.unique)
    var id: UUID

    /// The registrable domain (e.g., "twitter.com", not "mobile.twitter.com").
    ///
    /// Normalized using `URL.registrableDomain` to aggregate subdomains.
    var domain: String

    /// When this session started.
    var startTime: Date

    /// Duration of this session in seconds.
    var duration: TimeInterval

    // MARK: - Initialization

    /// Creates a new time entry for a completed session.
    ///
    /// - Parameters:
    ///   - domain: The registrable domain
    ///   - startTime: When the session started
    ///   - duration: How long the session lasted in seconds
    init(domain: String, startTime: Date, duration: TimeInterval) {
        self.id = UUID()
        self.domain = domain
        self.startTime = startTime
        self.duration = duration
    }
}

// MARK: - Convenience Extensions

extension DomainTimeEntry {
    /// Rolling window duration in seconds (24 hours).
    private static let rollingWindowSeconds: TimeInterval = 24 * 60 * 60

    /// Whether this entry is within the standard rolling window (24 hours).
    var isWithinRollingWindow: Bool {
        Date().timeIntervalSince(startTime) <= Self.rollingWindowSeconds
    }
}
