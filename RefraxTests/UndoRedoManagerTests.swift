import Foundation
import SwiftData
import SwiftUI
import Testing
import WebKit

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for UndoRedoManager operations.
    @Tag static var undoRedoManager: Self
}

// MARK: - UndoRedoManager Register Close Tab Tests

@Suite("UndoRedoManager Register Close Tab", .tags(.undoRedoManager), .serialized)
@MainActor
struct UndoRedoRegisterCloseTabTests {
    @Test("Register close tab adds to recently closed")
    func registerAddsToRecentlyClosed() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )
        let closedInfo = ClosedTabInfo(tab: tab)

        #expect(env.undoRedoManager.recentlyClosedTabs.isEmpty)

        env.undoRedoManager.registerCloseTab(closedInfo)

        #expect(env.undoRedoManager.recentlyClosedTabs.count == 1)
        #expect(env.undoRedoManager.recentlyClosedTabs.first?.id == closedInfo.id)
    }

    @Test("Register close tab sets action name with title")
    func registerSetsActionName() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )
        tab.activePage.title = "Test Page"
        let closedInfo = ClosedTabInfo(tab: tab)

        env.undoRedoManager.registerCloseTab(closedInfo)

        #expect(env.undoRedoManager.undoManager.canUndo)
        #expect(env.undoRedoManager.undoManager.undoActionName == "Close Tab \"Test Page\"")
    }

    @Test("Register close tab respects max limit")
    func registerRespectsMaxLimit() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create 12 tabs (exceeds limit of 10)
        for i in 0 ..< 12 {
            let tab = env.tabManager.createTab(
                url: URL(string: "https://example\(i).com")!,
                in: space,
                makeActive: false,
            )
            let closedInfo = ClosedTabInfo(tab: tab)
            env.undoRedoManager.registerCloseTab(closedInfo)
        }

        #expect(env.undoRedoManager.recentlyClosedTabs.count == 10)
    }

    @Test("Register close tab inserts at front")
    func registerInsertsAtFront() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab1 = env.tabManager.createTab(url: URL(string: "https://first.com")!, in: space, makeActive: false)
        let tab2 = env.tabManager.createTab(url: URL(string: "https://second.com")!, in: space, makeActive: false)

        let info1 = ClosedTabInfo(tab: tab1)
        let info2 = ClosedTabInfo(tab: tab2)

        env.undoRedoManager.registerCloseTab(info1)
        env.undoRedoManager.registerCloseTab(info2)

        #expect(env.undoRedoManager.recentlyClosedTabs.first?.id == info2.id)
    }

    @Test("Undo close tab removes from recently closed")
    func undoRemovesFromRecentlyClosed() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Need at least one tab remaining after close
        _ = env.tabManager.createTab(url: URL(string: "https://other.com")!, in: space, makeActive: false)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )
        let closedInfo = ClosedTabInfo(tab: tab)

        env.undoRedoManager.registerCloseTab(closedInfo)
        #expect(env.undoRedoManager.recentlyClosedTabs.count == 1)

        env.undoRedoManager.undoManager.undo()

        #expect(env.undoRedoManager.recentlyClosedTabs.isEmpty)
    }
}

// MARK: - UndoRedoManager Register Batch Tests

@Suite("UndoRedoManager Register Batch", .tags(.undoRedoManager), .serialized)
@MainActor
struct UndoRedoRegisterBatchTests {
    @Test("Register batch adds all to recently closed")
    func registerBatchAddsAll() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab1 = env.tabManager.createTab(url: URL(string: "https://one.com")!, in: space, makeActive: false)
        let tab2 = env.tabManager.createTab(url: URL(string: "https://two.com")!, in: space, makeActive: false)
        let tab3 = env.tabManager.createTab(url: URL(string: "https://three.com")!, in: space, makeActive: false)

        let infos = [ClosedTabInfo(tab: tab1), ClosedTabInfo(tab: tab2), ClosedTabInfo(tab: tab3)]

        env.undoRedoManager.registerCloseTabsBatch(infos, actionName: "Close 3 Tabs")

        #expect(env.undoRedoManager.recentlyClosedTabs.count == 3)
    }

    @Test("Register batch with empty array is no-op")
    func registerBatchEmptyIsNoOp() throws {
        let env = try TabManagerTestEnvironment()

        env.undoRedoManager.registerCloseTabsBatch([], actionName: "Close Tabs")

        #expect(env.undoRedoManager.recentlyClosedTabs.isEmpty)
        #expect(!env.undoRedoManager.undoManager.canUndo)
    }

    @Test("Register batch sets action name")
    func registerBatchSetsActionName() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(url: URL(string: "https://example.com")!, in: space, makeActive: false)
        let infos = [ClosedTabInfo(tab: tab)]

        env.undoRedoManager.registerCloseTabsBatch(infos, actionName: "Close Other Tabs")

        #expect(env.undoRedoManager.undoManager.undoActionName == "Close Other Tabs")
    }

    @Test("Undo batch removes all from recently closed")
    func undoBatchRemovesAll() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Keep one tab so space isn't empty
        _ = env.tabManager.createTab(url: URL(string: "https://keep.com")!, in: space, makeActive: true)

        let tab1 = env.tabManager.createTab(url: URL(string: "https://one.com")!, in: space, makeActive: false)
        let tab2 = env.tabManager.createTab(url: URL(string: "https://two.com")!, in: space, makeActive: false)

        let infos = [ClosedTabInfo(tab: tab1), ClosedTabInfo(tab: tab2)]

        env.undoRedoManager.registerCloseTabsBatch(infos, actionName: "Close 2 Tabs")

        #expect(env.undoRedoManager.recentlyClosedTabs.count == 2)

        env.undoRedoManager.undoManager.undo()

        // After undo, both should be removed from recently closed
        #expect(env.undoRedoManager.recentlyClosedTabs.isEmpty)
    }
}

// MARK: - UndoRedoManager Register Reference Tab Tests

@Suite("UndoRedoManager Register Reference Tab", .tags(.undoRedoManager), .serialized)
@MainActor
struct UndoRedoRegisterReferenceTabTests {
    @Test("Register close reference tab adds to recently closed")
    func registerRefTabAdds() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let refTab = env.referencePaneManager.addReferenceTab(
            url: URL(string: "https://reference.com")!,
            in: space,
        )!
        let closedInfo = ClosedTabInfo(tab: refTab)

        env.undoRedoManager.registerCloseReferenceTab(closedInfo)

        #expect(env.undoRedoManager.recentlyClosedTabs.count == 1)
        #expect(env.undoRedoManager.recentlyClosedTabs.first?.isReferenceTab == true)
    }

    @Test("Register close reference tab sets action name")
    func registerRefTabSetsActionName() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let refTab = env.referencePaneManager.addReferenceTab(
            url: URL(string: "https://reference.com")!,
            title: "Reference Doc",
            in: space,
        )!
        let closedInfo = ClosedTabInfo(tab: refTab)

        env.undoRedoManager.registerCloseReferenceTab(closedInfo)

        #expect(env.undoRedoManager.undoManager.undoActionName == "Close Reference Tab \"Reference Doc\"")
    }
}

// MARK: - UndoRedoManager Register Delete Group Tests

@Suite("UndoRedoManager Register Delete Group", .tags(.undoRedoManager), .serialized)
@MainActor
struct UndoRedoRegisterDeleteGroupTests {
    @Test("Register delete group adds to recently deleted groups")
    func registerDeleteGroupAdds() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(url: URL(string: "https://example.com")!, in: space, makeActive: true)
        let group = try env.groupManager.createGroup(in: space, name: "Test Group")
        env.groupManager.moveTabToGroup(tab, group: group)

        let closedInfo = ClosedGroupInfo(group: group, tabs: [tab])

        #expect(env.undoRedoManager.recentlyDeletedGroups.isEmpty)

        env.undoRedoManager.registerDeleteGroup(closedInfo)

        #expect(env.undoRedoManager.recentlyDeletedGroups.count == 1)
    }

    @Test("Register delete group sets action name")
    func registerDeleteGroupSetsActionName() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(url: URL(string: "https://example.com")!, in: space, makeActive: true)
        let group = try env.groupManager.createGroup(in: space, name: "My Group")
        env.groupManager.moveTabToGroup(tab, group: group)

        let closedInfo = ClosedGroupInfo(group: group, tabs: [tab])
        env.undoRedoManager.registerDeleteGroup(closedInfo)

        #expect(env.undoRedoManager.undoManager.undoActionName == "Delete Group \"My Group\"")
    }

    @Test("Register delete group respects max limit")
    func registerDeleteGroupRespectsLimit() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create 12 groups (exceeds limit of 10)
        for i in 0 ..< 12 {
            let tab = env.tabManager.createTab(url: URL(string: "https://example\(i).com")!, in: space, makeActive: false)
            let group = try env.groupManager.createGroup(in: space, name: "Group \(i)")
            env.groupManager.moveTabToGroup(tab, group: group)
            let closedInfo = ClosedGroupInfo(group: group, tabs: [tab])
            env.undoRedoManager.registerDeleteGroup(closedInfo)
        }

        #expect(env.undoRedoManager.recentlyDeletedGroups.count == 10)
    }

    @Test("Undo delete group removes from recently deleted")
    func undoDeleteGroupRemoves() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(url: URL(string: "https://example.com")!, in: space, makeActive: true)
        let group = try env.groupManager.createGroup(in: space, name: "Test Group")
        env.groupManager.moveTabToGroup(tab, group: group)

        let closedInfo = ClosedGroupInfo(group: group, tabs: [tab])
        env.undoRedoManager.registerDeleteGroup(closedInfo)

        #expect(env.undoRedoManager.recentlyDeletedGroups.count == 1)

        env.undoRedoManager.undoManager.undo()

        #expect(env.undoRedoManager.recentlyDeletedGroups.isEmpty)
    }
}

// MARK: - UndoRedoManager Reopen Tests

@Suite("UndoRedoManager Reopen", .tags(.undoRedoManager), .serialized)
@MainActor
struct UndoRedoReopenTests {
    @Test("Reopen last closed tab restores and removes from list")
    func reopenLastClosedTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Keep one tab so space isn't empty
        _ = env.tabManager.createTab(url: URL(string: "https://keep.com")!, in: space, makeActive: true)

        let tab = env.tabManager.createTab(url: URL(string: "https://example.com")!, in: space, makeActive: false)
        let closedInfo = ClosedTabInfo(tab: tab)

        env.undoRedoManager.registerCloseTab(closedInfo)
        #expect(env.undoRedoManager.recentlyClosedTabs.count == 1)

        env.undoRedoManager.reopenLastClosedTab()

        #expect(env.undoRedoManager.recentlyClosedTabs.isEmpty)
    }

    @Test("Reopen last closed tab is no-op when list empty")
    func reopenLastClosedTabEmpty() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.undoRedoManager.recentlyClosedTabs.isEmpty)

        // Should not crash
        env.undoRedoManager.reopenLastClosedTab()

        #expect(env.undoRedoManager.recentlyClosedTabs.isEmpty)
    }

    @Test("Reopen closed tab at index removes from list")
    func reopenAtIndex() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        _ = env.tabManager.createTab(url: URL(string: "https://keep.com")!, in: space, makeActive: true)

        let tab1 = env.tabManager.createTab(url: URL(string: "https://first.com")!, in: space, makeActive: false)
        let tab2 = env.tabManager.createTab(url: URL(string: "https://second.com")!, in: space, makeActive: false)

        let info1 = ClosedTabInfo(tab: tab1)
        let info2 = ClosedTabInfo(tab: tab2)

        env.undoRedoManager.registerCloseTab(info1)
        env.undoRedoManager.registerCloseTab(info2)

        #expect(env.undoRedoManager.recentlyClosedTabs.count == 2)

        // Reopen at index 1 (the first one registered)
        env.undoRedoManager.reopenClosedTab(at: 1)

        #expect(env.undoRedoManager.recentlyClosedTabs.count == 1)
        #expect(env.undoRedoManager.recentlyClosedTabs.first?.id == info2.id)
    }

    @Test("Reopen closed tab at invalid index is no-op")
    func reopenAtInvalidIndex() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(url: URL(string: "https://example.com")!, in: space, makeActive: false)
        let info = ClosedTabInfo(tab: tab)
        env.undoRedoManager.registerCloseTab(info)

        #expect(env.undoRedoManager.recentlyClosedTabs.count == 1)

        // Invalid indices
        env.undoRedoManager.reopenClosedTab(at: -1)
        env.undoRedoManager.reopenClosedTab(at: 5)

        #expect(env.undoRedoManager.recentlyClosedTabs.count == 1)
    }

    @Test("Reopen reference tab uses reference restore path")
    func reopenReferenceTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let refTab = env.referencePaneManager.addReferenceTab(
            url: URL(string: "https://reference.com")!,
            in: space,
        )!
        let closedInfo = ClosedTabInfo(tab: refTab)

        env.undoRedoManager.registerCloseReferenceTab(closedInfo)

        env.undoRedoManager.reopenLastClosedTab()

        #expect(env.undoRedoManager.recentlyClosedTabs.isEmpty)
    }
}

// MARK: - UndoRedoManager Clear Tests

@Suite("UndoRedoManager Clear", .tags(.undoRedoManager), .serialized)
@MainActor
struct UndoRedoClearTests {
    @Test("Clear recently closed tabs empties list")
    func clearRecentlyClosedTabs() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        for i in 0 ..< 5 {
            let tab = env.tabManager.createTab(url: URL(string: "https://example\(i).com")!, in: space, makeActive: false)
            let info = ClosedTabInfo(tab: tab)
            env.undoRedoManager.registerCloseTab(info)
        }

        #expect(env.undoRedoManager.recentlyClosedTabs.count == 5)

        env.undoRedoManager.clearRecentlyClosedTabs()

        #expect(env.undoRedoManager.recentlyClosedTabs.isEmpty)
    }
}

// MARK: - UndoRedoManager Menu Title Tests

@Suite("UndoRedoManager Menu Titles", .tags(.undoRedoManager), .serialized)
@MainActor
struct UndoRedoMenuTitleTests {
    @Test("Undo menu title shows action name when available")
    func undoMenuTitleWithAction() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(url: URL(string: "https://example.com")!, in: space, makeActive: true)
        tab.activePage.title = "My Page"
        let closedInfo = ClosedTabInfo(tab: tab)

        env.undoRedoManager.registerCloseTab(closedInfo)

        #expect(env.undoRedoManager.undoMenuTitle == "Undo Close Tab \"My Page\"")
    }

    @Test("Undo menu title is plain when no action")
    func undoMenuTitleNoAction() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.undoRedoManager.undoMenuTitle == "Undo")
    }

    @Test("Redo menu title is plain when undo action available but not yet undone")
    func redoMenuTitleNoRedo() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(url: URL(string: "https://example.com")!, in: space, makeActive: false)
        let closedInfo = ClosedTabInfo(tab: tab)

        env.undoRedoManager.registerCloseTab(closedInfo)

        // Undo is available but redo is not (haven't undone yet)
        #expect(env.undoRedoManager.undoManager.canUndo)
        #expect(!env.undoRedoManager.undoManager.canRedo)
        #expect(env.undoRedoManager.redoMenuTitle == "Redo")
    }

    @Test("Redo menu title is plain when no action")
    func redoMenuTitleNoAction() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.undoRedoManager.redoMenuTitle == "Redo")
    }
}

// MARK: - UndoRedoManager Edge Case Tests

@Suite("UndoRedoManager Edge Cases", .tags(.undoRedoManager), .serialized)
@MainActor
struct UndoRedoEdgeCaseTests {
    @Test("Levels of undo is set to 50")
    func levelsOfUndo() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.undoRedoManager.undoManager.levelsOfUndo == 50)
    }

    @Test("Max recently closed tabs is 10")
    func maxRecentlyClosedTabs() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.undoRedoManager.maxRecentlyClosedTabs == 10)
    }

    @Test("Max recently deleted groups is 10")
    func maxRecentlyDeletedGroups() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.undoRedoManager.maxRecentlyDeletedGroups == 10)
    }

    @Test("Multiple registrations create multiple undo actions")
    func multipleRegistrations() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Register 3 close actions
        for i in 0 ..< 3 {
            let tab = env.tabManager.createTab(url: URL(string: "https://example\(i).com")!, in: space, makeActive: false)
            let info = ClosedTabInfo(tab: tab)
            env.undoRedoManager.registerCloseTab(info)
        }

        #expect(env.undoRedoManager.recentlyClosedTabs.count == 3)
        #expect(env.undoRedoManager.undoManager.canUndo)

        // The last registered action should show in the undo menu
        #expect(env.undoRedoManager.undoMenuTitle.contains("Close Tab"))
    }
}
