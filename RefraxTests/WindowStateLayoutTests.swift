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

    @Test("WindowState starts with no active space")
    func windowStateStartsNoActiveSpace() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(windowState.activeSpaceID == nil)
        #expect(windowState.activeSpace == nil)
    }

    @Test("WindowState activeSpaceID set on switch")
    func windowStateActiveSpaceIDSet() throws {
        let env = try SpaceManagerTestEnvironment()

        let space = env.spaceManager.createSpace(name: "Test", iconName: "star")
        let windowState = env.makeWindowState()

        env.spaceManager.switchToSpaceSync(space, for: windowState)

        #expect(windowState.activeSpaceID == space.id)
    }

    @Test("WindowState activeSpace returns space object")
    func windowStateActiveSpaceReturns() throws {
        let env = try SpaceManagerTestEnvironment()

        let space = env.spaceManager.createSpace(name: "Test", iconName: "star")
        let windowState = env.makeWindowState()

        env.spaceManager.switchToSpaceSync(space, for: windowState)

        #expect(windowState.activeSpace?.id == space.id)
        #expect(windowState.activeSpace?.name == "Test")
    }

    // MARK: - Active Tab Tests

    @Test("WindowState activeTabID persists per space")
    func windowStateActiveTabIDPerSpace() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext

        let space1 = env.makeSpace(name: "Space 1")
        let space2 = env.makeSpace(name: "Space 2")

        let tab1 = Tab(space: space1, url: URL(string: "https://one.com")!)
        let tab2 = Tab(space: space2, url: URL(string: "https://two.com")!)
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

    @Test("WindowState activeTab returns tab object")
    func windowStateActiveTabReturns() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://active.com")!,
            in: space,
            makeActive: false,
        )
        env.tabManager.setActiveTab(tab, in: windowState)

        #expect(windowState.activeTab?.id == tab.id)
    }

    // MARK: - Layout Mode Tests

    @Test("WindowState isInLayoutMode starts false")
    func windowStateLayoutModeStartsFalse() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(!windowState.isInLayoutMode)
    }

    @Test("WindowState enterLayoutMode sets flag")
    func windowStateEnterLayoutMode() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.enterLayoutMode()

        #expect(windowState.isInLayoutMode)
    }

    @Test("WindowState exitLayoutMode clears flag")
    func windowStateExitLayoutMode() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.enterLayoutMode()
        #expect(windowState.isInLayoutMode)

        windowState.exitLayoutMode()
        #expect(!windowState.isInLayoutMode)
    }

    @Test("Switching space exits layout mode")
    func switchingSpaceExitsLayoutMode() throws {
        let env = try SpaceManagerTestEnvironment()

        let space1 = env.spaceManager.createSpace(name: "Space 1", iconName: "1.circle")
        let space2 = env.spaceManager.createSpace(name: "Space 2", iconName: "2.circle")

        let windowState = env.makeWindowState()
        env.spaceManager.switchToSpaceSync(space1, for: windowState)

        windowState.enterLayoutMode()
        #expect(windowState.isInLayoutMode)

        env.spaceManager.switchToSpaceSync(space2, for: windowState)
        #expect(!windowState.isInLayoutMode)
    }

    // MARK: - Sidebar State Tests

    @Test("WindowState sidebar collapsed state persists")
    func windowStateSidebarCollapsedPersists() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.isSidebarCollapsed = true

        #expect(windowState.isSidebarCollapsed)

        windowState.isSidebarCollapsed = false

        #expect(!windowState.isSidebarCollapsed)
    }

    // MARK: - Multiple Windows Tests

    @Test("Multiple WindowStates are independent")
    func multipleWindowStatesIndependent() throws {
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

    @Test("Multiple windows same space different active tabs")
    func multipleWindowsSameSpaceDifferentTabs() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext

        let space = env.makeSpace()

        let tab1 = Tab(space: space, url: URL(string: "https://one.com")!)
        let tab2 = Tab(space: space, url: URL(string: "https://two.com")!)
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
    @Test("Set active tab updates window state")
    func setActiveTabUpdatesState() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
        )

        env.tabManager.setActiveTab(tab, in: windowState)

        #expect(windowState.activeTabID == tab.id)
    }

    @Test("Select next tab advances selection")
    func selectNextTabAdvances() throws {
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

        env.tabManager.setActiveTab(tab1, in: windowState)

        // Use explicit list for deterministic ordering
        env.tabManager.selectNextTab(in: [tab1, tab2])

        #expect(windowState.activeTabID == tab2.id)
    }

    @Test("Select previous tab goes back")
    func selectPreviousTabGoesBack() throws {
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

        env.tabManager.setActiveTab(tab2, in: windowState)

        // Use explicit list for deterministic ordering
        env.tabManager.selectPreviousTab(in: [tab1, tab2])

        #expect(windowState.activeTabID == tab1.id)
    }

    @Test("Select next tab wraps at end")
    func selectNextTabWraps() throws {
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

        env.tabManager.setActiveTab(tab3, in: windowState)

        // selectNextTab at end stays at end (no wrapping) per TabManagerActivationTests
        env.tabManager.selectNextTab(in: [tab1, tab2, tab3])

        // At end of list, stays at current tab
        #expect(windowState.activeTabID == tab3.id)
    }
}

// MARK: - WindowState Cleanup Tests

@Suite("WindowState Cleanup", .tags(.tabManager), .serialized)
@MainActor
struct WindowStateCleanupTests {
    @Test("Closing active tab updates window state")
    func closingActiveTabUpdatesState() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab1 = env.tabManager.createTab(
            url: URL(string: "https://keep.com")!,
            in: space,
            makeActive: false,
        )
        let tab2 = env.tabManager.createTab(
            url: URL(string: "https://close.com")!,
            in: space,
            makeActive: false,
        )

        env.tabManager.setActiveTab(tab2, in: windowState)

        env.tabManager.closeTab(tab2)

        // Should switch to remaining tab
        #expect(windowState.activeTabID == tab1.id)
    }

    @Test("Closing last tab clears active tab ID")
    func closingLastTabClearsActiveID() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://only.com")!,
            in: space,
            makeActive: false,
        )

        env.tabManager.setActiveTab(tab, in: windowState)

        env.tabManager.closeTab(tab)

        #expect(windowState.activeTabID == nil)
    }

    @Test("Deleting active space switches window")
    func deletingActiveSpaceSwitchesWindow() throws {
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

    @Test("handleTabRemoved clears active tab for space")
    func handleTabRemovedClearsActiveTab() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()
        let windowState = env.makeWindowState()

        let tab = Tab(space: space, url: URL(string: "https://example.com")!)
        context.insert(tab)
        env.browserState.indexTab(tab)

        env.spaceManager.switchToSpaceSync(space, for: windowState)
        windowState.setActiveTabID(tab.id, for: space.id)
        #expect(windowState.activeTabID == tab.id)

        windowState.handleTabRemoved(tab.id, from: space.id)
        #expect(windowState.activeTabID == nil)
    }

    @Test("handleTabRemoved clears previous active tab")
    func handleTabRemovedClearsPreviousTab() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()
        let windowState = env.makeWindowState()

        let tab1 = Tab(space: space, url: URL(string: "https://one.com")!)
        let tab2 = Tab(space: space, url: URL(string: "https://two.com")!)
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

    @Test("handleTabRemoved clears live favorite override")
    func handleTabRemovedClearsLiveFavorite() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()
        let windowState = env.makeWindowState()

        let tab = Tab(space: nil, url: URL(string: "https://favorite.com")!)
        tab.status = .liveFavorite
        context.insert(tab)
        env.browserState.indexTab(tab)

        env.spaceManager.switchToSpaceSync(space, for: windowState)
        windowState.setActiveTab(tab)
        #expect(windowState.isShowingLiveFavorite)

        windowState.handleTabRemoved(tab.id, from: space.id)
        #expect(!windowState.isShowingLiveFavorite)
    }

    @Test("handleTabRemoved does not affect other spaces")
    func handleTabRemovedScopedToSpace() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space1 = env.makeSpace(name: "Space 1")
        let space2 = env.makeSpace(name: "Space 2")
        let windowState = env.makeWindowState()

        let tab1 = Tab(space: space1, url: URL(string: "https://one.com")!)
        let tab2 = Tab(space: space2, url: URL(string: "https://two.com")!)
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

    @Test("purgeStaleTabIDs removes deleted tabs from all spaces")
    func purgeStaleTabIDsRemovesDeleted() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space1 = env.makeSpace(name: "Space 1")
        let space2 = env.makeSpace(name: "Space 2")
        let windowState = env.makeWindowState()

        let tab1 = Tab(space: space1, url: URL(string: "https://one.com")!)
        let tab2 = Tab(space: space2, url: URL(string: "https://two.com")!)
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

    @Test("purgeStaleTabIDs preserves valid entries")
    func purgeStaleTabIDsPreservesValid() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()
        let windowState = env.makeWindowState()

        let tab = Tab(space: space, url: URL(string: "https://example.com")!)
        context.insert(tab)
        env.browserState.indexTab(tab)

        env.spaceManager.switchToSpaceSync(space, for: windowState)
        windowState.setActiveTabID(tab.id, for: space.id)

        windowState.purgeStaleTabIDs()

        #expect(windowState.activeTabID == tab.id)
    }

    @Test("purgeStaleTabIDs clears stale previous tab IDs")
    func purgeStaleTabIDsClearsStalePrevious() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()
        let windowState = env.makeWindowState()

        let tab1 = Tab(space: space, url: URL(string: "https://one.com")!)
        let tab2 = Tab(space: space, url: URL(string: "https://two.com")!)
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

    @Test("handleTabRemoved is idempotent")
    func handleTabRemovedIdempotent() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()
        let windowState = env.makeWindowState()

        let tab = Tab(space: space, url: URL(string: "https://example.com")!)
        context.insert(tab)
        env.browserState.indexTab(tab)

        env.spaceManager.switchToSpaceSync(space, for: windowState)
        windowState.setActiveTabID(tab.id, for: space.id)

        // Calling twice should not crash or change state
        windowState.handleTabRemoved(tab.id, from: space.id)
        windowState.handleTabRemoved(tab.id, from: space.id)

        #expect(windowState.activeTabID == nil)
    }

    @Test("handleTabRemoved with wrong space ID is no-op")
    func handleTabRemovedWrongSpace() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space1 = env.makeSpace(name: "Space 1")
        let space2 = env.makeSpace(name: "Space 2")
        let windowState = env.makeWindowState()

        let tab = Tab(space: space1, url: URL(string: "https://example.com")!)
        context.insert(tab)
        env.browserState.indexTab(tab)

        env.spaceManager.switchToSpaceSync(space1, for: windowState)
        windowState.setActiveTabID(tab.id, for: space1.id)

        // Remove from wrong space — should not affect space1
        windowState.handleTabRemoved(tab.id, from: space2.id)

        #expect(windowState.activeTabID == tab.id)
    }
}
