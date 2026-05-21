import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Refrax

// MARK: - History Snapshot Regression Tests

/// Tests for history functionality that could regress when implementing
/// history snapshots (3.4), reading time estimation (2.15), and related features.
@Suite("History Snapshot Regression", .tags(.historyManager), .serialized)
@MainActor
struct HistorySnapshotRegressionTests {
    // MARK: - Entry Time Tracking Tests

    @Test("History entry tracks time spent")
    func historyEntryTracksTimeSpent() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            tabID: tabID,
        )

        env.historyManager.addTimeSpent(for: tabID, duration: 60.0)

        #expect(entry?.timeSpent == 60.0)
    }

    @Test("History entry accumulates time spent")
    func historyEntryAccumulatesTimeSpent() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            tabID: tabID,
        )

        env.historyManager.addTimeSpent(for: tabID, duration: 30.0)
        env.historyManager.addTimeSpent(for: tabID, duration: 45.0)

        #expect(entry?.timeSpent == 75.0)
    }

    @Test("History entry records closedAt on close")
    func historyEntryRecordsClosedAt() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            tabID: tabID,
        )

        #expect(entry?.closedAt == nil)

        env.historyManager.closeEntry(for: tabID, timeSpent: 100.0)

        #expect(entry?.closedAt != nil)
    }

    @Test("Closed entry has final time spent")
    func closedEntryHasFinalTimeSpent() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            tabID: tabID,
        )

        // closeEntry ADDS to existing timeSpent, so 50 + 200 = 250
        env.historyManager.addTimeSpent(for: tabID, duration: 50.0)
        env.historyManager.closeEntry(for: tabID, timeSpent: 200.0)

        #expect(entry?.timeSpent == 250.0)
    }

    // MARK: - Last Seen Tests

    @Test("Last seen updates on update call")
    func lastSeenUpdatesOnUpdate() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            tabID: tabID,
        )

        let initialLastSeen = entry?.lastSeenAt

        // Small delay
        Thread.sleep(forTimeInterval: 0.01)

        env.historyManager.updateLastSeen(for: tabID)

        if let initial = initialLastSeen, let updated = entry?.lastSeenAt {
            #expect(updated >= initial)
        }
    }

    // MARK: - Failed Navigation Tests

    @Test("Failed navigation marked with status code")
    func failedNavigationMarked() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            tabID: tabID,
        )

        #expect(entry?.failedToLoad == false)

        env.historyManager.markEntryFailed(for: tabID, statusCode: 404)

        #expect(entry?.failedToLoad == true)
        #expect(entry?.httpStatusCode == 404)
    }

    @Test("Different status codes recorded")
    func differentStatusCodes() throws {
        let env = try TabManagerTestEnvironment()

        let tabID1 = UUID()
        let entry1 = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://notfound.com")),
            tabID: tabID1,
        )
        env.historyManager.markEntryFailed(for: tabID1, statusCode: 404)

        let tabID2 = UUID()
        let entry2 = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://error.com")),
            tabID: tabID2,
        )
        env.historyManager.markEntryFailed(for: tabID2, statusCode: 500)

        #expect(entry1?.httpStatusCode == 404)
        #expect(entry2?.httpStatusCode == 500)
    }

    // MARK: - Parent-Child Relationship Tests

    @Test("History entry can have parent")
    func historyEntryCanHaveParent() throws {
        let env = try TabManagerTestEnvironment()

        let parentEntry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://parent.com")),
            tabID: UUID(),
        )

        let childEntry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://child.com")),
            tabID: UUID(),
            parentEntry: parentEntry,
        )

        #expect(childEntry?.parent?.id == parentEntry?.id)
    }

    // MARK: - Active Entry Tests

    @Test("Active entry returned for active tab")
    func activeEntryForActiveTab() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            tabID: tabID,
        )

        let active = env.historyManager.activeEntry(for: tabID)

        #expect(active != nil)
    }

    @Test("No active entry for closed tab")
    func noActiveEntryForClosedTab() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            tabID: tabID,
        )

        env.historyManager.closeEntry(for: tabID, timeSpent: 0)

        let active = env.historyManager.activeEntry(for: tabID)

        #expect(active == nil)
    }

    @Test("Multiple navigations same tab chain active entries")
    func multipleNavigationsSameTabChain() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://first.com")),
            tabID: tabID,
        )

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://second.com")),
            tabID: tabID,
        )

        let active = env.historyManager.activeEntry(for: tabID)

        #expect(active?.url.host == "second.com")
    }

    // MARK: - Total Time Spent Tests

    @Test("Total time spent across all entries")
    func totalTimeSpentAcrossEntries() async throws {
        let env = try TabManagerTestEnvironment()

        let tabID1 = UUID()
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://one.com")),
            tabID: tabID1,
        )
        env.historyManager.closeEntry(for: tabID1, timeSpent: 100.0)

        let tabID2 = UUID()
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://two.com")),
            tabID: tabID2,
        )
        env.historyManager.closeEntry(for: tabID2, timeSpent: 150.0)

        try env.modelContext.save()
        await env.historyManager.performDeferredMaintenance(modelContainer: env.modelContainer)

        let total = await env.historyManager.totalTimeSpent()

        #expect(total == 250.0)
    }

    // MARK: - Domain Query Tests

    @Test("Entries for domain returns all matching")
    func entriesForDomainReturnsAll() async throws {
        let env = try TabManagerTestEnvironment()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com/page1")),
            tabID: UUID(),
        )
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com/page2")),
            tabID: UUID(),
        )
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://other.com")),
            tabID: UUID(),
        )

        try env.modelContext.save()
        await env.historyManager.performDeferredMaintenance(modelContainer: env.modelContainer)

        let results = await env.historyManager.entries(forDomain: "example.com")

        #expect(results.count == 2)
    }

    @Test("Delete entries for domain removes correct ones")
    func deleteEntriesForDomainRemoves() async throws {
        let env = try TabManagerTestEnvironment()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://delete.com/page1")),
            tabID: UUID(),
        )
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://keep.com/page")),
            tabID: UUID(),
        )

        try env.modelContext.save()
        await env.historyManager.performDeferredMaintenance(modelContainer: env.modelContainer)

        env.historyManager.deleteEntries(forDomain: "delete.com")

        let deleted = await env.historyManager.entries(forDomain: "delete.com")
        let kept = await env.historyManager.entries(forDomain: "keep.com")

        #expect(deleted.isEmpty)
        #expect(kept.count == 1)
    }

    // MARK: - All Domains Tests

    @Test("All domains returns unique sorted")
    func allDomainsUniqueSorted() async throws {
        let env = try TabManagerTestEnvironment()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://zebra.com")),
            tabID: UUID(),
        )
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://apple.com/path1")),
            tabID: UUID(),
        )
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://apple.com/path2")),
            tabID: UUID(),
        )

        try env.modelContext.save()
        await env.historyManager.performDeferredMaintenance(modelContainer: env.modelContainer)

        let domains = await env.historyManager.allDomains()

        #expect(domains.count == 2)
        #expect(domains.first == "apple.com")
        #expect(domains.last == "zebra.com")
    }

    // MARK: - Date Range Query Tests

    @Test("Entries in date range returns correct entries")
    func entriesInDateRangeCorrect() async throws {
        let env = try TabManagerTestEnvironment()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://today.com")),
            tabID: UUID(),
        )

        try env.modelContext.save()
        await env.historyManager.performDeferredMaintenance(modelContainer: env.modelContainer)

        let now = Date()
        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: now))
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: now))

        let results = await env.historyManager.entries(from: yesterday, to: tomorrow)

        #expect(!results.isEmpty)
    }
}

// MARK: - Frequent Destinations Tests

@Suite("Frequent Destinations Regression", .tags(.historyManager), .serialized)
@MainActor
struct FrequentDestinationsRegressionTests {
    @Test("Frequent destinations updated on navigation")
    func frequentDestinationsUpdated() throws {
        let env = try TabManagerTestEnvironment()

        for _ in 0 ..< 5 {
            _ = try env.historyManager.recordNavigation(
                url: #require(URL(string: "https://frequent.com")),
                title: "Frequent Site",
                tabID: UUID(),
            )
        }

        let destinations = env.historyManager.frequentDestinations.topDestinations()

        #expect(!destinations.isEmpty)
    }

    @Test("Frequent destinations cleared with history")
    func frequentDestinationsClearedWithHistory() throws {
        let env = try TabManagerTestEnvironment()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            tabID: UUID(),
        )

        env.historyManager.clearAllHistory()

        let destinations = env.historyManager.frequentDestinations.topDestinations()

        #expect(destinations.isEmpty)
    }

    @Test("Top destinations limited to count")
    func topDestinationsLimited() throws {
        let env = try TabManagerTestEnvironment()

        for i in 0 ..< 20 {
            for _ in 0 ..< (20 - i) {
                _ = try env.historyManager.recordNavigation(
                    url: #require(URL(string: "https://site\(i).com")),
                    tabID: UUID(),
                )
            }
        }

        let destinations = env.historyManager.frequentDestinations.topDestinations(limit: 5)

        #expect(destinations.count <= 5)
    }
}

// MARK: - History Cleanup Tests

@Suite("History Cleanup Regression", .tags(.historyManager), .serialized)
@MainActor
struct HistoryCleanupRegressionTests {
    @Test("Clear all history removes all entries")
    func clearAllHistoryRemovesAll() throws {
        let env = try TabManagerTestEnvironment()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://one.com")),
            tabID: UUID(),
        )
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://two.com")),
            tabID: UUID(),
        )

        #expect(env.historyManager.totalEntryCount() == 2)

        env.historyManager.clearAllHistory()

        #expect(env.historyManager.totalEntryCount() == 0)
    }

    @Test("Clear all history clears active entries")
    func clearAllHistoryClearsActive() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            tabID: tabID,
        )

        #expect(env.historyManager.activeEntry(for: tabID) != nil)

        env.historyManager.clearAllHistory()

        #expect(env.historyManager.activeEntry(for: tabID) == nil)
    }

    @Test("Delete entries before date removes old entries")
    func deleteEntriesBeforeDateRemovesOld() throws {
        let env = try TabManagerTestEnvironment()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://today.com")),
            tabID: UUID(),
        )

        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: Date()))
        env.historyManager.deleteEntriesBefore(date: tomorrow)

        #expect(env.historyManager.totalEntryCount() == 0)
    }

    @Test("Delete entries for multiple domains")
    func deleteEntriesForMultipleDomains() throws {
        let env = try TabManagerTestEnvironment()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://delete1.com")),
            tabID: UUID(),
        )
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://delete2.com")),
            tabID: UUID(),
        )
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://keep.com")),
            tabID: UUID(),
        )

        env.historyManager.deleteEntries(forDomains: ["delete1.com", "delete2.com"])

        #expect(env.historyManager.totalEntryCount() == 1)
    }
}
