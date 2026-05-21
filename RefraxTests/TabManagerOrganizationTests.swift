import Foundation
import SwiftData
import SwiftUI
import Testing
import WebKit

@testable import Refrax

// MARK: - TabManager+Organization Tests

@Suite("TabManager Pin Operations", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerPinTests {
    @Test("Toggle pin on normal tab pins it")
    func togglePinNormalTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        #expect(!tab.isPinned, "Tab should start unpinned")

        env.tabManager.togglePinTab(tab)

        #expect(tab.isPinned, "Tab should now be pinned")
        #expect(tab.status == .pinned, "Status should be pinned")
    }

    @Test("Toggle pin on pinned tab unpins it")
    func togglePinPinnedTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            isPinned: true,
            makeActive: true,
        )

        #expect(tab.isPinned, "Tab should start pinned")

        env.tabManager.togglePinTab(tab)

        #expect(!tab.isPinned, "Tab should now be unpinned")
    }

    @Test("Toggle pin on group tab does nothing")
    func togglePinGroupTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Test Group")

        let tab = env.tabManager.createTab(
            url: URL(string: "https://grouped.com")!,
            in: space,
            groupID: group.id,
            makeActive: true,
        )

        #expect(tab.groupID == group.id, "Tab should be in group")
        #expect(!tab.isPinned, "Tab should start unpinned")

        env.tabManager.togglePinTab(tab)

        #expect(!tab.isPinned, "Group tab should remain unpinned")
    }

    @Test("Pin moves tab to pinned section")
    func pinMovesToPinnedSection() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create some normal tabs first
        let normalTab1 = env.tabManager.createTab(
            url: URL(string: "https://one.com")!,
            in: space,
            makeActive: false,
        )
        let normalTab2 = env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: space,
            makeActive: false,
        )
        let tabToPin = env.tabManager.createTab(
            url: URL(string: "https://three.com")!,
            in: space,
            makeActive: true,
        )

        env.tabManager.togglePinTab(tabToPin)

        // Pinned tab should come before normal tabs
        let pinnedIndex = space.tabs.firstIndex(of: tabToPin)!
        let normalIndex1 = space.tabs.firstIndex(of: normalTab1)!
        let normalIndex2 = space.tabs.firstIndex(of: normalTab2)!

        #expect(pinnedIndex < normalIndex1, "Pinned tab should be before normal tabs")
        #expect(pinnedIndex < normalIndex2, "Pinned tab should be before normal tabs")
    }

    @Test("Unpin moves tab to unpinned section")
    func unpinMovesToUnpinnedSection() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create pinned tab first
        let pinnedTab = env.tabManager.createTab(
            url: URL(string: "https://pinned.com")!,
            in: space,
            isPinned: true,
            makeActive: false,
        )

        // Create normal tabs
        let normalTab = env.tabManager.createTab(
            url: URL(string: "https://normal.com")!,
            in: space,
            makeActive: true,
        )

        #expect(space.tabs.firstIndex(of: pinnedTab)! < space.tabs.firstIndex(of: normalTab)!)

        env.tabManager.togglePinTab(pinnedTab)

        // Now unpinned, should be in unpinned section
        #expect(!pinnedTab.isPinned)
    }
}

@Suite("TabManager Custom Name", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerCustomNameTests {
    @Test("Set custom name trims whitespace")
    func setCustomNameTrims() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        let result = env.tabManager.setCustomName("  My Tab  ", for: tab)

        #expect(result, "Should succeed")
        #expect(tab.customName == "My Tab", "Should trim whitespace")
    }

    @Test("Set custom name rejects empty string")
    func setCustomNameRejectsEmpty() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        let result = env.tabManager.setCustomName("", for: tab)

        #expect(!result, "Should fail for empty string")
        #expect(tab.customName == nil, "Custom name should not be set")
    }

    @Test("Set custom name rejects whitespace-only string")
    func setCustomNameRejectsWhitespace() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        let result = env.tabManager.setCustomName("   ", for: tab)

        #expect(!result, "Should fail for whitespace-only")
        #expect(tab.customName == nil, "Custom name should not be set")
    }

    @Test("Set custom name truncates long names")
    func setCustomNameTruncates() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        let longName = String(repeating: "x", count: 500)
        let result = env.tabManager.setCustomName(longName, for: tab)

        #expect(result, "Should succeed")
        #expect(tab.customName!.count <= TabManager.maxCustomNameLength, "Should be truncated")
    }

    @Test("Set custom name increments content version")
    func setCustomNameIncrementsVersion() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        let versionBefore = env.browserState.tabContentVersion

        env.tabManager.setCustomName("Custom", for: tab)

        #expect(env.browserState.tabContentVersion > versionBefore, "Content version should increment")
    }

    @Test("Clear custom name removes it")
    func clearCustomNameRemoves() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
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
    @Test("Mark as read clears unread flag")
    func markAsReadClearsFlag() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create active tab first
        _ = env.tabManager.createTab(
            url: URL(string: "https://active.com")!,
            in: space,
            makeActive: true,
        )

        // Background tab will be unread
        let backgroundTab = env.tabManager.createTab(
            url: URL(string: "https://background.com")!,
            in: space,
            makeActive: false,
        )

        #expect(backgroundTab.isUnread, "Should start unread")

        env.tabManager.markAsRead(backgroundTab)

        #expect(!backgroundTab.isUnread, "Should be marked as read")
    }

    @Test("Mark as unread sets unread flag")
    func markAsUnreadSetsFlag() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        #expect(!tab.isUnread, "Active tab should not be unread")

        env.tabManager.markAsUnread(tab)

        #expect(tab.isUnread, "Should be marked as unread")
    }

    @Test("Mark as read increments content version")
    func markAsReadIncrementsVersion() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        _ = env.tabManager.createTab(
            url: URL(string: "https://active.com")!,
            in: space,
            makeActive: true,
        )

        let tab = env.tabManager.createTab(
            url: URL(string: "https://background.com")!,
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
    @Test("Move tabs to space removes from source")
    func moveTabsRemovesFromSource() throws {
        let env = try TabManagerTestEnvironment()
        let sourceSpace = env.makeSpace(name: "Source")
        let targetSpace = env.spaceManager.createSpace(name: "Target", iconName: "heart")
        _ = env.makeActiveWindowState(with: sourceSpace)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: sourceSpace,
            makeActive: true,
        )

        #expect(sourceSpace.tabs.contains(where: { $0.id == tab.id }))

        env.tabManager.moveTabs([tab], to: targetSpace)

        #expect(!sourceSpace.tabs.contains(where: { $0.id == tab.id }), "Tab should be removed from source")
        #expect(targetSpace.tabs.contains(where: { $0.id == tab.id }), "Tab should be in target")
    }

    @Test("Move tabs clears group membership")
    func moveTabsClearsGroup() throws {
        let env = try TabManagerTestEnvironment()
        let sourceSpace = env.makeSpace(name: "Source")
        let targetSpace = env.spaceManager.createSpace(name: "Target", iconName: "heart")
        _ = env.makeActiveWindowState(with: sourceSpace)

        let group = try env.groupManager.createGroup(in: sourceSpace, name: "Test Group")

        let tab = env.tabManager.createTab(
            url: URL(string: "https://grouped.com")!,
            in: sourceSpace,
            groupID: group.id,
            makeActive: true,
        )

        #expect(tab.groupID == group.id, "Tab should be in group")

        env.tabManager.moveTabs([tab], to: targetSpace)

        #expect(tab.groupID == nil, "Group membership should be cleared")
    }

    @Test("Move tabs clears pinned status")
    func moveTabsClearsPinned() throws {
        let env = try TabManagerTestEnvironment()
        let sourceSpace = env.makeSpace(name: "Source")
        let targetSpace = env.spaceManager.createSpace(name: "Target", iconName: "heart")
        _ = env.makeActiveWindowState(with: sourceSpace)

        let pinnedTab = env.tabManager.createTab(
            url: URL(string: "https://pinned.com")!,
            in: sourceSpace,
            isPinned: true,
            makeActive: true,
        )

        #expect(pinnedTab.isPinned, "Tab should start pinned")

        env.tabManager.moveTabs([pinnedTab], to: targetSpace)

        #expect(!pinnedTab.isPinned, "Tab should be unpinned after move")
    }

    @Test("Move multiple tabs preserves order")
    func moveMultipleTabsPreservesOrder() throws {
        let env = try TabManagerTestEnvironment()
        let sourceSpace = env.makeSpace(name: "Source")
        let targetSpace = env.spaceManager.createSpace(name: "Target", iconName: "heart")
        _ = env.makeActiveWindowState(with: sourceSpace)

        let tab1 = env.tabManager.createTab(
            url: URL(string: "https://one.com")!,
            in: sourceSpace,
            makeActive: false,
        )
        let tab2 = env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: sourceSpace,
            makeActive: false,
        )
        let tab3 = env.tabManager.createTab(
            url: URL(string: "https://three.com")!,
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
    @Test("Filter tabs by title")
    func filterByTitle() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab1 = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
        )
        tab1.activePage.title = "Apple Developer"

        let tab2 = env.tabManager.createTab(
            url: URL(string: "https://other.com")!,
            in: space,
            makeActive: false,
        )
        tab2.activePage.title = "Google Search"

        let tab3 = env.tabManager.createTab(
            url: URL(string: "https://third.com")!,
            in: space,
            makeActive: true,
        )
        tab3.activePage.title = "Apple Music"

        let results = env.tabManager.tabs(matching: "Apple")

        #expect(results.count == 2, "Should find 2 tabs with Apple in title")
        #expect(results.contains(where: { $0.id == tab1.id }))
        #expect(results.contains(where: { $0.id == tab3.id }))
    }

    @Test("Filter tabs is case insensitive")
    func filterCaseInsensitive() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )
        tab.activePage.title = "UPPERCASE Title"

        let results = env.tabManager.tabs(matching: "uppercase")

        #expect(results.count == 1, "Should find tab with case-insensitive match")
    }

    @Test("Filter tabs by URL")
    func filterByURL() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab1 = env.tabManager.createTab(
            url: URL(string: "https://github.com/project")!,
            in: space,
            makeActive: false,
        )
        tab1.activePage.title = "Project"

        let tab2 = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )
        tab2.activePage.title = "Example"

        let results = env.tabManager.tabs(matching: "github")

        #expect(results.count == 1, "Should find tab with github in URL")
        #expect(results.first?.id == tab1.id)
    }

    @Test("Filter tabs by custom name")
    func filterByCustomName() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )
        tab.activePage.title = "Example Page"
        env.tabManager.setCustomName("My Favorite", for: tab)

        let results = env.tabManager.tabs(matching: "favorite")

        #expect(results.count == 1, "Should find tab with custom name match")
    }

    @Test("Filter with empty query returns all tabs")
    func filterEmptyQueryReturnsAll() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        _ = env.tabManager.createTab(
            url: URL(string: "https://one.com")!,
            in: space,
            makeActive: false,
        )
        _ = env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: space,
            makeActive: true,
        )

        let results = env.tabManager.tabs(matching: "")

        #expect(results.count == 2, "Empty query should return all tabs")
    }
}
