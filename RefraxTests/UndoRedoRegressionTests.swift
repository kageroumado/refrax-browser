import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Refrax

// MARK: - UndoRedo Regression Tests

/// Tests for UndoRedoManager functionality that could regress when implementing
/// new features that modify tabs, groups, or spaces.
@Suite("UndoRedo Regression", .tags(.tabManager), .serialized)
@MainActor
struct UndoRedoRegressionTests {
    // MARK: - Recently Closed Tabs Tests

    @Test("Closed tab added to recently closed list")
    func closedTabAddedToList() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        #expect(env.undoRedoManager.recentlyClosedTabs.isEmpty)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
        )

        env.tabManager.closeTab(tab)

        #expect(!env.undoRedoManager.recentlyClosedTabs.isEmpty)
    }

    @Test("Recently closed preserves URL")
    func recentlyClosedPreservesURL() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://preserve.com/path")!,
            in: space,
            makeActive: false,
        )

        env.tabManager.closeTab(tab)

        let closedInfo = env.undoRedoManager.recentlyClosedTabs.first

        #expect(closedInfo?.url.absoluteString == "https://preserve.com/path")
    }

    @Test("Recently closed preserves title")
    func recentlyClosedPreservesTitle() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
        )
        tab.activePage.title = "Preserved Title"

        env.tabManager.closeTab(tab)

        let closedInfo = env.undoRedoManager.recentlyClosedTabs.first

        #expect(closedInfo?.title == "Preserved Title")
    }

    @Test("Recently closed preserves custom name")
    func recentlyClosedPreservesCustomName() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
        )
        tab.customName = "Custom Name"

        env.tabManager.closeTab(tab)

        let closedInfo = env.undoRedoManager.recentlyClosedTabs.first

        #expect(closedInfo?.customName == "Custom Name")
    }

    @Test("Recently closed preserves group ID")
    func recentlyClosedPreservesGroupID() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Container")

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            groupID: group.id,
            makeActive: false,
        )

        env.tabManager.closeTab(tab)

        let closedInfo = env.undoRedoManager.recentlyClosedTabs.first

        #expect(closedInfo?.groupID == group.id)
    }

    @Test("Recently closed preserves space ID")
    func recentlyClosedPreservesSpaceID() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
        )

        env.tabManager.closeTab(tab)

        let closedInfo = env.undoRedoManager.recentlyClosedTabs.first

        #expect(closedInfo?.spaceID == space.id)
    }

    // MARK: - Restore Tab Tests

    @Test("Restore tab creates new tab")
    func restoreTabCreatesNew() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://restore.com")!,
            in: space,
            makeActive: false,
        )

        env.tabManager.closeTab(tab)

        #expect(space.tabs.isEmpty)

        let closedInfo = env.undoRedoManager.recentlyClosedTabs.first!
        env.tabManager.restoreTab(closedInfo)

        #expect(space.tabs.count == 1)
    }

    @Test("Restore tab restores to original space")
    func restoreTabToOriginalSpace() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
        )

        env.tabManager.closeTab(tab)

        let closedInfo = env.undoRedoManager.recentlyClosedTabs.first!
        env.tabManager.restoreTab(closedInfo)

        let restoredTab = space.tabs.first
        #expect(restoredTab?.space?.id == space.id)
    }

    @Test("Restore tab restores group membership")
    func restoreTabRestoresGroupMembership() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Container")

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            groupID: group.id,
            makeActive: false,
        )

        env.tabManager.closeTab(tab)

        let closedInfo = env.undoRedoManager.recentlyClosedTabs.first!
        env.tabManager.restoreTab(closedInfo)

        let restoredTab = space.tabs.first
        #expect(restoredTab?.groupID == group.id)
    }

    @Test("Reopen last closed tab works")
    func reopenLastClosedTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab1 = env.tabManager.createTab(
            url: URL(string: "https://first.com")!,
            in: space,
            makeActive: false,
        )
        let tab2 = env.tabManager.createTab(
            url: URL(string: "https://second.com")!,
            in: space,
            makeActive: false,
        )

        env.tabManager.closeTab(tab1)
        env.tabManager.closeTab(tab2)

        #expect(space.tabs.isEmpty)

        env.tabManager.reopenLastClosedTab()

        // Should restore tab2 (last closed)
        #expect(space.tabs.count == 1)
        #expect(space.tabs.first?.activePage.url.host == "second.com")
    }

    // MARK: - Recently Closed Limit Tests

    @Test("Recently closed has maximum limit")
    func recentlyClosedMaxLimit() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create and close many tabs
        for i in 0 ..< 30 {
            let tab = env.tabManager.createTab(
                url: URL(string: "https://site\(i).com")!,
                in: space,
                makeActive: false,
            )
            env.tabManager.closeTab(tab)
        }

        // Should not exceed reasonable limit
        #expect(env.undoRedoManager.recentlyClosedTabs.count <= 20)
    }

    @Test("Recently closed LIFO order")
    func recentlyClosedLIFOOrder() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab1 = env.tabManager.createTab(
            url: URL(string: "https://first.com")!,
            in: space,
            makeActive: false,
        )
        let tab2 = env.tabManager.createTab(
            url: URL(string: "https://second.com")!,
            in: space,
            makeActive: false,
        )
        let tab3 = env.tabManager.createTab(
            url: URL(string: "https://third.com")!,
            in: space,
            makeActive: false,
        )

        env.tabManager.closeTab(tab1)
        env.tabManager.closeTab(tab2)
        env.tabManager.closeTab(tab3)

        // Most recent should be first
        #expect(env.undoRedoManager.recentlyClosedTabs[0].url.host == "third.com")
        #expect(env.undoRedoManager.recentlyClosedTabs[1].url.host == "second.com")
        #expect(env.undoRedoManager.recentlyClosedTabs[2].url.host == "first.com")
    }

    // MARK: - Restore Removes From List Tests

    @Test("Restore removes from recently closed list")
    func restoreRemovesFromList() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
        )

        env.tabManager.closeTab(tab)
        #expect(env.undoRedoManager.recentlyClosedTabs.count == 1)

        env.tabManager.reopenLastClosedTab()
        #expect(env.undoRedoManager.recentlyClosedTabs.isEmpty)
    }

    @Test("Recently closed list is accessible")
    func recentlyClosedListAccessible() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        #expect(env.undoRedoManager.recentlyClosedTabs.isEmpty)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
        )
        env.tabManager.closeTab(tab)

        #expect(!env.undoRedoManager.recentlyClosedTabs.isEmpty)
    }
}
