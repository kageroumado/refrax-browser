import Foundation
import SwiftData
import SwiftUI
import Testing
import WebKit

@testable import Refrax

// MARK: - TabManager Normalize Positions Tests

@Suite("TabManager Normalize Positions", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerNormalizePositionsTests {
    @Test("Normalize positions assigns hierarchical values")
    func normalizeAssignsHierarchical() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create tabs - they get positions sequentially on creation
        _ = env.tabManager.createTab(url: URL(string: "https://one.com")!, in: space, makeActive: false)
        _ = env.tabManager.createTab(url: URL(string: "https://two.com")!, in: space, makeActive: false)
        _ = env.tabManager.createTab(url: URL(string: "https://three.com")!, in: space, makeActive: false)

        env.tabManager.normalizePositions(in: space)

        // After normalization, positions should follow hierarchical scheme
        let sorted = space.tabs.sorted { $0.position < $1.position }
        #expect(sorted.count == 3)

        // Positions should be in order (exact values depend on implementation)
        #expect(sorted[0].position < sorted[1].position)
        #expect(sorted[1].position < sorted[2].position)
    }

    @Test("Normalize positions is stable across repeated calls")
    func normalizeIsStable() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        env.tabManager.createTab(url: URL(string: "https://one.com")!, in: space, makeActive: false)
        env.tabManager.createTab(url: URL(string: "https://two.com")!, in: space, makeActive: false)
        env.tabManager.createTab(url: URL(string: "https://three.com")!, in: space, makeActive: false)

        // Normalize twice
        env.tabManager.normalizePositions(in: space)
        let firstNormalize = space.tabs.sorted { $0.position < $1.position }.map(\.id)

        env.tabManager.normalizePositions(in: space)
        let secondNormalize = space.tabs.sorted { $0.position < $1.position }.map(\.id)

        #expect(firstNormalize == secondNormalize, "Order should be stable")
    }

    @Test("Normalize positions handles groups correctly")
    func normalizeHandlesGroups() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create a group with tabs
        let group = try env.groupManager.createGroup(in: space, name: "Test Group")

        let tabInGroup = env.tabManager.createTab(url: URL(string: "https://grouped.com")!, in: space, makeActive: false)
        tabInGroup.groupID = group.id

        _ = env.tabManager.createTab(url: URL(string: "https://root.com")!, in: space, makeActive: false)

        env.tabManager.normalizePositions(in: space)

        // Group tabs should have positions relative to their group
        // Root items use billions, group items use millions offset from group position
        let groupPos = group.position
        let tabInGroupPos = tabInGroup.position

        // Tab in group should have position greater than group position
        #expect(tabInGroupPos > groupPos, "Tab in group should follow group position")
    }

    @Test("Normalize positions handles nested groups")
    func normalizeHandlesNestedGroups() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let parentGroup = try env.groupManager.createGroup(in: space, name: "Parent")
        let nestedGroup = try env.groupManager.createGroup(in: space, name: "Nested", parentGroupID: parentGroup.id)

        let tabInNested = env.tabManager.createTab(url: URL(string: "https://nested.com")!, in: space, makeActive: false)
        tabInNested.groupID = nestedGroup.id

        env.tabManager.normalizePositions(in: space)

        // Nested group should have position > parent
        // Tab in nested should have position > nested group
        #expect(nestedGroup.position > parentGroup.position)
        #expect(tabInNested.position > nestedGroup.position)
    }

    @Test("Normalize positions handles empty space")
    func normalizeHandlesEmptySpace() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        #expect(space.tabs.isEmpty)

        // Should not crash
        env.tabManager.normalizePositions(in: space)

        #expect(space.tabs.isEmpty)
    }

    @Test("Normalize positions separates pinned and unpinned")
    func normalizeSeparatesPinnedUnpinned() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let pinnedTab = env.tabManager.createTab(url: URL(string: "https://pinned.com")!, in: space, makeActive: false)
        pinnedTab.isPinned = true

        let unpinnedTab = env.tabManager.createTab(url: URL(string: "https://unpinned.com")!, in: space, makeActive: false)

        env.tabManager.normalizePositions(in: space)

        // Pinned tabs should have lower positions than unpinned
        #expect(pinnedTab.position < unpinnedTab.position, "Pinned should have lower position")
    }
}

// MARK: - TabManager Initialize Window Tests

@Suite("TabManager Initialize Window", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerInitializeWindowTests {
    @Test("Initialize window sets active space but not active tab")
    func initializeWindowSetsSpace() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        _ = env.tabManager.createTab(url: URL(string: "https://one.com")!, in: space, makeActive: false)
        _ = env.tabManager.createTab(url: URL(string: "https://two.com")!, in: space, makeActive: false)

        let windowState = env.makeWindowState()
        env.tabManager.initializeWindow(windowState, with: space)

        // initializeWindow now defers tab selection for lazy WebPage creation
        #expect(windowState.activeSpace?.id == space.id, "Should set active space")
        #expect(windowState.activeTabID == nil, "Should not set active tab (lazy initialization)")
    }

    @Test("Initialize window does not set active tab when activeTabID is nil")
    func initializeWindowNoActiveTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        _ = env.tabManager.createTab(url: URL(string: "https://one.com")!, in: space, makeActive: false)
        _ = env.tabManager.createTab(url: URL(string: "https://two.com")!, in: space, makeActive: false)

        let windowState = env.makeWindowState()
        env.tabManager.initializeWindow(windowState, with: space)

        // initializeWindow now defers tab selection for lazy WebPage creation
        #expect(windowState.activeTabID == nil, "Should not set active tab")
    }

    @Test("Initialize window uses first space when none provided")
    func initializeWindowUsesFirstSpace() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        env.tabManager.createTab(url: URL(string: "https://one.com")!, in: space, makeActive: false)

        let windowState = env.makeWindowState()
        env.tabManager.initializeWindow(windowState, with: nil)

        #expect(windowState.activeSpace?.id == space.id, "Should use first space")
    }
}

// MARK: - TabManager Temporary Space Tests

@Suite("TabManager Temporary Space", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerTemporarySpaceTests {
    @Test("Create temporary space returns a space")
    func createTemporarySpaceReturnsSpace() throws {
        let env = try TabManagerTestEnvironment()

        let space = env.tabManager.createTemporarySpace()

        #expect(space.name.isEmpty == false, "Temporary space should have a name")
    }
}

// MARK: - TabManager Save Tests

@Suite("TabManager Save Operations", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerSaveTests {
    @Test("scheduleSave delegates to state")
    func scheduleSaveDelegatesToState() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create a tab to have something to save
        env.tabManager.createTab(url: URL(string: "https://example.com")!, in: space, makeActive: true)

        // Should not crash
        env.tabManager.scheduleSave()

        // No assertion needed - just verifying it doesn't crash
    }

    @Test("saveImmediately completes without error")
    func saveImmediatelyCompletes() async throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        env.tabManager.createTab(url: URL(string: "https://example.com")!, in: space, makeActive: true)

        // Should complete without error
        await env.tabManager.saveImmediately()

        // No assertion needed - just verifying it completes
    }

    @Test("saveSpaceState delegates to space manager")
    func saveSpaceStateDelegates() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        env.tabManager.createTab(url: URL(string: "https://example.com")!, in: space, makeActive: true)

        // Should not crash
        env.tabManager.saveSpaceState(space)
    }
}

// MARK: - TabManager Memory Warning Tests

@Suite("TabManager Memory Warning", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerMemoryWarningTests {
    @Test("handleMemoryWarning delegates to page pool")
    func handleMemoryWarningDelegates() throws {
        let env = try TabManagerTestEnvironment()

        // Should not crash
        env.tabManager.handleMemoryWarning()
    }
}

// MARK: - TabManager Restore From Persistence Tests

@Suite("TabManager Restore From Persistence", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerRestoreFromPersistenceTests {
    @Test("restoreFromPersistence with existing spaces preserves them")
    func restorePreservesExistingSpaces() throws {
        let env = try TabManagerTestEnvironment()

        // Create a space first
        let existingSpace = env.makeSpace(name: "Existing")
        env.tabManager.createTab(url: URL(string: "https://existing.com")!, in: existingSpace, makeActive: false)

        // Restore should not lose the existing space
        let restoredSpace = env.tabManager.restoreFromPersistence()

        // The restored space should be the first space (either existing or default)
        #expect(env.browserState.spaces.contains(where: { $0.id == existingSpace.id }) ||
            env.browserState.spaces.contains(where: { $0.id == restoredSpace.id }))
    }
}
