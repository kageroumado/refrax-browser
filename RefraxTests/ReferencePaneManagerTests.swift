import Foundation
import SwiftData
import SwiftUI
import Testing
import WebKit
@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for ReferencePaneManager operations.
    @Tag static var referencePaneManager: Self
}

// MARK: - ReferencePaneManager Add Tests

@Suite("ReferencePaneManager Add", .tags(.referencePaneManager), .serialized)
@MainActor
struct ReferencePaneAddTests {
    @Test("Add reference tab creates tab marked as reference")
    func addCreatesReferenceTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let refTab = try env.referencePaneManager.addReferenceTab(
            url: #require(URL(string: "https://reference.com")),
            title: "Reference Tab",
            in: space,
        )

        #expect(refTab != nil)
        #expect(refTab?.isReferenceTab == true)
        #expect(space.referenceTabs.contains(where: { $0.id == refTab?.id }))
        #expect(space.tabs.contains(where: { $0.id == refTab?.id }), "Tab should be in space.tabs")
    }

    @Test("Add reference tab respects limit of 4")
    func addRespectsLimit() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Add 4 reference tabs (the max)
        for i in 0 ..< 4 {
            let tab = try env.referencePaneManager.addReferenceTab(
                url: #require(URL(string: "https://ref\(i).com")),
                in: space,
            )
            #expect(tab != nil, "Should create reference tab \(i)")
        }

        #expect(space.referenceTabs.count == 4)

        // Fifth should fail
        let fifthTab = try env.referencePaneManager.addReferenceTab(
            url: #require(URL(string: "https://ref5.com")),
            in: space,
        )

        #expect(fifthTab == nil, "Fifth reference tab should be rejected")
        #expect(space.referenceTabs.count == 4)
    }

    @Test("Add reference tab assigns sequential positions")
    func addAssignsPositions() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let url1 = try #require(URL(string: "https://ref1.com"))
        let url2 = try #require(URL(string: "https://ref2.com"))
        let url3 = try #require(URL(string: "https://ref3.com"))
        let ref1 = try #require(env.referencePaneManager.addReferenceTab(url: url1, in: space))
        let ref2 = try #require(env.referencePaneManager.addReferenceTab(url: url2, in: space))
        let ref3 = try #require(env.referencePaneManager.addReferenceTab(url: url3, in: space))

        #expect(ref1.position == 0)
        #expect(ref2.position == 1)
        #expect(ref3.position == 2)
    }

    @Test("Add reference tab indexes tab in browser state")
    func addIndexesTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.referencePaneManager.addReferenceTab(
            url: refURL,
            in: space,
        ))

        #expect(env.browserState.tab(for: refTab.id) != nil)
    }

    @Test("Add reference tab increments list version")
    func addIncrementsVersion() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let versionBefore = env.browserState.tabListVersion

        try env.referencePaneManager.addReferenceTab(
            url: #require(URL(string: "https://reference.com")),
            in: space,
        )

        #expect(env.browserState.tabListVersion > versionBefore)
    }
}

// MARK: - ReferencePaneManager Close Tests

@Suite("ReferencePaneManager Close", .tags(.referencePaneManager), .serialized)
@MainActor
struct ReferencePaneCloseTests {
    @Test("Close reference tab removes from space")
    func closeRemovesFromSpace() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.referencePaneManager.addReferenceTab(
            url: refURL,
            in: space,
        ))

        #expect(space.referenceTabs.count == 1)

        env.referencePaneManager.closeReferenceTab(refTab)

        #expect(space.referenceTabs.isEmpty)
        #expect(!space.tabs.contains(where: { $0.id == refTab.id }))
    }

    @Test("Close reference tab removes from index")
    func closeRemovesFromIndex() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.referencePaneManager.addReferenceTab(
            url: refURL,
            in: space,
        ))
        let tabID = refTab.id

        env.referencePaneManager.closeReferenceTab(refTab)

        #expect(env.browserState.tab(for: tabID) == nil)
    }

    @Test("Close reference tab registers with undo manager")
    func closeRegistersUndo() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.referencePaneManager.addReferenceTab(
            url: refURL,
            in: space,
        ))

        let initialCount = env.undoRedoManager.recentlyClosedTabs.count

        env.referencePaneManager.closeReferenceTab(refTab)

        #expect(env.undoRedoManager.recentlyClosedTabs.count > initialCount)
    }

    @Test("Close reference tab renumbers remaining tabs")
    func closeRenumbersRemaining() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let url1 = try #require(URL(string: "https://ref1.com"))
        let url2 = try #require(URL(string: "https://ref2.com"))
        let url3 = try #require(URL(string: "https://ref3.com"))
        let ref1 = try #require(env.referencePaneManager.addReferenceTab(url: url1, in: space))
        let ref2 = try #require(env.referencePaneManager.addReferenceTab(url: url2, in: space))
        let ref3 = try #require(env.referencePaneManager.addReferenceTab(url: url3, in: space))

        // Close middle tab
        env.referencePaneManager.closeReferenceTab(ref2)

        #expect(ref1.position == 0)
        #expect(ref3.position == 1, "ref3 should be renumbered to position 1")
    }

    @Test("Close non-reference tab is no-op")
    func closeNonReferenceIsNoOp() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let mainTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        let countBefore = space.tabs.count

        // This should not crash and should be a no-op
        env.referencePaneManager.closeReferenceTab(mainTab)

        #expect(space.tabs.count == countBefore)
    }

    @Test("Close last reference tab empties reference tabs")
    func closeLastRefTabEmptiesReferenceTabs() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.referencePaneManager.addReferenceTab(
            url: refURL,
            in: space,
        ))

        #expect(space.referenceTabs.count == 1)

        env.referencePaneManager.closeReferenceTab(refTab)

        #expect(space.referenceTabs.isEmpty)
    }

    @Test("Close reference tab increments list version")
    func closeIncrementsVersion() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.referencePaneManager.addReferenceTab(
            url: refURL,
            in: space,
        ))

        let versionBefore = env.browserState.tabListVersion

        env.referencePaneManager.closeReferenceTab(refTab)

        #expect(env.browserState.tabListVersion > versionBefore)
    }
}

// MARK: - ReferencePaneManager Restore Tests

@Suite("ReferencePaneManager Restore", .tags(.referencePaneManager), .serialized)
@MainActor
struct ReferencePaneRestoreTests {
    @Test("Restore reference tab recreates with properties")
    func restoreRecreatesWithProperties() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.referencePaneManager.addReferenceTab(
            url: refURL,
            title: "Original Title",
            in: space,
        ))
        refTab.customName = "Custom Name"
        refTab.activePage.faviconData = Data([0xAB, 0xCD])

        env.referencePaneManager.closeReferenceTab(refTab)

        let closedInfo = try #require(env.undoRedoManager.recentlyClosedTabs.first)

        env.referencePaneManager.restoreReferenceTab(closedInfo)

        let restored = space.referenceTabs.first
        #expect(restored != nil)
        #expect(restored?.customName == "Custom Name")
        #expect(restored?.activePage.faviconData == Data([0xAB, 0xCD]))
    }

    @Test("Restore reference tab respects limit")
    func restoreRespectsLimit() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create and close a reference tab first to get ClosedTabInfo
        let overflowURL = try #require(URL(string: "https://overflow.com"))
        let extraRefTab = try #require(env.referencePaneManager.addReferenceTab(
            url: overflowURL,
            in: space,
        ))
        env.referencePaneManager.closeReferenceTab(extraRefTab)
        let closedInfo = try #require(env.undoRedoManager.recentlyClosedTabs.first)

        // Now fill reference pane to 4
        for i in 0 ..< 4 {
            try env.referencePaneManager.addReferenceTab(
                url: #require(URL(string: "https://ref\(i).com")),
                in: space,
            )
        }

        #expect(space.referenceTabs.count == 4)

        // Try to restore - should fail because limit reached
        env.referencePaneManager.restoreReferenceTab(closedInfo)

        #expect(space.referenceTabs.count == 4, "Should not exceed limit")
    }

    @Test("Restore reference tab to missing space logs error")
    func restoreToMissingSpaceLogs() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.referencePaneManager.addReferenceTab(
            url: refURL,
            in: space,
        ))

        env.referencePaneManager.closeReferenceTab(refTab)

        let closedInfo = try #require(env.undoRedoManager.recentlyClosedTabs.first)

        // Delete the space
        env.spaceManager.deleteSpace(space, closeTabs: true)

        // This should log an error but not crash
        env.referencePaneManager.restoreReferenceTab(closedInfo)

        // No reference tab should be restored
        #expect(env.browserState.spaces.flatMap(\.referenceTabs).isEmpty)
    }

    @Test("Restore increments list version")
    func restoreIncrementsVersion() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.referencePaneManager.addReferenceTab(
            url: refURL,
            in: space,
        ))
        env.referencePaneManager.closeReferenceTab(refTab)

        let versionBefore = env.browserState.tabListVersion

        let closedInfo = try #require(env.undoRedoManager.recentlyClosedTabs.first)
        env.referencePaneManager.restoreReferenceTab(closedInfo)

        #expect(env.browserState.tabListVersion > versionBefore)
    }
}

// MARK: - ReferencePaneManager Active Tab Tests

@Suite("ReferencePaneManager Active Tab", .tags(.referencePaneManager), .serialized)
@MainActor
struct ReferencePaneActiveTabTests {
    @Test("Set active reference tab validates tab is reference")
    func setActiveValidatesReference() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let mainTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        // Setting a main tab as active reference should be a no-op
        env.referencePaneManager.setActiveReferenceTab(mainTab, in: windowState)

        // windowState.activeReferenceTabID should remain nil or not be set to mainTab
        #expect(windowState.activeReferenceTabID != mainTab.id)
    }

    @Test("Set active reference tab updates lastAccessed")
    func setActiveUpdatesLastAccessed() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.referencePaneManager.addReferenceTab(
            url: refURL,
            in: space,
        ))

        // Tabs that were never activated don't have lastAccessed set
        #expect(refTab.lastAccessed == nil)

        env.referencePaneManager.setActiveReferenceTab(refTab, in: windowState)

        // After activation, lastAccessed should be set
        #expect(refTab.lastAccessed != nil)
    }

    @Test("Set active reference tab increments content version")
    func setActiveIncrementsVersion() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.referencePaneManager.addReferenceTab(
            url: refURL,
            in: space,
        ))

        let versionBefore = env.browserState.tabContentVersion

        env.referencePaneManager.setActiveReferenceTab(refTab, in: windowState)

        #expect(env.browserState.tabContentVersion > versionBefore)
    }
}

// MARK: - ReferencePaneManager Move To Reference Tests

@Suite("ReferencePaneManager Move To Reference", .tags(.referencePaneManager), .serialized)
@MainActor
struct ReferencePaneMoveToReferenceTests {
    @Test("Move tab to reference rejects multi-page tab")
    func moveRejectsMultiPage() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Need at least 2 main tabs to allow move
        _ = try env.tabManager.createTab(url: #require(URL(string: "https://other.com")), in: space, makeActive: false)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        // Add a second page
        try env.tabManager.addPageToTab(tab, url: #require(URL(string: "https://second.com")), at: .topRight)

        let result = env.referencePaneManager.moveTabToReferencePane(tab)

        #expect(!result, "Multi-page tab should be rejected")
        #expect(!tab.isReferenceTab)
    }

    @Test("Move tab to reference rejects when only one main tab")
    func moveRejectsOnlyTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://only.com")),
            in: space,
            makeActive: true,
        )

        #expect(space.mainTabs.count == 1)

        let result = env.referencePaneManager.moveTabToReferencePane(tab)

        #expect(!result, "Only main tab should be rejected")
        #expect(space.mainTabs.count == 1)
    }

    @Test("Move tab to reference rejects when limit reached")
    func moveRejectsWhenLimitReached() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Fill reference pane
        for i in 0 ..< 4 {
            try env.referencePaneManager.addReferenceTab(
                url: #require(URL(string: "https://ref\(i).com")),
                in: space,
            )
        }

        // Create main tabs
        _ = try env.tabManager.createTab(url: #require(URL(string: "https://main1.com")), in: space, makeActive: false)
        let tabToMove = try env.tabManager.createTab(url: #require(URL(string: "https://main2.com")), in: space, makeActive: true)

        let result = env.referencePaneManager.moveTabToReferencePane(tabToMove)

        #expect(!result, "Should reject when reference pane is full")
        #expect(!tabToMove.isReferenceTab)
    }

    @Test("Move tab to reference converts to reference tab")
    func moveConvertsToReference() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        _ = try env.tabManager.createTab(url: #require(URL(string: "https://other.com")), in: space, makeActive: false)
        let tabToMove = try env.tabManager.createTab(url: #require(URL(string: "https://tomove.com")), in: space, makeActive: true)

        let mainCountBefore = space.mainTabs.count

        let result = env.referencePaneManager.moveTabToReferencePane(tabToMove)

        #expect(result)
        #expect(tabToMove.isReferenceTab)
        #expect(space.referenceTabs.contains(where: { $0.id == tabToMove.id }))
        #expect(space.mainTabs.count == mainCountBefore - 1)
    }

    @Test("Move tab to reference increments list version")
    func moveIncrementsVersion() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        _ = try env.tabManager.createTab(url: #require(URL(string: "https://other.com")), in: space, makeActive: false)
        let tabToMove = try env.tabManager.createTab(url: #require(URL(string: "https://tomove.com")), in: space, makeActive: true)

        let versionBefore = env.browserState.tabListVersion

        env.referencePaneManager.moveTabToReferencePane(tabToMove)

        #expect(env.browserState.tabListVersion > versionBefore)
    }
}

// MARK: - ReferencePaneManager Move To Main Tests

@Suite("ReferencePaneManager Move To Main", .tags(.referencePaneManager), .serialized)
@MainActor
struct ReferencePaneMoveToMainTests {
    @Test("Move reference tab to main converts tab")
    func moveConvertsToMain() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create main tab first
        _ = try env.tabManager.createTab(url: #require(URL(string: "https://main.com")), in: space, makeActive: true)

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.referencePaneManager.addReferenceTab(
            url: refURL,
            in: space,
        ))

        #expect(refTab.isReferenceTab)

        let result = env.referencePaneManager.moveReferenceTabToMainArea(refTab, insertionIndex: 0) { _ in }

        #expect(result)
        #expect(!refTab.isReferenceTab)
        #expect(space.mainTabs.contains(where: { $0.id == refTab.id }))
        #expect(space.referenceTabs.isEmpty)
    }

    @Test("Move reference tab to main renumbers remaining")
    func moveRenumbersRemaining() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        _ = try env.tabManager.createTab(url: #require(URL(string: "https://main.com")), in: space, makeActive: true)

        let url1 = try #require(URL(string: "https://ref1.com"))
        let url2 = try #require(URL(string: "https://ref2.com"))
        let url3 = try #require(URL(string: "https://ref3.com"))
        let ref1 = try #require(env.referencePaneManager.addReferenceTab(url: url1, in: space))
        let ref2 = try #require(env.referencePaneManager.addReferenceTab(url: url2, in: space))
        let ref3 = try #require(env.referencePaneManager.addReferenceTab(url: url3, in: space))

        env.referencePaneManager.moveReferenceTabToMainArea(ref1, insertionIndex: 0) { _ in }

        #expect(ref2.position == 0)
        #expect(ref3.position == 1)
    }

    @Test("Move non-reference tab is no-op")
    func moveNonReferenceIsNoOp() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let mainTab = try env.tabManager.createTab(url: #require(URL(string: "https://main.com")), in: space, makeActive: true)

        let result = env.referencePaneManager.moveReferenceTabToMainArea(mainTab, insertionIndex: 0) { _ in }

        #expect(!result)
    }

    @Test("Move reference tab to main calls normalize callback")
    func moveCallsNormalizeCallback() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        _ = try env.tabManager.createTab(url: #require(URL(string: "https://main.com")), in: space, makeActive: true)

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.referencePaneManager.addReferenceTab(
            url: refURL,
            in: space,
        ))

        var normalizeCalled = false
        var normalizeSpace: Space?

        env.referencePaneManager.moveReferenceTabToMainArea(refTab, insertionIndex: 0) { space in
            normalizeCalled = true
            normalizeSpace = space
        }

        #expect(normalizeCalled)
        #expect(normalizeSpace?.id == space.id)
    }

    @Test("Move reference tab to main increments list version")
    func moveIncrementsVersion() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        _ = try env.tabManager.createTab(url: #require(URL(string: "https://main.com")), in: space, makeActive: true)

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.referencePaneManager.addReferenceTab(
            url: refURL,
            in: space,
        ))

        let versionBefore = env.browserState.tabListVersion

        env.referencePaneManager.moveReferenceTabToMainArea(refTab, insertionIndex: 0) { _ in }

        #expect(env.browserState.tabListVersion > versionBefore)
    }
}
