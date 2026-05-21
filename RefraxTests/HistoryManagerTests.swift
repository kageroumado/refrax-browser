import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for HistoryManager operations.
    @Tag static var historyManager: Self
}

// MARK: - HistoryManager Recording Tests

@Suite("HistoryManager Recording", .tags(.historyManager), .serialized)
@MainActor
struct HistoryManagerRecordingTests {
    @Test("Record navigation creates entry")
    func recordNavigationCreatesEntry() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            title: "Example",
            tabID: tabID,
        )

        #expect(entry != nil)
        #expect(entry?.title == "Example")
        #expect(entry?.tabID == tabID)
    }

    @Test("Record navigation normalizes URL by removing www")
    func recordNavigationNormalizesWWW() throws {
        let env = try TabManagerTestEnvironment()

        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://www.example.com")),
            tabID: UUID(),
        )

        #expect(entry?.url.host == "example.com")
    }

    @Test("Record navigation normalizes URL by removing trailing slash")
    func recordNavigationNormalizesTrailingSlash() throws {
        let env = try TabManagerTestEnvironment()

        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com/")),
            tabID: UUID(),
        )

        #expect(entry?.url.path == "" || entry?.url.path == nil)
    }

    @Test("Record navigation normalizes search query for DuckDuckGo")
    func recordNavigationNormalizesDuckDuckGo() throws {
        let env = try TabManagerTestEnvironment()

        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://duckduckgo.com/?q=swift&ia=web&t=trackingparam")),
            tabID: UUID(),
        )

        // Should keep only 'q' parameter
        #expect(entry?.url.query == "q=swift")
    }

    @Test("Record navigation normalizes search query for Google")
    func recordNavigationNormalizesGoogle() throws {
        let env = try TabManagerTestEnvironment()

        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://www.google.com/search?q=swift&hl=en&client=safari")),
            tabID: UUID(),
        )

        #expect(entry?.url.query == "q=swift")
    }

    @Test("Record navigation with space ID")
    func recordNavigationWithSpaceID() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            tabID: UUID(),
            spaceID: space.id,
        )

        #expect(entry?.spaceID == space.id)
    }

    @Test("Record navigation skips private space")
    func recordNavigationSkipsPrivateSpace() throws {
        let env = try TabManagerTestEnvironment()
        let privateSpace = env.makeSpace(name: "Private")
        privateSpace.dataStoreMode = .private

        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            tabID: UUID(),
            spaceID: privateSpace.id,
            isPrivateSpace: true,
        )

        #expect(entry == nil, "Should not record in private space")
    }

    @Test("Record navigation with parent entry")
    func recordNavigationWithParent() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        let parent = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://parent.com")),
            tabID: tabID,
        )

        let child = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://child.com")),
            tabID: UUID(),
            parentEntry: parent,
        )

        #expect(child?.parent?.id == parent?.id)
    }
}

// MARK: - HistoryManager Update Tests

@Suite("HistoryManager Update", .tags(.historyManager), .serialized)
@MainActor
struct HistoryManagerUpdateTests {
    @Test("Update entry title")
    func updateEntryTitle() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            title: "Loading...",
            tabID: tabID,
        )

        env.historyManager.updateEntry(for: tabID, title: "Example Site")

        #expect(entry?.title == "Example Site")
    }

    @Test("Update entry is no-op for unknown tab")
    func updateEntryUnknownTab() throws {
        let env = try TabManagerTestEnvironment()

        // Should not crash
        env.historyManager.updateEntry(for: UUID(), title: "Test")
    }

    @Test("Mark entry failed")
    func markEntryFailed() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            tabID: tabID,
        )

        env.historyManager.markEntryFailed(for: tabID, statusCode: 404)

        #expect(entry?.failedToLoad == true)
        #expect(entry?.httpStatusCode == 404)
    }

    @Test("Close entry records time spent")
    func closeEntryRecordsTimeSpent() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            tabID: tabID,
        )

        env.historyManager.closeEntry(for: tabID, timeSpent: 120.0)

        #expect(entry?.closedAt != nil)
        #expect(entry?.timeSpent == 120.0)
    }

    @Test("Close entry removes from active entries")
    func closeEntryRemovesFromActive() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            tabID: tabID,
        )

        #expect(env.historyManager.activeEntry(for: tabID) != nil)

        env.historyManager.closeEntry(for: tabID, timeSpent: 10.0)

        #expect(env.historyManager.activeEntry(for: tabID) == nil)
    }

    @Test("Add time spent")
    func addTimeSpent() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            tabID: tabID,
        )

        env.historyManager.addTimeSpent(for: tabID, duration: 30.0)
        env.historyManager.addTimeSpent(for: tabID, duration: 20.0)

        #expect(entry?.timeSpent == 50.0)
    }

    @Test("Update last seen")
    func updateLastSeen() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            tabID: tabID,
        )

        let initialLastSeen = entry?.lastSeenAt

        // Sleep briefly to ensure time difference
        Thread.sleep(forTimeInterval: 0.01)

        env.historyManager.updateLastSeen(for: tabID)

        #expect(entry?.lastSeenAt != nil)
        if let initial = initialLastSeen, let updated = entry?.lastSeenAt {
            #expect(updated >= initial)
        }
    }
}

// MARK: - HistoryManager Query Tests

@Suite("HistoryManager Query", .tags(.historyManager), .serialized)
@MainActor
struct HistoryManagerQueryTests {
    @Test("Search by title")
    func searchByTitle() async throws {
        let env = try TabManagerTestEnvironment()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://swift.org")),
            title: "Swift Programming Language",
            tabID: UUID(),
        )
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            title: "Example Site",
            tabID: UUID(),
        )

        // Initialize query actor for async searches
        try env.modelContext.save()
        await env.historyManager.performDeferredMaintenance(modelContainer: env.modelContainer)

        let results = await env.historyManager.search(query: "swift")

        #expect(results.count == 1)
        #expect(results.first?.title == "Swift Programming Language")
    }

    @Test("Search by URL")
    func searchByURL() async throws {
        let env = try TabManagerTestEnvironment()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://github.com/apple/swift")),
            title: "Swift Repo",
            tabID: UUID(),
        )
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            title: "Example",
            tabID: UUID(),
        )

        try env.modelContext.save()
        await env.historyManager.performDeferredMaintenance(modelContainer: env.modelContainer)

        let results = await env.historyManager.search(query: "github")

        #expect(results.count == 1)
    }

    @Test("Search is case insensitive")
    func searchCaseInsensitive() async throws {
        let env = try TabManagerTestEnvironment()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            title: "UPPERCASE TITLE",
            tabID: UUID(),
        )

        try env.modelContext.save()
        await env.historyManager.performDeferredMaintenance(modelContainer: env.modelContainer)

        let results = await env.historyManager.search(query: "uppercase")

        #expect(results.count == 1)
    }

    @Test("Search respects limit")
    func searchRespectsLimit() async throws {
        let env = try TabManagerTestEnvironment()

        for i in 0 ..< 10 {
            _ = try env.historyManager.recordNavigation(
                url: #require(URL(string: "https://site\(i).com")),
                title: "Site \(i)",
                tabID: UUID(),
            )
        }

        try env.modelContext.save()
        await env.historyManager.performDeferredMaintenance(modelContainer: env.modelContainer)

        let results = await env.historyManager.search(query: "site", limit: 3)

        #expect(results.count == 3)
    }

    @Test("Get entries by date range")
    func entriesByDateRange() async throws {
        let env = try TabManagerTestEnvironment()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://today.com")),
            title: "Today",
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

    @Test("Get entries by domain")
    func entriesByDomain() async throws {
        let env = try TabManagerTestEnvironment()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com/page1")),
            title: "Page 1",
            tabID: UUID(),
        )
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com/page2")),
            title: "Page 2",
            tabID: UUID(),
        )
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://other.com")),
            title: "Other",
            tabID: UUID(),
        )

        try env.modelContext.save()
        await env.historyManager.performDeferredMaintenance(modelContainer: env.modelContainer)

        let results = await env.historyManager.entries(forDomain: "example.com")

        #expect(results.count == 2)
    }

    @Test("Get active entry for tab")
    func activeEntryForTab() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            tabID: tabID,
        )

        let active = env.historyManager.activeEntry(for: tabID)

        #expect(active != nil)
        #expect(active?.tabID == tabID)
    }
}

// MARK: - HistoryManager Cleanup Tests

@Suite("HistoryManager Cleanup", .tags(.historyManager), .serialized)
@MainActor
struct HistoryManagerCleanupTests {
    @Test("Delete entries before date")
    func deleteEntriesBeforeDate() throws {
        let env = try TabManagerTestEnvironment()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com")),
            title: "Today",
            tabID: UUID(),
        )

        // Delete entries before tomorrow (should delete today's entry)
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: Date()))
        env.historyManager.deleteEntriesBefore(date: tomorrow)

        let count = env.historyManager.totalEntryCount()
        #expect(count == 0)
    }

    @Test("Delete entries for domain")
    func deleteEntriesForDomain() async throws {
        let env = try TabManagerTestEnvironment()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com/page1")),
            title: "Page 1",
            tabID: UUID(),
        )
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example.com/page2")),
            title: "Page 2",
            tabID: UUID(),
        )
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://keep.com")),
            title: "Keep",
            tabID: UUID(),
        )

        try env.modelContext.save()
        await env.historyManager.performDeferredMaintenance(modelContainer: env.modelContainer)

        env.historyManager.deleteEntries(forDomain: "example.com")

        let remainingByDomain = await env.historyManager.entries(forDomain: "example.com")
        #expect(remainingByDomain.isEmpty)

        let kept = await env.historyManager.entries(forDomain: "keep.com")
        #expect(kept.count == 1)
    }

    @Test("Clear all history")
    func clearAllHistory() throws {
        let env = try TabManagerTestEnvironment()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example1.com")),
            tabID: UUID(),
        )
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://example2.com")),
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
}

// MARK: - HistoryManager Statistics Tests

@Suite("HistoryManager Statistics", .tags(.historyManager), .serialized)
@MainActor
struct HistoryManagerStatisticsTests {
    @Test("Total entry count")
    func totalEntryCount() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.historyManager.totalEntryCount() == 0)

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://one.com")),
            tabID: UUID(),
        )
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://two.com")),
            tabID: UUID(),
        )

        #expect(env.historyManager.totalEntryCount() == 2)
    }

    @Test("Total time spent")
    func totalTimeSpent() async throws {
        let env = try TabManagerTestEnvironment()

        let tabID1 = UUID()
        let tabID2 = UUID()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://one.com")),
            tabID: tabID1,
        )
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://two.com")),
            tabID: tabID2,
        )

        env.historyManager.closeEntry(for: tabID1, timeSpent: 100.0)
        env.historyManager.closeEntry(for: tabID2, timeSpent: 50.0)

        try env.modelContext.save()
        await env.historyManager.performDeferredMaintenance(modelContainer: env.modelContainer)

        let total = await env.historyManager.totalTimeSpent()
        #expect(total == 150.0)
    }

    @Test("Statistics ignore private space entries")
    func statisticsIgnorePrivateSpace() throws {
        let env = try TabManagerTestEnvironment()
        let privateSpace = env.makeSpace(name: "Private")
        privateSpace.dataStoreMode = .private

        // Record in normal space
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://normal.com")),
            tabID: UUID(),
        )

        // Try to record in private space (should be skipped)
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://private.com")),
            tabID: UUID(),
            spaceID: privateSpace.id,
            isPrivateSpace: true,
        )

        // Only the normal entry should be counted
        #expect(env.historyManager.totalEntryCount() == 1)
    }

    @Test("All domains returns unique sorted list")
    func allDomainsUniqueSorted() async throws {
        let env = try TabManagerTestEnvironment()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://zebra.com")),
            tabID: UUID(),
        )
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://apple.com")),
            tabID: UUID(),
        )
        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://apple.com/other")),
            tabID: UUID(),
        )

        try env.modelContext.save()
        await env.historyManager.performDeferredMaintenance(modelContainer: env.modelContainer)

        let domains = await env.historyManager.allDomains()

        #expect(domains.count == 2) // apple.com and zebra.com
        #expect(domains.first == "apple.com") // Sorted
        #expect(domains.last == "zebra.com")
    }
}

// MARK: - HistoryManager Frequent Destinations Tests

@Suite("HistoryManager Frequent Destinations", .tags(.historyManager), .serialized)
@MainActor
struct HistoryManagerFrequentDestinationsTests {
    @Test("Frequent destinations updated on navigation")
    func frequentDestinationsUpdated() throws {
        let env = try TabManagerTestEnvironment()

        // Record multiple visits to same URL
        for _ in 0 ..< 5 {
            _ = try env.historyManager.recordNavigation(
                url: #require(URL(string: "https://frequent.com")),
                title: "Frequent Site",
                tabID: UUID(),
            )
        }

        let destinations = env.historyManager.frequentDestinations.topDestinations()

        #expect(!destinations.isEmpty)
        #expect(destinations.first?.url.host == "frequent.com")
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
}

// MARK: - HistoryManager Edge Cases

@Suite("HistoryManager Edge Cases", .tags(.historyManager), .serialized)
@MainActor
struct HistoryManagerEdgeCaseTests {
    @Test("Multiple navigations same tab updates active entry")
    func multipleNavigationsSameTab() throws {
        let env = try TabManagerTestEnvironment()
        let tabID = UUID()

        let entry1 = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://first.com")),
            tabID: tabID,
        )

        let entry2 = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://second.com")),
            tabID: tabID,
        )

        // Both entries should be created (different navigations)
        #expect(entry1?.url.host != entry2?.url.host)

        // Active entry should be the latest
        let active = env.historyManager.activeEntry(for: tabID)
        #expect(active?.url.host == "second.com")
    }

    @Test("Close entry is no-op for unknown tab")
    func closeEntryUnknownTab() throws {
        let env = try TabManagerTestEnvironment()

        // Should not crash
        env.historyManager.closeEntry(for: UUID(), timeSpent: 10.0)
    }

    @Test("Mark entry failed is no-op for unknown tab")
    func markEntryFailedUnknownTab() throws {
        let env = try TabManagerTestEnvironment()

        // Should not crash
        env.historyManager.markEntryFailed(for: UUID(), statusCode: 500)
    }

    @Test("Delete entries for domains handles multiple domains")
    func deleteEntriesForDomains() throws {
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
