import Foundation
import SwiftData

/// Background actor for history maintenance operations.
///
/// Performs heavy SwiftData operations off the main thread to avoid blocking
/// app launch and UI responsiveness:
///
/// - **Orphan Cleanup**: Closes history entries left open from previous sessions
/// - **Frequent Destinations Rebuild**: Aggregates visit data for suggestions
///
/// ## Usage
///
/// The actor is initialized during app launch but work is deferred until after
/// the first frame renders:
///
/// ```swift
/// // In AppDelegate, after first frame
/// DispatchQueue.main.async {
///     Task {
///         await historyManager.performDeferredMaintenance()
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// Uses `@ModelActor` to ensure all SwiftData operations happen on a dedicated
/// serial executor with its own `ModelContext`. Results are passed back to
/// the main actor's `HistoryManager` via method parameters.
@ModelActor
actor HistoryMaintenanceActor {
    /// Closes history entries that were left open from a previous session.
    ///
    /// When the app starts, any entries with `closedAt == nil` are from tabs that
    /// were open when the app last terminated. This method closes them using their
    /// `lastSeenAt` timestamp as the close time.
    ///
    /// - Returns: Number of entries closed, for logging.
    func closeOrphanedEntries() -> Int {
        let descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { entry in
                entry.closedAt == nil
            },
        )

        do {
            let orphanedEntries = try modelContext.fetch(descriptor)

            guard !orphanedEntries.isEmpty else { return 0 }

            for entry in orphanedEntries {
                let closeTime = entry.lastSeenAt ?? entry.visitedAt
                let timeSpent = closeTime.timeIntervalSince(entry.visitedAt)
                entry.closedAt = closeTime
                entry.timeSpent = max(entry.timeSpent, timeSpent)
            }

            try modelContext.save()
            return orphanedEntries.count
        } catch {
            Logger.error("Failed to close orphaned entries: \(error)", category: Logger.data)
            return 0
        }
    }

    /// Fetches recent history entries for rebuilding the frequent destinations cache.
    ///
    /// Returns the raw entries which will be processed by `FrequentDestinationsCache`
    /// on the main thread.
    ///
    /// - Returns: Array of history entries from the last 90 days.
    func fetchRecentEntriesForFrequentDestinations() -> [FrequentDestinationData] {
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()

        let descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { entry in
                entry.visitedAt >= ninetyDaysAgo
            },
            sortBy: [SortDescriptor(\.visitedAt, order: .reverse)],
        )

        do {
            let entries = try modelContext.fetch(descriptor)
            // Convert to transferable data to avoid passing @Model objects across actors
            return entries.map { entry in
                FrequentDestinationData(
                    domain: entry.domain,
                    url: entry.url,
                    title: entry.title,
                    visitedAt: entry.visitedAt,
                )
            }
        } catch {
            Logger.error("Failed to fetch entries for frequent destinations: \(error)", category: Logger.data)
            return []
        }
    }
}

/// Transferable data for frequent destination cache rebuilding.
///
/// Since `@Model` objects can't cross actor boundaries, we extract the
/// relevant fields into a plain struct for transfer to the main actor.
struct FrequentDestinationData: Sendable {
    let domain: String
    let url: URL
    let title: String?
    let visitedAt: Date
}

// MARK: - Maintenance Operations

extension HistoryMaintenanceActor {
    /// Deletes history entries older than the specified retention period.
    ///
    /// - Parameter retentionDays: Number of days to retain history.
    /// - Returns: Number of entries deleted.
    func cleanOldEntries(retentionDays: Int) -> Int {
        guard retentionDays > 0 else { return 0 }

        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -retentionDays,
            to: Date(),
        ) ?? Date()

        let descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { entry in
                entry.visitedAt < cutoffDate
            },
        )

        do {
            let oldEntries = try modelContext.fetch(descriptor)
            guard !oldEntries.isEmpty else { return 0 }

            for entry in oldEntries {
                modelContext.delete(entry)
            }

            try modelContext.save()
            return oldEntries.count
        } catch {
            Logger.error("Failed to clean old entries: \(error)", category: Logger.data)
            return 0
        }
    }

    /// Deletes snapshots older than the specified retention period.
    ///
    /// - Parameter retentionDays: Number of days to retain snapshots.
    /// - Returns: Number of snapshots deleted.
    func cleanOldSnapshots(retentionDays: Int) -> Int {
        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -retentionDays,
            to: Date(),
        ) ?? Date()

        let descriptor = FetchDescriptor<TabSnapshot>(
            predicate: #Predicate { snapshot in
                snapshot.createdAt < cutoffDate
            },
        )

        do {
            let oldSnapshots = try modelContext.fetch(descriptor)
            guard !oldSnapshots.isEmpty else { return 0 }

            for snapshot in oldSnapshots {
                modelContext.delete(snapshot)
            }

            try modelContext.save()
            return oldSnapshots.count
        } catch {
            Logger.error("Failed to clean old snapshots: \(error)", category: Logger.data)
            return 0
        }
    }

    /// Trims snapshots to the specified maximum count, keeping the most recent.
    ///
    /// - Parameter maxCount: Maximum number of snapshots to keep.
    /// - Returns: Number of snapshots deleted.
    func trimExcessSnapshots(maxCount: Int) -> Int {
        let descriptor = FetchDescriptor<TabSnapshot>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)],
        )

        do {
            let allSnapshots = try modelContext.fetch(descriptor)

            guard allSnapshots.count > maxCount else { return 0 }

            let snapshotsToDelete = Array(allSnapshots.dropFirst(maxCount))

            for snapshot in snapshotsToDelete {
                modelContext.delete(snapshot)
            }

            try modelContext.save()
            return snapshotsToDelete.count
        } catch {
            Logger.error("Failed to trim excess snapshots: \(error)", category: Logger.data)
            return 0
        }
    }
}
