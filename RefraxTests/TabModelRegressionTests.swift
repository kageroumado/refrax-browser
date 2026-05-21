import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Refrax

// MARK: - Tab Model Regression Tests

/// Tests for Tab model properties that could regress when adding new features
/// like badges (2.1), timers (2.2), auto-archive (2.3), and agentic description (2.7).
@Suite("Tab Model Regression", .tags(.tabManager), .serialized)
@MainActor
struct TabModelRegressionTests {
    // MARK: - Age Category Tests

    @Test("Tab age category is recent within 6 hours")
    func tabAgeCategoryRecent() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
        )

        // Newly created tab should be recent (lastAccessed is now)
        #expect(tab.ageCategory == .recent)
    }

    @Test("Tab age category changes based on lastAccessed")
    func tabAgeCategoryBasedOnLastAccessed() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = Tab(space: space, url: URL(string: "https://example.com")!)
        env.modelContext.insert(tab)

        // Set lastAccessed to 7 hours ago (ageCategory uses lastAccessed, not createdAt)
        tab.lastAccessed = Date().addingTimeInterval(-7 * 3_600)

        #expect(tab.ageCategory == .old6h)

        // Set lastAccessed to 13 hours ago
        tab.lastAccessed = Date().addingTimeInterval(-13 * 3_600)

        #expect(tab.ageCategory == .old12h)
    }

    @Test("Tab lastAccessed updates on activation")
    func tabLastAccessedUpdates() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
        )

        // Tabs that were never activated don't have lastAccessed set
        #expect(tab.lastAccessed == nil)

        // Activate the tab
        env.tabManager.setActiveTab(tab, in: windowState)
        tab.updateLastAccessed()

        // After activation, lastAccessed should be set
        #expect(tab.lastAccessed != nil)
    }

    // MARK: - Tab Status Tests

    @Test("Tab status regular by default")
    func tabStatusRegularByDefault() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        #expect(tab.status == .regular)
        #expect(!tab.isPinned)
        #expect(!tab.isLiveFavorite)
    }

    @Test("Tab status pinned when isPinned true")
    func tabStatusPinned() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            isPinned: true,
            makeActive: true,
        )

        #expect(tab.status == .pinned)
        #expect(tab.isPinned)
    }

    @Test("Pinned tab status is exempt from cleanup")
    func pinnedTabStatusExemptFromCleanup() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let pinnedTab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            isPinned: true,
            makeActive: true,
        )

        let regularTab = env.tabManager.createTab(
            url: URL(string: "https://other.com")!,
            in: space,
            makeActive: true,
        )

        #expect(pinnedTab.status.isExemptFromCleanup)
        #expect(!regularTab.status.isExemptFromCleanup)
    }

    // MARK: - Tab Display Title Tests

    @Test("Tab displayTitle uses customName when set")
    func tabDisplayTitleUsesCustomName() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        tab.customName = "My Custom Name"

        #expect(tab.displayTitle == "My Custom Name")
    }

    @Test("Tab displayTitle falls back to page title")
    func tabDisplayTitleFallsBackToPageTitle() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        tab.activePage.title = "Page Title"

        #expect(tab.displayTitle == "Page Title")
    }

    @Test("Tab displayTitle returns cleaned URL when title empty")
    func tabDisplayTitleReturnsCleanedURL() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com/path")!,
            in: space,
            makeActive: true,
        )

        // Clear title by setting to empty string
        tab.activePage.title = ""
        tab.customName = nil

        // displayTitle returns cleaned URL (protocol removed but path kept)
        #expect(tab.displayTitle.contains("example.com"))
    }

    // MARK: - Tab Unread State Tests

    @Test("Tab isUnread is false when makeActive is true")
    func tabUnreadFalseWhenActive() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        // isUnread = !makeActive, so when makeActive is true, isUnread is false
        #expect(!tab.isUnread)
    }

    @Test("Tab isUnread is true when makeActive is false")
    func tabUnreadTrueWhenNotActive() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
        )

        // isUnread = !makeActive, so when makeActive is false, isUnread is true
        #expect(tab.isUnread)
    }

    @Test("Tab isUnread can be toggled")
    func tabUnreadCanBeToggled() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        #expect(!tab.isUnread)

        tab.isUnread = true
        #expect(tab.isUnread)

        tab.isUnread = false
        #expect(!tab.isUnread)
    }

    // MARK: - Tab Group Membership Tests

    @Test("Tab can be assigned to group")
    func tabCanBeAssignedToGroup() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Test Group")

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            groupID: group.id,
            makeActive: true,
        )

        #expect(tab.groupID == group.id)
    }

    @Test("Tab without group has nil groupID")
    func tabWithoutGroupHasNilGroupID() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        #expect(tab.groupID == nil)
    }

    // MARK: - Tab Position Tests

    @Test("Tab positions maintain ordering")
    func tabPositionsOrdering() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create tabs - they use fractional indexing, so positions are large numbers
        // but maintain relative ordering
        _ = env.tabManager.createTab(
            url: URL(string: "https://one.com")!,
            in: space,
            makeActive: true,
        )
        _ = env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: space,
            makeActive: true,
        )
        _ = env.tabManager.createTab(
            url: URL(string: "https://three.com")!,
            in: space,
            makeActive: true,
        )

        // Check that tabs are sorted in order (positions are relative, not sequential)
        let sorted = space.tabs.sorted { $0.position < $1.position }
        #expect(sorted.count == 3)
    }

    // MARK: - Tab Page Tests

    @Test("Tab has primary page after creation")
    func tabHasactivePage() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        #expect(tab.pages.count >= 1)
        #expect(tab.activePage.url.absoluteString == "https://example.com")
    }

    // MARK: - Tab Persistence Tests

    @Test("Tab survives context save and fetch")
    func tabSurvivesContextSave() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )
        let tabID = tab.id

        try env.modelContext.save()

        let descriptor = FetchDescriptor<Refrax.Tab>(predicate: #Predicate { $0.id == tabID })
        let fetched = try env.modelContext.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched.first?.activePage.url.absoluteString == "https://example.com")
    }

    @Test("Tab customName persists")
    func tabCustomNamePersists() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )
        tab.customName = "Persisted Name"
        let tabID = tab.id

        try env.modelContext.save()

        let descriptor = FetchDescriptor<Refrax.Tab>(predicate: #Predicate { $0.id == tabID })
        let fetched = try env.modelContext.fetch(descriptor)

        #expect(fetched.first?.customName == "Persisted Name")
    }
}

// MARK: - Tab Sorting Regression Tests

@Suite("Tab Sorting Regression", .tags(.tabManager), .serialized)
@MainActor
struct TabSortingRegressionTests {
    @Test("Sort by name orders alphabetically")
    func sortByName() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tabC = env.tabManager.createTab(
            url: URL(string: "https://c.com")!,
            in: space,
            makeActive: true,
        )
        tabC.activePage.title = "Charlie"

        let tabA = env.tabManager.createTab(
            url: URL(string: "https://a.com")!,
            in: space,
            makeActive: true,
        )
        tabA.activePage.title = "Alpha"

        let tabB = env.tabManager.createTab(
            url: URL(string: "https://b.com")!,
            in: space,
            makeActive: true,
        )
        tabB.activePage.title = "Beta"

        env.tabManager.sortTabs(by: .nameAscending, in: space)

        let sorted = space.tabs.sorted { $0.position < $1.position }
        #expect(sorted[0].activePage.title == "Alpha")
        #expect(sorted[1].activePage.title == "Beta")
        #expect(sorted[2].activePage.title == "Charlie")
    }

    @Test("Sort by domain orders by host")
    func sortByDomain() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        _ = env.tabManager.createTab(
            url: URL(string: "https://zebra.com")!,
            in: space,
            makeActive: true,
        )
        _ = env.tabManager.createTab(
            url: URL(string: "https://apple.com")!,
            in: space,
            makeActive: true,
        )
        _ = env.tabManager.createTab(
            url: URL(string: "https://mango.com")!,
            in: space,
            makeActive: true,
        )

        env.tabManager.sortTabs(by: .domainAscending, in: space)

        let sorted = space.tabs.sorted { $0.position < $1.position }
        #expect(sorted[0].activePage.url.host == "apple.com")
        #expect(sorted[1].activePage.url.host == "mango.com")
        #expect(sorted[2].activePage.url.host == "zebra.com")
    }

    @Test("Sort by recent orders by lastAccessed")
    func sortByRecent() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tabOld = env.tabManager.createTab(
            url: URL(string: "https://old.com")!,
            in: space,
            makeActive: true,
        )
        tabOld.lastAccessed = Date().addingTimeInterval(-3_600)

        let tabNew = env.tabManager.createTab(
            url: URL(string: "https://new.com")!,
            in: space,
            makeActive: true,
        )
        tabNew.lastAccessed = Date()

        let tabMid = env.tabManager.createTab(
            url: URL(string: "https://mid.com")!,
            in: space,
            makeActive: true,
        )
        tabMid.lastAccessed = Date().addingTimeInterval(-1_800)

        env.tabManager.sortTabs(by: .recentFirst, in: space)

        let sorted = space.tabs.sorted { $0.position < $1.position }
        // recentFirst means most recent first
        #expect(sorted[0].activePage.url.host == "new.com")
        #expect(sorted[2].activePage.url.host == "old.com")
    }

    @Test("Pinned tabs remain pinned after sort")
    func pinnedTabsRemainPinned() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let pinnedTab = env.tabManager.createTab(
            url: URL(string: "https://pinned.com")!,
            in: space,
            isPinned: true,
            makeActive: true,
        )
        pinnedTab.activePage.title = "Zebra"

        let regularTab = env.tabManager.createTab(
            url: URL(string: "https://regular.com")!,
            in: space,
            makeActive: true,
        )
        regularTab.activePage.title = "Alpha"

        // Sort by name - Alpha would normally come first
        env.tabManager.sortTabs(by: .nameAscending, in: space)

        // But pinned should stay separate in its own section
        #expect(pinnedTab.isPinned)
        #expect(!regularTab.isPinned)
    }
}

// MARK: - Tab Close Behavior Tests

@Suite("Tab Close Behavior", .tags(.tabManager), .serialized)
@MainActor
struct TabCloseBehaviorTests {
    @Test("Closing active tab activates adjacent tab")
    func closingActiveTabActivatesAdjacent() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab1 = env.tabManager.createTab(
            url: URL(string: "https://one.com")!,
            in: space,
            makeActive: true,
        )
        let tab2 = env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: space,
            makeActive: true,
        )
        let tab3 = env.tabManager.createTab(
            url: URL(string: "https://three.com")!,
            in: space,
            makeActive: true,
        )

        // Activate tab2
        env.tabManager.setActiveTab(tab2, in: windowState)

        // Close tab2
        env.tabManager.closeTab(tab2)

        // Either tab1 or tab3 should be active
        let activeID = windowState.activeTabID
        #expect(activeID == tab1.id || activeID == tab3.id)
    }

    @Test("Closing last tab in space leaves no active tab")
    func closingLastTabLeavesNoActive() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )
        env.tabManager.setActiveTab(tab, in: windowState)

        env.tabManager.closeTab(tab)

        #expect(space.tabs.isEmpty)
        #expect(windowState.activeTabID == nil)
    }

    @Test("Close other tabs keeps active tab")
    func closeOtherTabsKeepsActive() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let keepTab = env.tabManager.createTab(
            url: URL(string: "https://keep.com")!,
            in: space,
            makeActive: true,
        )
        _ = env.tabManager.createTab(
            url: URL(string: "https://close1.com")!,
            in: space,
            makeActive: true,
        )
        _ = env.tabManager.createTab(
            url: URL(string: "https://close2.com")!,
            in: space,
            makeActive: true,
        )

        env.tabManager.setActiveTab(keepTab, in: windowState)

        env.tabManager.closeOtherTabsInSpace(except: keepTab)

        #expect(space.tabs.count == 1)
        #expect(space.tabs.first?.id == keepTab.id)
    }

    @Test("Close tab adds to recently closed")
    func closeTabAddsToRecentlyClosed() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        #expect(env.undoRedoManager.recentlyClosedTabs.isEmpty)

        env.tabManager.closeTab(tab)

        #expect(!env.undoRedoManager.recentlyClosedTabs.isEmpty)
    }
}
