import Foundation
import SwiftData

/// Background actor for DomainTimeTracker persistence operations.
///
/// All SwiftData operations are performed off the main thread to avoid
/// blocking tab switches and navigation. The main `DomainTimeTracker`
/// maintains cached state for UI observation.
@ModelActor
actor DomainTimeTrackerActor {
    // MARK: - Constants

    /// Rolling window duration in seconds (24 hours).
    private static let rollingWindowSeconds: TimeInterval = 24 * 60 * 60

    /// Retention period for old entries (48 hours).
    private static let retentionPeriod: TimeInterval = 48 * 60 * 60

    // MARK: - Session Recording

    /// Records a completed time tracking session.
    ///
    /// - Parameters:
    ///   - domain: The registrable domain.
    ///   - startTime: When the session started.
    ///   - duration: Session duration in seconds.
    func recordSession(domain: String, startTime: Date, duration: TimeInterval) {
        let entry = DomainTimeEntry(
            domain: domain,
            startTime: startTime,
            duration: duration,
        )
        modelContext.insert(entry)
        try? modelContext.save()
    }

    // MARK: - Time Queries

    /// Calculates time spent on a domain within the rolling window.
    ///
    /// - Parameters:
    ///   - domain: The registrable domain to query.
    ///   - window: Time window in seconds (default: 24 hours).
    /// - Returns: Total time spent in seconds.
    func timeSpent(on domain: String, in window: TimeInterval = rollingWindowSeconds) -> TimeInterval {
        let cutoff = Date().addingTimeInterval(-window)

        let descriptor = FetchDescriptor<DomainTimeEntry>(
            predicate: #Predicate { entry in
                entry.domain == domain && entry.startTime > cutoff
            },
        )

        let entries = (try? modelContext.fetch(descriptor)) ?? []
        return entries.reduce(0) { $0 + $1.duration }
    }

    /// Gets all domains with recorded time in the rolling window.
    ///
    /// - Returns: Dictionary of domain to time spent.
    func allDomainsTimeSpent(in window: TimeInterval = rollingWindowSeconds) -> [String: TimeInterval] {
        let cutoff = Date().addingTimeInterval(-window)

        let descriptor = FetchDescriptor<DomainTimeEntry>(
            predicate: #Predicate { entry in
                entry.startTime > cutoff
            },
        )

        let entries = (try? modelContext.fetch(descriptor)) ?? []

        var result: [String: TimeInterval] = [:]
        for entry in entries {
            result[entry.domain, default: 0] += entry.duration
        }

        return result
    }

    // MARK: - Limit Queries

    /// Gets the time limit for a domain, if one exists.
    ///
    /// - Parameter domain: The registrable domain.
    /// - Returns: Sendable snapshot of the limit, or nil if none configured.
    func limit(for domain: String) -> DomainTimeLimitData? {
        let descriptor = FetchDescriptor<DomainTimeLimit>(
            predicate: #Predicate { $0.domain == domain },
        )
        guard let limit = try? modelContext.fetch(descriptor).first else {
            return nil
        }
        return DomainTimeLimitData(from: limit)
    }

    /// Gets all configured time limits.
    ///
    /// - Returns: Array of all domain time limit snapshots.
    func allLimits() -> [DomainTimeLimitData] {
        let descriptor = FetchDescriptor<DomainTimeLimit>(
            sortBy: [SortDescriptor(\.domain)],
        )
        let limits = (try? modelContext.fetch(descriptor)) ?? []
        return limits.map { DomainTimeLimitData(from: $0) }
    }

    // MARK: - Limit Management

    /// Creates or updates a time limit for a domain.
    ///
    /// - Parameters:
    ///   - domain: The registrable domain.
    ///   - limitSeconds: Daily limit in seconds.
    ///   - enabled: Whether the limit is active.
    /// - Returns: Sendable snapshot of the created/updated limit.
    @discardableResult
    func setLimit(for domain: String, limitSeconds: Int, enabled: Bool = true) -> DomainTimeLimitData {
        let descriptor = FetchDescriptor<DomainTimeLimit>(
            predicate: #Predicate { $0.domain == domain },
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            existing.dailyLimitSeconds = limitSeconds
            existing.isEnabled = enabled
            try? modelContext.save()
            return DomainTimeLimitData(from: existing)
        }

        let newLimit = DomainTimeLimit(domain: domain, dailyLimitSeconds: limitSeconds)
        newLimit.isEnabled = enabled
        modelContext.insert(newLimit)
        try? modelContext.save()
        return DomainTimeLimitData(from: newLimit)
    }

    /// Removes the time limit for a domain.
    ///
    /// - Parameter domain: The registrable domain.
    func removeLimit(for domain: String) {
        let descriptor = FetchDescriptor<DomainTimeLimit>(
            predicate: #Predicate { $0.domain == domain },
        )

        guard let limit = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(limit)
        try? modelContext.save()
    }

    /// Uses a snooze extension for a domain.
    ///
    /// - Parameter domain: The registrable domain.
    /// - Returns: `true` if snooze was used, `false` if none remaining or no limit exists.
    @discardableResult
    func useSnooze(for domain: String) -> Bool {
        let descriptor = FetchDescriptor<DomainTimeLimit>(
            predicate: #Predicate { $0.domain == domain },
        )

        guard let limit = try? modelContext.fetch(descriptor).first else {
            return false
        }

        let success = limit.useSnooze()
        if success {
            try? modelContext.save()
        }
        return success
    }

    /// Gets current limit data after using snooze.
    ///
    /// - Parameter domain: The registrable domain.
    /// - Returns: Updated limit snapshot, or nil if no limit exists.
    func limitAfterSnooze(for domain: String) -> DomainTimeLimitData? {
        let descriptor = FetchDescriptor<DomainTimeLimit>(
            predicate: #Predicate { $0.domain == domain },
        )

        guard let limit = try? modelContext.fetch(descriptor).first else {
            return nil
        }
        return DomainTimeLimitData(from: limit)
    }

    // MARK: - Maintenance

    /// Removes entries older than the retention period.
    ///
    /// - Returns: Number of entries pruned.
    @discardableResult
    func pruneOldEntries() -> Int {
        let cutoff = Date().addingTimeInterval(-Self.retentionPeriod)
        let descriptor = FetchDescriptor<DomainTimeEntry>(
            predicate: #Predicate { $0.startTime < cutoff },
        )

        guard let oldEntries = try? modelContext.fetch(descriptor), !oldEntries.isEmpty else {
            return 0
        }

        for entry in oldEntries {
            modelContext.delete(entry)
        }
        try? modelContext.save()

        Logger.debug("Pruned \(oldEntries.count) old domain time entries", category: Logger.data)
        return oldEntries.count
    }
}

// MARK: - Sendable Data Transfer Type

/// Sendable snapshot of DomainTimeLimit for cross-actor transfer.
///
/// Marked nonisolated to opt out of implicit MainActor isolation.
nonisolated struct DomainTimeLimitData: Sendable {
    let domain: String
    let dailyLimitSeconds: Int
    let isEnabled: Bool
    let snoozesUsedToday: Int
    let effectiveLimitSeconds: Int
    let snoozesRemaining: Int
    let canSnooze: Bool

    init(from limit: DomainTimeLimit) {
        self.domain = limit.domain
        self.dailyLimitSeconds = limit.dailyLimitSeconds
        self.isEnabled = limit.isEnabled
        self.snoozesUsedToday = limit.snoozesUsedToday
        self.effectiveLimitSeconds = limit.effectiveLimitSeconds
        self.snoozesRemaining = limit.snoozesRemaining
        self.canSnooze = limit.canSnooze
    }
}
