import Foundation
import SwiftData
import SwiftUI
import Testing
import WebKit
@testable import Refrax

// MARK: - TabManager Live Favorite Tests

@Suite("TabManager Live Favorites", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerLiveFavoriteTests {
    @Test
    func `Create live favorite tab has no space`() throws {
        let env = try TabManagerTestEnvironment()

        // Create a bookmark first
        let bookmark = try Bookmark(
            url: #require(URL(string: "https://example.com")),
            title: "Example",
        )
        env.modelContext.insert(bookmark)

        let tab = env.tabManager.createLiveFavoriteTab(for: bookmark)

        #expect(tab.space == nil, "Live favorite should not belong to a space")
        #expect(tab.status == .favorite, "Status should be liveFavorite")
        #expect(env.browserState.favoriteTabs.contains(where: { $0.id == tab.id }))
    }

    @Test
    func `Create live favorite tab copies bookmark favicon`() throws {
        let env = try TabManagerTestEnvironment()

        let faviconData = Data([0x89, 0x50, 0x4E, 0x47])
        let bookmark = try Bookmark(
            url: #require(URL(string: "https://example.com")),
            title: "Example",
        )
        bookmark.faviconData = faviconData
        env.modelContext.insert(bookmark)

        let tab = env.tabManager.createLiveFavoriteTab(for: bookmark)

        #expect(tab.activePage.faviconData == faviconData, "Favicon should be copied from bookmark")
    }

    @Test
    func `Create live favorite tab links to bookmark`() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = try Bookmark(
            url: #require(URL(string: "https://example.com")),
            title: "Example",
        )
        env.modelContext.insert(bookmark)

        let tab = env.tabManager.createLiveFavoriteTab(for: bookmark)

        #expect(tab.linkedBookmark?.id == bookmark.id, "Tab should link to bookmark")
    }

    @Test
    func `Close live favorite tab removes from browser state`() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = try Bookmark(
            url: #require(URL(string: "https://example.com")),
            title: "Example",
        )
        env.modelContext.insert(bookmark)

        let tab = env.tabManager.createLiveFavoriteTab(for: bookmark)
        let tabID = tab.id

        #expect(env.browserState.favoriteTabs.contains(where: { $0.id == tabID }))

        env.tabManager.closeLiveFavoriteTab(tab)

        #expect(!env.browserState.favoriteTabs.contains(where: { $0.id == tabID }))
    }

    @Test
    func `Close non-live-favorite as live favorite does nothing`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let normalTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        // This should log a warning and not crash
        env.tabManager.closeLiveFavoriteTab(normalTab)

        // Tab should still exist (wasn't closed)
        #expect(space.tabs.contains(where: { $0.id == normalTab.id }))
    }
}

// MARK: - TabManager Restore Tests

@Suite("TabManager Restore Operations", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerRestoreTests {
    @Test
    func `Restore tab recreates in original space`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )
        tab.activePage.title = "Example Page"

        env.tabManager.closeTab(tab)

        #expect(space.tabs.isEmpty)
        #expect(!env.undoRedoManager.recentlyClosedTabs.isEmpty)

        // Get the closed tab info
        let closedInfo = try #require(env.undoRedoManager.recentlyClosedTabs.first)

        // Restore
        env.tabManager.restoreTab(closedInfo)

        #expect(space.tabs.count == 1, "Tab should be restored")
        #expect(space.tabs.first?.activePage.url.absoluteString == "https://example.com")
    }

    @Test
    func `Restore tab preserves custom name`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )
        tab.customName = "My Custom Name"

        env.tabManager.closeTab(tab)

        let closedInfo = try #require(env.undoRedoManager.recentlyClosedTabs.first)

        #expect(closedInfo.customName == "My Custom Name")

        env.tabManager.restoreTab(closedInfo)

        #expect(space.tabs.first?.customName == "My Custom Name")
    }

    @Test
    func `Restore tab preserves group membership`() throws {
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

        env.tabManager.closeTab(tab)

        let closedInfo = try #require(env.undoRedoManager.recentlyClosedTabs.first)
        #expect(closedInfo.groupID == group.id)

        env.tabManager.restoreTab(closedInfo)

        let restoredTab = try #require(space.tabs.first)
        #expect(restoredTab.groupID == group.id, "Group membership should be restored")
        #expect(group.tabs.contains(where: { $0.id == restoredTab.id }), "Group should contain restored tab")
    }

    @Test
    func `Reopen last closed tab restores most recent`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

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

        env.tabManager.closeTab(tab1)
        env.tabManager.closeTab(tab2)

        #expect(space.tabs.isEmpty)

        // Reopen last closed (should be tab2)
        env.tabManager.reopenLastClosedTab()

        #expect(space.tabs.count == 1)
        #expect(space.tabs.first?.activePage.url.absoluteString == "https://two.com")
    }
}

// MARK: - TabManager Request Close Tests

@Suite("TabManager Request Close", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerRequestCloseTests {
    @Test
    func `Request close with no warnings closes immediately`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        env.tabManager.requestCloseTab(tab)

        // Tab should be closed immediately (no pending confirmation)
        #expect(env.tabManager.pendingCloseConfirmation == nil)
        #expect(space.tabs.isEmpty)
    }

    @Test
    func `Cancel close clears pending confirmation`() throws {
        let env = try TabManagerTestEnvironment()

        // Manually set pending confirmation to test cancel
        env.tabManager.pendingCloseConfirmation = TabManager.CloseConfirmation(
            tabs: [],
            reasons: [],
            allTabsToClose: [],
        )

        env.tabManager.cancelCloseTabs()

        #expect(env.tabManager.pendingCloseConfirmation == nil)
    }

    @Test
    func `Request close multiple tabs processes all`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab1 = try env.tabManager.createTab(
            url: #require(URL(string: "https://one.com")),
            in: space,
            makeActive: false,
        )
        let tab2 = try env.tabManager.createTab(
            url: #require(URL(string: "https://two.com")),
            in: space,
            makeActive: false,
        )
        let tab3 = try env.tabManager.createTab(
            url: #require(URL(string: "https://three.com")),
            in: space,
            makeActive: true,
        )

        env.tabManager.requestCloseTabs([tab1, tab2, tab3])

        // All tabs should be closed (no media/capture warnings)
        #expect(space.tabs.isEmpty)
    }
}
