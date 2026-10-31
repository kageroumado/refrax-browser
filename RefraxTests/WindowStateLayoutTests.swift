import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Refrax

// MARK: - WindowState Regression Tests

/// Tests for WindowState functionality that could regress when implementing
/// layout mode (2.11), mini-windows (2.4), and related features.
@Suite("WindowState Regression", .tags(.tabManager), .serialized)
@MainActor
struct WindowStateRegressionTests {
    // MARK: - Active Space Tests

    @Test
    func `WindowState starts with no active space`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(windowState.activeSpaceID == nil)
        #expect(windowState.activeSpace == nil)
    }

    @Test
    func `WindowState activeSpaceID set on switch`() throws {
        let env = try SpaceManagerTestEnvironment()

        let space = env.spaceManager.createSpace(name: "Test", iconName: "star")
        let windowState = env.makeWindowState()

        env.spaceManager.switchToSpaceSync(space, for: windowState)

        #expect(windowState.activeSpaceID == space.id)
    }

    @Test
    func `WindowState activeSpace returns space object`() throws {
        let env = try SpaceManagerTestEnvironment()

        let space = env.spaceManager.createSpace(name: "Test", iconName: "star")
        let windowState = env.makeWindowState()

        env.spaceManager.switchToSpaceSync(space, for: windowState)

        #expect(windowState.activeSpace?.id == space.id)
        #expect(windowState.activeSpace?.name == "Test")
    }

    // MARK: - Active Tab Tests

    @Test
    func `WindowState activeTabID persists per space`() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext

        let space1 = env.makeSpace(name: "Space 1")
        let space2 = env.makeSpace(name: "Space 2")

        let tab1 = try Tab(space: space1, url: #require(URL(string: "https://one.com")))
        let tab2 = try Tab(space: space2, url: #require(URL(string: "https://two.com")))
        context.insert(tab1)
        context.insert(tab2)
        env.browserState.indexTab(tab1)
        env.browserState.indexTab(tab2)

        let windowState = env.makeWindowState()

        // Set active tabs for each space
        env.spaceManager.switchToSpaceSync(space1, for: windowState)
        windowState.setActiveTabID(tab1.id, for: space1.id)

        env.spaceManager.switchToSpaceSync(space2, for: windowState)
        windowState.setActiveTabID(tab2.id, for: space2.id)

        // Switch back and verify
        env.spaceManager.switchToSpaceSync(space1, for: windowState)
        #expect(windowState.activeTabID == tab1.id)

        env.spaceManager.switchToSpaceSync(space2, for: windowState)
        #expect(windowState.activeTabID == tab2.id)
    }

    @Test
    func `WindowState activeTab returns tab object`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://active.com")),
            in: space,
            makeActive: false,
        )
        env.tabManager.setActiveTab(tab, in: windowState)

        #expect(windowState.activeTab?.id == tab.id)
    }

    // MARK: - Layout Mode Tests

    @Test
    func `WindowState isInLayoutMode starts false`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(!windowState.isInLayoutMode)
    }

    @Test
    func `WindowState enterLayoutMode edits the current tab`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)
        let tab = try env.createActiveTab(url: #require(URL(string: "https://one.com")), in: space, for: windowState)

        windowState.enterLayoutMode()

        #expect(windowState.isInLayoutMode)
        #expect(windowState.paneEditor.isEditing(tab: tab.id))
    }

    @Test
    func `WindowState enterLayoutMode without a tab stays off`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.enterLayoutMode()

        #expect(windowState.isInLayoutMode == false)
    }

    @Test
    func `WindowState exitLayoutMode clears flag`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)
        try env.createActiveTab(url: #require(URL(string: "https://one.com")), in: space, for: windowState)

        windowState.enterLayoutMode()
        #expect(windowState.isInLayoutMode)

        windowState.exitLayoutMode()
        #expect(windowState.isInLayoutMode == false)
    }

    @Test
    func `Switching space exits layout mode`() throws {
        let env = try TabManagerTestEnvironment()
        let space1 = env.makeSpace(name: "Space 1")
        let space2 = env.makeSpace(name: "Space 2")
        let windowState = env.makeActiveWindowState(with: space1)
        try env.createActiveTab(url: #require(URL(string: "https://one.com")), in: space1, for: windowState)

        windowState.enterLayoutMode()
        #expect(windowState.isInLayoutMode)

        env.spaceManager.switchToSpaceSync(space2, for: windowState)
        #expect(windowState.isInLayoutMode == false)
    }

    // MARK: - Multiple Windows Tests

    @Test
    func `Multiple WindowStates are independent`() throws {
        let env = try SpaceManagerTestEnvironment()

        let space1 = env.spaceManager.createSpace(name: "Space 1", iconName: "1.circle")
        let space2 = env.spaceManager.createSpace(name: "Space 2", iconName: "2.circle")

        let window1 = env.makeWindowState()
        let window2 = env.makeWindowState()

        env.spaceManager.switchToSpaceSync(space1, for: window1)
        env.spaceManager.switchToSpaceSync(space2, for: window2)

        #expect(window1.activeSpaceID == space1.id)
        #expect(window2.activeSpaceID == space2.id)
    }

    @Test
    func `Multiple windows same space different active tabs`() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext

        let space = env.makeSpace()

        let tab1 = try Tab(space: space, url: #require(URL(string: "https://one.com")))
        let tab2 = try Tab(space: space, url: #require(URL(string: "https://two.com")))
        context.insert(tab1)
        context.insert(tab2)
        env.browserState.indexTab(tab1)
        env.browserState.indexTab(tab2)

        let window1 = env.makeWindowState()
        let window2 = env.makeWindowState()

        env.spaceManager.switchToSpaceSync(space, for: window1)
        env.spaceManager.switchToSpaceSync(space, for: window2)

        window1.setActiveTabID(tab1.id, for: space.id)
        window2.setActiveTabID(tab2.id, for: space.id)

        #expect(window1.activeTabID == tab1.id)
        #expect(window2.activeTabID == tab2.id)
    }
}

// MARK: - WindowState Tab Switching Tests

@Suite("WindowState Tab Switching", .tags(.tabManager), .serialized)
@MainActor
struct WindowStateTabSwitchingTests {
    @Test
    func `Set active tab updates window state`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: false,
        )

        env.tabManager.setActiveTab(tab, in: windowState)

        #expect(windowState.activeTabID == tab.id)
    }
}

// MARK: - WindowState Cleanup Tests

@Suite("WindowState Cleanup", .tags(.tabManager), .serialized)
@MainActor
struct WindowStateCleanupTests {
    @Test
    func `Closing active tab updates window state`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab1 = try env.tabManager.createTab(
            url: #require(URL(string: "https://keep.com")),
            in: space,
            makeActive: false,
        )
        let tab2 = try env.tabManager.createTab(
            url: #require(URL(string: "https://close.com")),
            in: space,
            makeActive: false,
        )

        env.tabManager.setActiveTab(tab2, in: windowState)

        env.tabManager.closeTab(tab2)

        // Should switch to remaining tab
        #expect(windowState.activeTabID == tab1.id)
    }

    @Test
    func `Closing last tab clears active tab ID`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://only.com")),
            in: space,
            makeActive: false,
        )

        env.tabManager.setActiveTab(tab, in: windowState)

        env.tabManager.closeTab(tab)

        #expect(windowState.activeTabID == nil)
    }

    @Test
    func `Deleting active space switches window`() throws {
        let env = try SpaceManagerTestEnvironment()

        let space1 = env.spaceManager.createSpace(name: "Space 1", iconName: "1.circle")
        let space2 = env.spaceManager.createSpace(name: "Space 2", iconName: "2.circle")

        let windowState = env.makeWindowState()
        env.spaceManager.switchToSpaceSync(space2, for: windowState)

        env.spaceManager.deleteSpace(space2, windowState: windowState)

        #expect(windowState.activeSpaceID == space1.id)
    }
}

// MARK: - WindowState Stale Tab ID Tests

@Suite("WindowState Stale Tab Cleanup", .tags(.tabManager), .serialized)
@MainActor
struct WindowStateStaleTabTests {
    @Test
    func `handleTabRemoved clears active tab for space`() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()
        let windowState = env.makeWindowState()

        let tab = try Tab(space: space, url: #require(URL(string: "https://example.com")))
        context.insert(tab)
        env.browserState.indexTab(tab)

        env.spaceManager.switchToSpaceSync(space, for: windowState)
        windowState.setActiveTabID(tab.id, for: space.id)
        #expect(windowState.activeTabID == tab.id)

        windowState.handleTabRemoved(tab.id, from: space.id)
        #expect(windowState.activeTabID == nil)
    }

    @Test
    func `handleTabRemoved clears previous active tab`() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()
        let windowState = env.makeWindowState()

        let tab1 = try Tab(space: space, url: #require(URL(string: "https://one.com")))
        let tab2 = try Tab(space: space, url: #require(URL(string: "https://two.com")))
        context.insert(tab1)
        context.insert(tab2)
        env.browserState.indexTab(tab1)
        env.browserState.indexTab(tab2)

        env.spaceManager.switchToSpaceSync(space, for: windowState)
        windowState.setActiveTabID(tab1.id, for: space.id)
        windowState.setActiveTabID(tab2.id, for: space.id, trackPrevious: true)

        #expect(windowState.previousActiveTabID(for: space.id) == tab1.id)

        windowState.handleTabRemoved(tab1.id, from: space.id)
        #expect(windowState.previousActiveTabID(for: space.id) == nil)
    }

    @Test
    func `handleTabRemoved clears live favorite override`() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()
        let windowState = env.makeWindowState()

        let tab = try Tab(space: nil, url: #require(URL(string: "https://favorite.com")))
        tab.status = .favorite
        context.insert(tab)
        env.browserState.indexTab(tab)

        env.spaceManager.switchToSpaceSync(space, for: windowState)
        windowState.setActiveTab(tab)
        #expect(windowState.isShowingLiveFavorite)

        windowState.handleTabRemoved(tab.id, from: space.id)
        #expect(!windowState.isShowingLiveFavorite)
    }

    @Test
    func `handleTabRemoved does not affect other spaces`() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space1 = env.makeSpace(name: "Space 1")
        let space2 = env.makeSpace(name: "Space 2")
        let windowState = env.makeWindowState()

        let tab1 = try Tab(space: space1, url: #require(URL(string: "https://one.com")))
        let tab2 = try Tab(space: space2, url: #require(URL(string: "https://two.com")))
        context.insert(tab1)
        context.insert(tab2)
        env.browserState.indexTab(tab1)
        env.browserState.indexTab(tab2)

        windowState.setActiveTabID(tab1.id, for: space1.id)
        windowState.setActiveTabID(tab2.id, for: space2.id)

        windowState.handleTabRemoved(tab1.id, from: space1.id)

        env.spaceManager.switchToSpaceSync(space2, for: windowState)
        #expect(windowState.activeTabID == tab2.id)
    }

    @Test
    func `purgeStaleTabIDs removes deleted tabs from all spaces`() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space1 = env.makeSpace(name: "Space 1")
        let space2 = env.makeSpace(name: "Space 2")
        let windowState = env.makeWindowState()

        let tab1 = try Tab(space: space1, url: #require(URL(string: "https://one.com")))
        let tab2 = try Tab(space: space2, url: #require(URL(string: "https://two.com")))
        context.insert(tab1)
        context.insert(tab2)
        env.browserState.indexTab(tab1)
        env.browserState.indexTab(tab2)

        windowState.setActiveTabID(tab1.id, for: space1.id)
        windowState.setActiveTabID(tab2.id, for: space2.id)

        // Simulate tab1 being deleted (removed from index)
        env.browserState.removeFromIndex(tab1)

        windowState.purgeStaleTabIDs()

        env.spaceManager.switchToSpaceSync(space1, for: windowState)
        #expect(windowState.activeTabID == nil)

        env.spaceManager.switchToSpaceSync(space2, for: windowState)
        #expect(windowState.activeTabID == tab2.id)
    }

    @Test
    func `purgeStaleTabIDs preserves valid entries`() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()
        let windowState = env.makeWindowState()

        let tab = try Tab(space: space, url: #require(URL(string: "https://example.com")))
        context.insert(tab)
        env.browserState.indexTab(tab)

        env.spaceManager.switchToSpaceSync(space, for: windowState)
        windowState.setActiveTabID(tab.id, for: space.id)

        windowState.purgeStaleTabIDs()

        #expect(windowState.activeTabID == tab.id)
    }

    @Test
    func `purgeStaleTabIDs clears stale previous tab IDs`() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()
        let windowState = env.makeWindowState()

        let tab1 = try Tab(space: space, url: #require(URL(string: "https://one.com")))
        let tab2 = try Tab(space: space, url: #require(URL(string: "https://two.com")))
        context.insert(tab1)
        context.insert(tab2)
        env.browserState.indexTab(tab1)
        env.browserState.indexTab(tab2)

        env.spaceManager.switchToSpaceSync(space, for: windowState)
        windowState.setActiveTabID(tab1.id, for: space.id)
        windowState.setActiveTabID(tab2.id, for: space.id, trackPrevious: true)

        #expect(windowState.previousActiveTabID(for: space.id) == tab1.id)

        // Simulate tab1 being deleted
        env.browserState.removeFromIndex(tab1)
        windowState.purgeStaleTabIDs()

        #expect(windowState.previousActiveTabID(for: space.id) == nil)
        #expect(windowState.activeTabID == tab2.id)
    }

    @Test
    func `handleTabRemoved is idempotent`() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()
        let windowState = env.makeWindowState()

        let tab = try Tab(space: space, url: #require(URL(string: "https://example.com")))
        context.insert(tab)
        env.browserState.indexTab(tab)

        env.spaceManager.switchToSpaceSync(space, for: windowState)
        windowState.setActiveTabID(tab.id, for: space.id)

        // Calling twice should not crash or change state
        windowState.handleTabRemoved(tab.id, from: space.id)
        windowState.handleTabRemoved(tab.id, from: space.id)

        #expect(windowState.activeTabID == nil)
    }

    @Test
    func `handleTabRemoved with wrong space ID is no-op`() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space1 = env.makeSpace(name: "Space 1")
        let space2 = env.makeSpace(name: "Space 2")
        let windowState = env.makeWindowState()

        let tab = try Tab(space: space1, url: #require(URL(string: "https://example.com")))
        context.insert(tab)
        env.browserState.indexTab(tab)

        env.spaceManager.switchToSpaceSync(space1, for: windowState)
        windowState.setActiveTabID(tab.id, for: space1.id)

        // Remove from wrong space — should not affect space1
        windowState.handleTabRemoved(tab.id, from: space2.id)

        #expect(windowState.activeTabID == tab.id)
    }
}
