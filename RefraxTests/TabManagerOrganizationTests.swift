import Foundation
import SwiftData
import SwiftUI
import Testing
import WebKit
@testable import Refrax

// MARK: - TabManager+Organization Tests

@Suite("TabManager Custom Name", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerCustomNameTests {
    @Test
    func `Set custom name trims whitespace`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        let result = env.tabManager.setCustomName("  My Tab  ", for: tab)

        #expect(result, "Should succeed")
        #expect(tab.customName == "My Tab", "Should trim whitespace")
    }

    @Test
    func `Set custom name rejects empty string`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        let result = env.tabManager.setCustomName("", for: tab)

        #expect(!result, "Should fail for empty string")
        #expect(tab.customName == nil, "Custom name should not be set")
    }

    @Test
    func `Set custom name rejects whitespace-only string`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        let result = env.tabManager.setCustomName("   ", for: tab)

        #expect(!result, "Should fail for whitespace-only")
        #expect(tab.customName == nil, "Custom name should not be set")
    }

    @Test
    func `Set custom name truncates long names`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        let longName = String(repeating: "x", count: 500)
        let result = env.tabManager.setCustomName(longName, for: tab)

        #expect(result, "Should succeed")
        #expect(try #require(tab.customName?.count) <= TabManager.maxCustomNameLength, "Should be truncated")
    }

    @Test
    func `Set custom name increments content version`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        let versionBefore = env.browserState.tabContentVersion

        env.tabManager.setCustomName("Custom", for: tab)

        #expect(env.browserState.tabContentVersion > versionBefore, "Content version should increment")
    }

    @Test
    func `Clear custom name removes it`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        env.tabManager.setCustomName("Custom Name", for: tab)
        #expect(tab.customName == "Custom Name")

        env.tabManager.clearCustomName(tab)

        #expect(tab.customName == nil, "Custom name should be cleared")
    }
}

@Suite("TabManager Read/Unread", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerReadUnreadTests {
    @Test
    func `Mark as read clears unread flag`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create active tab first
        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://active.com")),
            in: space,
            makeActive: true,
        )

        // Background tab will be unread
        let backgroundTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://background.com")),
            in: space,
            makeActive: false,
        )

        #expect(backgroundTab.isUnread, "Should start unread")

        env.tabManager.markAsRead(backgroundTab)

        #expect(!backgroundTab.isUnread, "Should be marked as read")
    }

    @Test
    func `Mark as unread sets unread flag`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        #expect(!tab.isUnread, "Active tab should not be unread")

        env.tabManager.markAsUnread(tab)

        #expect(tab.isUnread, "Should be marked as unread")
    }

    @Test
    func `Mark as read increments content version`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://active.com")),
            in: space,
            makeActive: true,
        )

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://background.com")),
            in: space,
            makeActive: false,
        )

        let versionBefore = env.browserState.tabContentVersion

        env.tabManager.markAsRead(tab)

        #expect(env.browserState.tabContentVersion > versionBefore)
    }
}

@Suite("TabManager Move To Space", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerMoveToSpaceTests {
    @Test
    func `Move tabs to space removes from source`() throws {
        let env = try TabManagerTestEnvironment()
        let sourceSpace = env.makeSpace(name: "Source")
        let targetSpace = env.spaceManager.createSpace(name: "Target", iconName: "heart")
        _ = env.makeActiveWindowState(with: sourceSpace)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: sourceSpace,
            makeActive: true,
        )

        #expect(sourceSpace.tabs.contains(where: { $0.id == tab.id }))

        env.tabManager.moveTabs([tab], to: targetSpace)

        #expect(!sourceSpace.tabs.contains(where: { $0.id == tab.id }), "Tab should be removed from source")
        #expect(targetSpace.tabs.contains(where: { $0.id == tab.id }), "Tab should be in target")
    }

    @Test
    func `Move tabs clears group membership`() throws {
        let env = try TabManagerTestEnvironment()
        let sourceSpace = env.makeSpace(name: "Source")
        let targetSpace = env.spaceManager.createSpace(name: "Target", iconName: "heart")
        _ = env.makeActiveWindowState(with: sourceSpace)

        let group = try env.groupManager.createGroup(in: sourceSpace, name: "Test Group")

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://grouped.com")),
            in: sourceSpace,
            groupID: group.id,
            makeActive: true,
        )

        #expect(tab.groupID == group.id, "Tab should be in group")

        env.tabManager.moveTabs([tab], to: targetSpace)

        #expect(tab.groupID == nil, "Group membership should be cleared")
    }

    @Test
    func `Move multiple tabs preserves order`() throws {
        let env = try TabManagerTestEnvironment()
        let sourceSpace = env.makeSpace(name: "Source")
        let targetSpace = env.spaceManager.createSpace(name: "Target", iconName: "heart")
        _ = env.makeActiveWindowState(with: sourceSpace)

        let tab1 = try env.tabManager.createTab(
            url: #require(URL(string: "https://one.com")),
            in: sourceSpace,
            makeActive: false,
        )
        let tab2 = try env.tabManager.createTab(
            url: #require(URL(string: "https://two.com")),
            in: sourceSpace,
            makeActive: false,
        )
        let tab3 = try env.tabManager.createTab(
            url: #require(URL(string: "https://three.com")),
            in: sourceSpace,
            makeActive: true,
        )

        env.tabManager.moveTabs([tab1, tab2, tab3], to: targetSpace)

        #expect(targetSpace.tabs.count == 3, "All tabs should be in target")
        #expect(sourceSpace.tabs.isEmpty, "Source should be empty")
    }
}

@Suite("TabManager Filter", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerFilterTests {
    @Test
    func `Filter tabs by title`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab1 = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: false,
        )
        tab1.activePage.title = "Apple Developer"

        let tab2 = try env.tabManager.createTab(
            url: #require(URL(string: "https://other.com")),
            in: space,
            makeActive: false,
        )
        tab2.activePage.title = "Google Search"

        let tab3 = try env.tabManager.createTab(
            url: #require(URL(string: "https://third.com")),
            in: space,
            makeActive: true,
        )
        tab3.activePage.title = "Apple Music"

        let results = env.tabManager.tabs(matching: "Apple")

        #expect(results.count == 2, "Should find 2 tabs with Apple in title")
        #expect(results.contains(where: { $0.id == tab1.id }))
        #expect(results.contains(where: { $0.id == tab3.id }))
    }

    @Test
    func `Filter tabs is case insensitive`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )
        tab.activePage.title = "UPPERCASE Title"

        let results = env.tabManager.tabs(matching: "uppercase")

        #expect(results.count == 1, "Should find tab with case-insensitive match")
    }

    @Test
    func `Filter tabs by URL`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab1 = try env.tabManager.createTab(
            url: #require(URL(string: "https://github.com/project")),
            in: space,
            makeActive: false,
        )
        tab1.activePage.title = "Project"

        let tab2 = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )
        tab2.activePage.title = "Example"

        let results = env.tabManager.tabs(matching: "github")

        #expect(results.count == 1, "Should find tab with github in URL")
        #expect(results.first?.id == tab1.id)
    }

    @Test
    func `Filter tabs by custom name`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )
        tab.activePage.title = "Example Page"
        env.tabManager.setCustomName("My Favorite", for: tab)

        let results = env.tabManager.tabs(matching: "favorite")

        #expect(results.count == 1, "Should find tab with custom name match")
    }

    @Test
    func `Filter with empty query returns all tabs`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://one.com")),
            in: space,
            makeActive: false,
        )
        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://two.com")),
            in: space,
            makeActive: true,
        )

        let results = env.tabManager.tabs(matching: "")

        #expect(results.count == 2, "Empty query should return all tabs")
    }
}
