import Foundation
import SwiftData

/// Background actor for expensive HistoryManager read queries.
///
/// History recording stays on the main thread (hot path), but expensive read
/// queries like search, mostVisited, and date range queries are performed here
/// to avoid blocking navigation recording during History panel usage.
@ModelActor
actor HistoryQueryActor {
    // MARK: - Search

    /// Search history by query string.
    ///
    /// Uses the indexed `searchableText` field for efficient database-level
    /// filtering instead of loading all entries into memory.
    func search(query: String, limit: Int = 50) -> [HistoryEntryData] {
        let lowercasedQuery = query.lowercased()

        var descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { entry in
                entry.searchableText.contains(lowercasedQuery)
            },
            sortBy: [SortDescriptor(\.visitedAt, order: .reverse)],
        )
        descriptor.fetchLimit = limit

        do {
            let entries = try modelContext.fetch(descriptor)
            return entries.map { HistoryEntryData(from: $0) }
        } catch {
            Logger.error("Failed to search history: \(error)", category: Logger.data)
            return []
        }
    }

    // MARK: - Date Range Queries

    /// Get history entries within a date range.
    func entries(from startDate: Date, to endDate: Date) -> [HistoryEntryData] {
        let descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { entry in
                entry.visitedAt >= startDate && entry.visitedAt <= endDate
            },
            sortBy: [SortDescriptor(\.visitedAt, order: .reverse)],
        )

        do {
            let entries = try modelContext.fetch(descriptor)
            return entries.map { HistoryEntryData(from: $0) }
        } catch {
            Logger.error("Failed to fetch history entries: \(error)", category: Logger.data)
            return []
        }
    }

    // MARK: - Aggregation Queries

    /// Get most visited URLs (grouped by URL, sorted by visit count).
    ///
    /// Fetches entries from the last 90 days and groups by URL to count visits.
    /// This is an expensive operation that fetches all entries from the period.
    func mostVisited(limit: Int = 20) -> [HistoryEntryData] {
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()

        let descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { entry in
                entry.visitedAt >= ninetyDaysAgo
            },
            sortBy: [SortDescriptor(\.visitedAt, order: .reverse)],
        )

        do {
            let recentEntries = try modelContext.fetch(descriptor)

            // Group by URL and count visits
            var urlCounts: [URL: (count: Int, latestEntry: HistoryEntry)] = [:]
            for entry in recentEntries {
                if let existing = urlCounts[entry.url] {
                    urlCounts[entry.url] = (existing.count + 1, existing.latestEntry)
                } else {
                    urlCounts[entry.url] = (1, entry)
                }
            }

            // Sort by count descending, then by recency
            let sorted = urlCounts.values
                .sorted { lhs, rhs in
                    if lhs.count != rhs.count {
                        return lhs.count > rhs.count
                    }
                    return lhs.latestEntry.visitedAt > rhs.latestEntry.visitedAt
                }
                .prefix(limit)
                .map { HistoryEntryData(from: $0.latestEntry) }

            return Array(sorted)
        } catch {
            Logger.error("Failed to fetch most visited: \(error)", category: Logger.data)
            return []
        }
    }

    // MARK: - Domain Queries

    /// Get entries for a specific domain.
    func entries(forDomain domain: String) -> [HistoryEntryData] {
        let descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { entry in
                entry.domain == domain
            },
            sortBy: [SortDescriptor(\.visitedAt, order: .reverse)],
        )

        do {
            let entries = try modelContext.fetch(descriptor)
            return entries.map { HistoryEntryData(from: $0) }
        } catch {
            Logger.error("Failed to fetch entries for domain: \(error)", category: Logger.data)
            return []
        }
    }

    /// Get all unique domains in history from the last year.
    func allDomains() -> [String] {
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()

        let descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { entry in
                entry.visitedAt >= oneYearAgo
            },
        )

        do {
            let entries = try modelContext.fetch(descriptor)
            return Array(Set(entries.map(\.domain))).sorted()
        } catch {
            Logger.error("Failed to fetch domains: \(error)", category: Logger.data)
            return []
        }
    }

    // MARK: - Statistics

    /// Get total time spent browsing (paginated to avoid memory issues).
    func totalTimeSpent() -> TimeInterval {
        var total: TimeInterval = 0
        var offset = 0
        let batchSize = 1_000

        do {
            while true {
                var descriptor = FetchDescriptor<HistoryEntry>()
                descriptor.fetchLimit = batchSize
                descriptor.fetchOffset = offset

                let batch = try modelContext.fetch(descriptor)
                if batch.isEmpty { break }

                total += batch.reduce(0) { $0 + $1.timeSpent }
                offset += batch.count

                if batch.count < batchSize { break }
            }
            return total
        } catch {
            Logger.error("Failed to calculate total time spent: \(error)", category: Logger.data)
            return 0
        }
    }

    /// Get total time spent on a domain for a specific date.
    func timeSpent(on domain: String, for date: Date) -> TimeInterval {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return 0
        }

        let descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { entry in
                entry.domain == domain &&
                    entry.visitedAt >= startOfDay &&
                    entry.visitedAt < endOfDay
            },
        )

        do {
            let entries = try modelContext.fetch(descriptor)
            return entries.reduce(0) { $0 + $1.timeSpent }
        } catch {
            Logger.error("Failed to calculate time spent on domain: \(error)", category: Logger.data)
            return 0
        }
    }

    // MARK: - Snapshot Queries

    /// Get snapshots within a date range.
    func snapshots(from startDate: Date, to endDate: Date) -> [TabSnapshotData] {
        let descriptor = FetchDescriptor<TabSnapshot>(
            predicate: #Predicate { snapshot in
                snapshot.createdAt >= startDate &&
                    snapshot.createdAt <= endDate
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)],
        )

        do {
            let snapshots = try modelContext.fetch(descriptor)
            return snapshots.map { TabSnapshotData(from: $0) }
        } catch {
            Logger.error("Failed to fetch snapshots: \(error)", category: Logger.data)
            return []
        }
    }
}

// MARK: - Sendable Data Transfer Types

/// Sendable snapshot of HistoryEntry for cross-actor transfer.
///
/// Marked nonisolated to opt out of implicit MainActor isolation.
nonisolated struct HistoryEntryData: Sendable, Identifiable {
    let id: UUID
    let url: URL
    let title: String?
    let domain: String
    let visitedAt: Date
    let closedAt: Date?
    let timeSpent: TimeInterval
    let faviconURL: URL?
    let failedToLoad: Bool
    let httpStatusCode: Int?
    let spaceID: UUID?
    let isImported: Bool

    init(from entry: HistoryEntry) {
        self.id = entry.id
        self.url = entry.url
        self.title = entry.title
        self.domain = entry.domain
        self.visitedAt = entry.visitedAt
        self.closedAt = entry.closedAt
        self.timeSpent = entry.timeSpent
        self.faviconURL = entry.faviconURL
        self.failedToLoad = entry.failedToLoad
        self.httpStatusCode = entry.httpStatusCode
        self.spaceID = entry.spaceID
        self.isImported = entry.isImported
    }
}

/// Sendable snapshot of TabSnapshot for cross-actor transfer.
///
/// Marked nonisolated to opt out of implicit MainActor isolation.
nonisolated struct TabSnapshotData: Sendable, Identifiable {
    let id: UUID
    let createdAt: Date
    let spaceID: UUID?
    let activeTabID: UUID?
    let items: [TabSnapshotItemData]
    let contentHash: String

    init(from snapshot: TabSnapshot) {
        self.id = snapshot.id
        self.createdAt = snapshot.createdAt
        self.spaceID = snapshot.spaceID
        self.activeTabID = snapshot.activeTabID
        self.items = snapshot.items.map { TabSnapshotItemData(from: $0) }
        self.contentHash = snapshot.contentHash
    }
}

/// Sendable snapshot of TabSnapshotItem for cross-actor transfer.
nonisolated struct TabSnapshotItemData: Sendable {
    let tabID: UUID
    let url: URL
    let title: String
    let position: Int
    let isPinned: Bool
    let groupID: UUID?
    let customName: String?
    let faviconData: Data?

    init(from item: TabSnapshotItem) {
        self.tabID = item.tabID
        self.url = item.url
        self.title = item.title ?? item.url.host ?? ""
        self.position = item.position
        self.isPinned = item.isPinned
        self.groupID = item.groupID
        self.customName = item.customName
        self.faviconData = item.faviconData
    }
}
