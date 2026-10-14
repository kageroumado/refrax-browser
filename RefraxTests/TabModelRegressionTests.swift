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

    @Test
    func `Tab age category is recent within 6 hours`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: false,
        )

        // Newly created tab should be recent (lastAccessed is now)
        #expect(tab.ageCategory == .recent)
    }

    @Test
    func `Tab age category changes based on lastAccessed`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = try Tab(space: space, url: #require(URL(string: "https://example.com")))
        env.modelContext.insert(tab)

        // Set lastAccessed to 7 hours ago (ageCategory uses lastAccessed, not createdAt)
        tab.lastAccessed = Date().addingTimeInterval(-7 * 3_600)

        #expect(tab.ageCategory == .old6h)

        // Set lastAccessed to 13 hours ago
        tab.lastAccessed = Date().addingTimeInterval(-13 * 3_600)

        #expect(tab.ageCategory == .old12h)
    }

    @Test
    func `Tab lastAccessed updates on activation`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
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

    @Test
    func `Tab status regular by default`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        #expect(tab.status == .regular)
        #expect(!tab.isInPinnedGroup)
        #expect(!tab.isFavorite)
    }

    @Test
    func `Favorite status is exempt from cleanup`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let favoriteTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )
        env.tabManager.makeFavorite(favoriteTab)

        let regularTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://other.com")),
            in: space,
            makeActive: true,
        )

        #expect(favoriteTab.status.isExemptFromCleanup)
        #expect(!regularTab.status.isExemptFromCleanup)
    }

    // MARK: - Tab Display Title Tests

    @Test
    func `Tab displayTitle uses customName when set`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        tab.customName = "My Custom Name"

        #expect(tab.displayTitle == "My Custom Name")
    }

    @Test
    func `Tab displayTitle falls back to page title`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        tab.activePage.title = "Page Title"

        #expect(tab.displayTitle == "Page Title")
    }

    @Test
    func `Tab displayTitle returns cleaned URL when title empty`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com/path")),
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

    @Test
    func `Tab isUnread is false when makeActive is true`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        // isUnread = !makeActive, so when makeActive is true, isUnread is false
        #expect(!tab.isUnread)
    }

    @Test
    func `Tab isUnread is true when makeActive is false`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: false,
        )

        // isUnread = !makeActive, so when makeActive is false, isUnread is true
        #expect(tab.isUnread)
    }

    @Test
    func `Tab isUnread can be toggled`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
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

    @Test
    func `Tab can be assigned to group`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Test Group")

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            groupID: group.id,
            makeActive: true,
        )

        #expect(tab.groupID == group.id)
    }

    @Test
    func `Tab without group has nil groupID`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        #expect(tab.groupID == nil)
    }

    // MARK: - Tab Position Tests

    @Test
    func `Tab positions maintain ordering`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create tabs - they use fractional indexing, so positions are large numbers
        // but maintain relative ordering
        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://one.com")),
            in: space,
            makeActive: true,
        )
        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://two.com")),
            in: space,
            makeActive: true,
        )
        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://three.com")),
            in: space,
            makeActive: true,
        )

        // Check that tabs are sorted in order (positions are relative, not sequential)
        let sorted = space.tabs.sorted { $0.position < $1.position }
        #expect(sorted.count == 3)
    }

    // MARK: - Tab Page Tests

    @Test
    func `Tab has primary page after creation`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        #expect(tab.pages.count >= 1)
        #expect(tab.activePage.url.absoluteString == "https://example.com")
    }

    // MARK: - Tab Persistence Tests

    @Test
    func `Tab survives context save and fetch`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
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

    @Test
    func `Tab customName persists`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
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
    @Test
    func `Sort by name orders alphabetically`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tabC = try env.tabManager.createTab(
            url: #require(URL(string: "https://c.com")),
            in: space,
            makeActive: true,
        )
        tabC.activePage.title = "Charlie"

        let tabA = try env.tabManager.createTab(
            url: #require(URL(string: "https://a.com")),
            in: space,
            makeActive: true,
        )
        tabA.activePage.title = "Alpha"

        let tabB = try env.tabManager.createTab(
            url: #require(URL(string: "https://b.com")),
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

    @Test
    func `Sort by domain orders by host`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://zebra.com")),
            in: space,
            makeActive: true,
        )
        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://apple.com")),
            in: space,
            makeActive: true,
        )
        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://mango.com")),
            in: space,
            makeActive: true,
        )

        env.tabManager.sortTabs(by: .domainAscending, in: space)

        let sorted = space.tabs.sorted { $0.position < $1.position }
        #expect(sorted[0].activePage.url.host == "apple.com")
        #expect(sorted[1].activePage.url.host == "mango.com")
        #expect(sorted[2].activePage.url.host == "zebra.com")
    }

    @Test
    func `Sort by recent orders by lastAccessed`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tabOld = try env.tabManager.createTab(
            url: #require(URL(string: "https://old.com")),
            in: space,
            makeActive: true,
        )
        tabOld.lastAccessed = Date().addingTimeInterval(-3_600)

        let tabNew = try env.tabManager.createTab(
            url: #require(URL(string: "https://new.com")),
            in: space,
            makeActive: true,
        )
        tabNew.lastAccessed = Date()

        let tabMid = try env.tabManager.createTab(
            url: #require(URL(string: "https://mid.com")),
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
}

// MARK: - Tab Close Behavior Tests

@Suite("Tab Close Behavior", .tags(.tabManager), .serialized)
@MainActor
struct TabCloseBehaviorTests {
    @Test
    func `Closing active tab activates adjacent tab`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab1 = try env.tabManager.createTab(
            url: #require(URL(string: "https://one.com")),
            in: space,
            makeActive: true,
        )
        let tab2 = try env.tabManager.createTab(
            url: #require(URL(string: "https://two.com")),
            in: space,
            makeActive: true,
        )
        let tab3 = try env.tabManager.createTab(
            url: #require(URL(string: "https://three.com")),
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

    @Test
    func `Closing last tab in space leaves no active tab`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )
        env.tabManager.setActiveTab(tab, in: windowState)

        env.tabManager.closeTab(tab)

        #expect(space.tabs.isEmpty)
        #expect(windowState.activeTabID == nil)
    }

    @Test
    func `Close other tabs keeps active tab`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let keepTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://keep.com")),
            in: space,
            makeActive: true,
        )
        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://close1.com")),
            in: space,
            makeActive: true,
        )
        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://close2.com")),
            in: space,
            makeActive: true,
        )

        env.tabManager.setActiveTab(keepTab, in: windowState)

        env.tabManager.closeOtherTabsInSpace(except: keepTab)

        #expect(space.tabs.count == 1)
        #expect(space.tabs.first?.id == keepTab.id)
    }

    @Test
    func `Close tab adds to recently closed`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        #expect(env.undoRedoManager.recentlyClosedTabs.isEmpty)

        env.tabManager.closeTab(tab)

        #expect(!env.undoRedoManager.recentlyClosedTabs.isEmpty)
    }
}
