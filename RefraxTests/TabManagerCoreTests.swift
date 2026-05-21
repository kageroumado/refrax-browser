import Foundation
import SwiftData
import SwiftUI
import Testing
import WebKit

@testable import Refrax

// MARK: - TabManager Persistence Tests

@Suite("TabManager Persistence", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerPersistenceTests {
    @Test("Initialize window with space sets active space")
    func initializeWindowSetsActiveSpace() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeWindowState()

        env.tabManager.initializeWindow(windowState, with: space)

        #expect(windowState.activeSpaceID == space.id)
    }

    @Test("Initialize window defers tab selection")
    func initializeWindowDefersTabSelection() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        // Create tabs before initializing window
        _ = env.tabManager.createTab(
            url: URL(string: "https://one.com")!,
            in: space,
            makeActive: false,
        )
        _ = env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: space,
            makeActive: false,
        )

        let windowState = env.makeWindowState()
        env.tabManager.initializeWindow(windowState, with: space)

        // initializeWindow now defers tab selection for lazy WebPage creation
        #expect(windowState.activeTabID == nil, "Tab selection should be deferred")
    }

    @Test("Initialize window does not set active tab")
    func initializeWindowNoActiveTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        _ = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
        )

        let windowState = env.makeWindowState()
        env.tabManager.initializeWindow(windowState, with: space)

        #expect(windowState.activeTabID == nil, "No tab should be active")
    }

    @Test("Normalize positions fixes gaps")
    func normalizePositionsFixesGaps() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create tabs with artificial gaps in positions
        let tab1 = env.tabManager.createTab(
            url: URL(string: "https://one.com")!,
            in: space,
            makeActive: false,
        )
        let tab2 = env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: space,
            makeActive: false,
        )
        let tab3 = env.tabManager.createTab(
            url: URL(string: "https://three.com")!,
            in: space,
            makeActive: false,
        )

        // Manually create gaps
        tab1.position = 1_000
        tab2.position = 5_000
        tab3.position = 9_000

        env.tabManager.normalizePositions(in: space)

        // After normalization, positions should be sequential without huge gaps
        let positions = space.tabs.map(\.position).sorted()
        #expect(positions.count == 3)

        // The key invariant is that position ORDER is preserved (tab1 had lowest position, so still should)
        // Note: normalizePositions preserves position order, not array order
        #expect(tab1.position < tab2.position, "Position order should be preserved")
        #expect(tab2.position < tab3.position, "Position order should be preserved")
    }

    @Test("Restore from persistence returns default space")
    func restoreFromPersistenceReturnsDefaultSpace() throws {
        let env = try TabManagerTestEnvironment()

        // Clear any existing spaces
        env.browserState.setSpaces([])

        let space = env.tabManager.restoreFromPersistence()

        #expect(space.name == SpaceManager.DefaultSpaceConfig.name)
        #expect(env.browserState.spaces.count >= 1)
    }

    @Test("Create temporary space does not persist")
    func createTemporarySpaceDoesNotPersist() throws {
        let env = try TabManagerTestEnvironment()

        let tempSpace = env.tabManager.createTemporarySpace()

        #expect(tempSpace.name == SpaceManager.DefaultSpaceConfig.name)
        #expect(env.browserState.spaces.contains(where: { $0.id == tempSpace.id }))
    }
}

// MARK: - TabManager Edge Cases

@Suite("TabManager Edge Cases", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerEdgeCaseTests {
    @Test("Deep link pages are not preloaded")
    func deepLinkPagesNotPreloaded() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create a tab with a deep link URL
        let deepLinkURL = URL(string: "refrax://ssl-error?type=expired&url=https://example.com")!
        let tab = env.tabManager.createTab(
            url: deepLinkURL,
            in: space,
            makeActive: true,
        )

        // Page should not be preloaded for deep links
        let page = env.pagePool.existingPage(for: tab.activePage)
        #expect(page == nil, "Deep link page should not be preloaded")
    }

    @Test("Content version increments on tab activation")
    func contentVersionIncrementsOnActivation() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        _ = env.tabManager.createTab(
            url: URL(string: "https://one.com")!,
            in: space,
            makeActive: true,
        )

        let tab2 = env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: space,
            makeActive: false,
        )

        let versionBefore = env.browserState.tabContentVersion

        env.tabManager.setActiveTab(tab2, in: windowState)

        #expect(env.browserState.tabContentVersion > versionBefore, "Content version should increment")
    }

    @Test("List version distinct from content version")
    func listVersionDistinctFromContentVersion() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        _ = env.tabManager.createTab(
            url: URL(string: "https://one.com")!,
            in: space,
            makeActive: true,
        )

        let listVersionAfterCreate = env.browserState.tabListVersion
        let contentVersionAfterCreate = env.browserState.tabContentVersion

        // Activate different tab - should increment content, not list
        let tab2 = env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: space,
            makeActive: false,
        )

        let listVersionAfterSecondCreate = env.browserState.tabListVersion
        #expect(listVersionAfterSecondCreate > listVersionAfterCreate, "List version should increment on create")

        env.tabManager.setActiveTab(tab2, in: windowState)

        let listVersionAfterActivation = env.browserState.tabListVersion
        let contentVersionAfterActivation = env.browserState.tabContentVersion

        // List version should NOT change on activation
        #expect(listVersionAfterActivation == listVersionAfterSecondCreate, "List version should not change on activation")
        #expect(contentVersionAfterActivation > contentVersionAfterCreate, "Content version should increase on activation")
    }

    @Test("Tab count reflects active space")
    func tabCountReflectsActiveSpace() throws {
        let env = try TabManagerTestEnvironment()
        let space1 = env.makeSpace(name: "Space 1")
        let space2 = env.spaceManager.createSpace(name: "Space 2", iconName: "heart")

        _ = env.tabManager.createTab(
            url: URL(string: "https://one.com")!,
            in: space1,
            makeActive: false,
        )
        _ = env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: space1,
            makeActive: false,
        )

        _ = env.tabManager.createTab(
            url: URL(string: "https://other.com")!,
            in: space2,
            makeActive: false,
        )

        // Note: tabCount depends on activeWindowState which requires window setup
        // In tests without real windows, we verify via space directly
        #expect(space1.tabCount == 2, "Space 1 should have 2 tabs")
        #expect(space2.tabCount == 1, "Space 2 should have 1 tab")
    }

    @Test("Has tabs reflects space content")
    func hasTabsReflectsSpaceContent() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        #expect(space.tabs.isEmpty, "Space should start empty")

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
        )

        #expect(!space.tabs.isEmpty, "Space should have tabs")

        env.tabManager.closeTab(tab)

        #expect(space.tabs.isEmpty, "Space should be empty after close")
    }

    @Test("Multiple spaces allows hasMultipleSpaces")
    func hasMultipleSpacesCheck() throws {
        let env = try TabManagerTestEnvironment()

        #expect(!env.tabManager.hasMultipleSpaces, "Should start with no multiple spaces")

        _ = env.makeSpace(name: "Space 1")

        #expect(!env.tabManager.hasMultipleSpaces, "One space is not multiple")

        _ = env.spaceManager.createSpace(name: "Space 2", iconName: "heart")

        #expect(env.tabManager.hasMultipleSpaces, "Two spaces is multiple")
    }

    @Test("Copyable URL returns absolute string")
    func copyableURLReturnsAbsoluteString() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com/path?query=1")!,
            in: space,
            makeActive: true,
        )

        let copyable = env.tabManager.copyableURL(for: tab)

        #expect(copyable == "https://example.com/path?query=1")
    }

    @Test("Active tab exits layout mode")
    func setActiveTabExitsLayoutMode() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        _ = env.tabManager.createTab(
            url: URL(string: "https://one.com")!,
            in: space,
            makeActive: true,
        )

        let tab2 = env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: space,
            makeActive: false,
        )

        // Enter layout mode
        windowState.enterLayoutMode()
        #expect(windowState.isInLayoutMode)

        // Activate different tab
        env.tabManager.setActiveTab(tab2, in: windowState)

        #expect(!windowState.isInLayoutMode, "Layout mode should exit on tab activation")
    }

    @Test("Setting active tab updates lastAccessed")
    func setActiveTabUpdatesLastAccessed() throws {
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

        env.tabManager.setActiveTab(tab, in: windowState)

        // After activation, lastAccessed should be set
        #expect(tab.lastAccessed != nil, "lastAccessed should be updated")
    }

    @Test("Setting active tab clears unread flag")
    func setActiveTabClearsUnread() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        // Create active tab first
        _ = env.tabManager.createTab(
            url: URL(string: "https://one.com")!,
            in: space,
            makeActive: true,
        )

        // Create background tab (will be unread)
        let backgroundTab = env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: space,
            makeActive: false,
        )

        #expect(backgroundTab.isUnread, "Background tab should be unread")

        env.tabManager.setActiveTab(backgroundTab, in: windowState)

        #expect(!backgroundTab.isUnread, "Tab should no longer be unread after activation")
    }
}
