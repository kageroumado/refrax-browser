import Foundation
import SwiftData
import SwiftUI
import Testing
import WebKit
@testable import Refrax

// MARK: - TabManager+Layout Tests

@Suite("TabManager Reference Tab Operations", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerReferenceTabTests {
    @Test("Add reference tab creates tab in reference pane")
    func addReferenceTabCreatesTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let refTab = try env.tabManager.addReferenceTab(
            url: #require(URL(string: "https://reference.com")),
            title: "Reference Tab",
            in: space,
        )

        #expect(refTab != nil, "Should create reference tab")
        #expect(refTab?.isReferenceTab == true, "Tab should be marked as reference")
        #expect(space.referenceTabs.contains(where: { $0.id == refTab?.id }), "Space should contain reference tab")
    }

    @Test("Add reference tab respects limit of 4")
    func addReferenceTabRespectsLimit() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Add 4 reference tabs (the max)
        for i in 0 ..< 4 {
            let tab = try env.tabManager.addReferenceTab(
                url: #require(URL(string: "https://ref\(i).com")),
                in: space,
            )
            #expect(tab != nil, "Should create reference tab \(i)")
        }

        #expect(space.referenceTabs.count == 4, "Should have 4 reference tabs")

        // Fifth should fail
        let fifthTab = try env.tabManager.addReferenceTab(
            url: #require(URL(string: "https://ref5.com")),
            in: space,
        )

        #expect(fifthTab == nil, "Fifth reference tab should not be created")
        #expect(space.referenceTabs.count == 4, "Should still have 4 reference tabs")
    }

    @Test("Close reference tab removes from space")
    func closeReferenceTabRemovesFromSpace() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.tabManager.addReferenceTab(
            url: refURL,
            in: space,
        ))

        #expect(space.referenceTabs.count == 1)

        env.tabManager.closeReferenceTab(refTab)

        #expect(space.referenceTabs.isEmpty, "Reference tab should be removed")
    }

    @Test("Close reference tab registers with undo manager")
    func closeReferenceTabRegistersUndo() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.tabManager.addReferenceTab(
            url: refURL,
            in: space,
        ))

        let initialClosedCount = env.undoRedoManager.recentlyClosedTabs.count

        env.tabManager.closeReferenceTab(refTab)

        #expect(env.undoRedoManager.recentlyClosedTabs.count > initialClosedCount, "Should register in undo")
    }

    @Test("Close last reference tab removes it from space")
    func closeLastReferenceTabRemovesFromSpace() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.tabManager.addReferenceTab(
            url: refURL,
            in: space,
        ))

        #expect(space.referenceTabs.count == 1)

        env.tabManager.closeReferenceTab(refTab)

        #expect(space.referenceTabs.isEmpty)
    }

    @Test("Close reference tab renumbers remaining tabs")
    func closeReferenceTabRenumbersRemaining() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let url1 = try #require(URL(string: "https://ref1.com"))
        let url2 = try #require(URL(string: "https://ref2.com"))
        let url3 = try #require(URL(string: "https://ref3.com"))
        let ref1 = try #require(env.tabManager.addReferenceTab(url: url1, in: space))
        let ref2 = try #require(env.tabManager.addReferenceTab(url: url2, in: space))
        let ref3 = try #require(env.tabManager.addReferenceTab(url: url3, in: space))

        #expect(ref1.position == 0)
        #expect(ref2.position == 1)
        #expect(ref3.position == 2)

        // Close middle tab
        env.tabManager.closeReferenceTab(ref2)

        // Remaining tabs should be renumbered
        #expect(ref1.position == 0)
        #expect(ref3.position == 1, "ref3 should be renumbered to position 1")
    }

    @Test("Add reference tab returns nil for nil space with no active window")
    func addReferenceTabNilSpaceNoWindow() throws {
        let env = try TabManagerTestEnvironment()
        // No active window state created

        let refTab = try env.tabManager.addReferenceTab(
            url: #require(URL(string: "https://reference.com")),
        )

        #expect(refTab == nil, "Should return nil when no space or window available")
    }
}

@Suite("TabManager Tab Transfer", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerTabTransferTests {
    @Test("Move tab to reference pane rejects multi-page tab")
    func moveTabToReferenceRejectsMultiPage() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        // Add a second page to make it multi-page
        try env.tabManager.addPageToTab(tab, url: #require(URL(string: "https://second.com")), at: .topRight)

        #expect(tab.pages.count == 2, "Tab should have 2 pages")

        // Attempt to move - should fail
        env.tabManager.moveTabToReferencePane(tab)

        #expect(!tab.isReferenceTab, "Multi-page tab should not be moved to reference")
        #expect(space.referenceTabs.isEmpty, "No reference tabs should exist")
    }

    @Test("Move tab to reference pane rejects when only one main tab")
    func moveTabToReferenceRejectsOnlyTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://only.com")),
            in: space,
            makeActive: true,
        )

        #expect(space.mainTabs.count == 1, "Should only have one main tab")

        env.tabManager.moveTabToReferencePane(tab)

        #expect(!tab.isReferenceTab, "Only main tab should not be moved")
        #expect(space.mainTabs.count == 1, "Should still have one main tab")
    }

    @Test("Move tab to reference pane activates adjacent tab")
    func moveTabToReferenceActivatesAdjacent() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab1 = try env.tabManager.createTab(
            url: #require(URL(string: "https://one.com")),
            in: space,
            makeActive: false,
        )
        let activeTab = try env.createActiveTab(
            url: #require(URL(string: "https://active.com")),
            in: space,
            for: windowState,
        )
        let tab3 = try env.tabManager.createTab(
            url: #require(URL(string: "https://three.com")),
            in: space,
            makeActive: false,
        )

        #expect(windowState.activeTabID == activeTab.id)

        env.tabManager.moveTabToReferencePane(activeTab)

        #expect(activeTab.isReferenceTab, "Tab should be in reference pane")
        #expect(windowState.activeTabID != activeTab.id, "Should have new active tab")
        #expect(windowState.activeTabID == tab1.id || windowState.activeTabID == tab3.id, "Should activate adjacent tab")
    }

    @Test("Move reference tab to main area converts tab")
    func moveReferenceTabToMainConverts() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create main tab first
        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.tabManager.addReferenceTab(
            url: refURL,
            in: space,
        ))

        #expect(refTab.isReferenceTab)
        #expect(space.referenceTabs.count == 1)
        #expect(space.mainTabs.count == 1)

        env.tabManager.moveReferenceTabToMainArea(refTab)

        #expect(!refTab.isReferenceTab, "Tab should no longer be a reference tab")
        #expect(space.referenceTabs.isEmpty, "Reference pane should be empty")
        #expect(space.mainTabs.count == 2, "Main area should have 2 tabs")
    }

    @Test("Move reference tab to main area activates if makeActive=true")
    func moveReferenceTabToMainActivates() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let mainTab = try env.createActiveTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            for: windowState,
        )

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.tabManager.addReferenceTab(
            url: refURL,
            in: space,
        ))

        #expect(windowState.activeTabID == mainTab.id)

        env.tabManager.moveReferenceTabToMainArea(refTab, makeActive: true)

        #expect(windowState.activeTabID == refTab.id, "Moved tab should be active")
    }

    @Test("Move reference tab to main renumbers remaining reference tabs")
    func moveReferenceTabToMainRenumbers() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        _ = try env.createActiveTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            for: windowState,
        )

        let url1 = try #require(URL(string: "https://ref1.com"))
        let url2 = try #require(URL(string: "https://ref2.com"))
        let url3 = try #require(URL(string: "https://ref3.com"))
        let ref1 = try #require(env.tabManager.addReferenceTab(url: url1, in: space))
        let ref2 = try #require(env.tabManager.addReferenceTab(url: url2, in: space))
        let ref3 = try #require(env.tabManager.addReferenceTab(url: url3, in: space))

        env.tabManager.moveReferenceTabToMainArea(ref1)

        // Remaining reference tabs should be renumbered
        #expect(ref2.position == 0, "ref2 should now be position 0")
        #expect(ref3.position == 1, "ref3 should now be position 1")
    }
}

@Suite("TabManager Page Transfer", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerPageTransferTests {
    @Test("Move page to reference pane - single page tab moves whole tab")
    func movePageSinglePageMovesWholeTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://other.com")),
            in: space,
            makeActive: false,
        )

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://single.com")),
            in: space,
            makeActive: true,
        )

        #expect(tab.pages.count == 1)

        let page = tab.activePage
        env.tabManager.movePageToReferencePane(page, from: tab)

        // Whole tab should be in reference
        #expect(tab.isReferenceTab, "Single-page tab should be moved entirely")
        #expect(space.referenceTabs.count == 1)
    }

    @Test("Move page to reference pane - multi page creates new reference tab")
    func movePageMultiPageCreatesNewRef() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        // Add second page
        let secondPage = try env.tabManager.addPageToTab(tab, url: #require(URL(string: "https://second.com")), at: .topRight)

        #expect(tab.pages.count == 2)

        env.tabManager.movePageToReferencePane(secondPage, from: tab)

        #expect(tab.pages.count == 1, "Source tab should have one page")
        #expect(!tab.isReferenceTab, "Source tab should remain main tab")
        #expect(space.referenceTabs.count == 1, "Should have one reference tab")
    }

    @Test("Move page to reference pane respects limit")
    func movePageToReferenceRespectsLimit() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Fill up reference pane
        for i in 0 ..< 4 {
            try env.tabManager.addReferenceTab(url: #require(URL(string: "https://ref\(i).com")), in: space)
        }

        #expect(space.referenceTabs.count == 4)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        let secondPage = try env.tabManager.addPageToTab(tab, url: #require(URL(string: "https://second.com")), at: .topRight)

        env.tabManager.movePageToReferencePane(secondPage, from: tab)

        #expect(tab.pages.count == 2, "Page should not be moved when limit reached")
        #expect(space.referenceTabs.count == 4, "Reference tabs should still be at limit")
    }

    @Test("Move reference tab to page adds to target tab")
    func moveReferenceTabToPageAddsToTarget() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let mainTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.tabManager.addReferenceTab(
            url: refURL,
            in: space,
        ))

        #expect(mainTab.pages.count == 1)
        #expect(space.referenceTabs.count == 1)

        env.tabManager.moveReferenceTabToPage(refTab, into: mainTab, at: .topRight)

        #expect(mainTab.pages.count == 2, "Target tab should have 2 pages")
        #expect(space.referenceTabs.isEmpty, "Reference pane should be empty")
    }

    @Test("Move reference tab to page respects 4 page limit")
    func moveReferenceTabToPageRespectsLimit() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let mainTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        // Add pages until at limit
        try env.tabManager.addPageToTab(mainTab, url: #require(URL(string: "https://page2.com")), at: .topRight)
        try env.tabManager.addPageToTab(mainTab, url: #require(URL(string: "https://page3.com")), at: .bottomLeft)
        try env.tabManager.addPageToTab(mainTab, url: #require(URL(string: "https://page4.com")), at: .bottomRight)

        #expect(mainTab.pages.count == 4)

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.tabManager.addReferenceTab(
            url: refURL,
            in: space,
        ))

        env.tabManager.moveReferenceTabToPage(refTab, into: mainTab)

        #expect(mainTab.pages.count == 4, "Should not add beyond 4 pages")
        #expect(space.referenceTabs.count == 1, "Reference tab should remain")
    }

    @Test("Move reference tab to page activates page in target")
    func moveReferenceTabToPageActivatesPage() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let mainTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        let refURL = try #require(URL(string: "https://reference.com"))
        let refTab = try #require(env.tabManager.addReferenceTab(
            url: refURL,
            in: space,
        ))

        let originalActivePage = mainTab.activePage

        env.tabManager.moveReferenceTabToPage(refTab, into: mainTab, at: .topRight)

        #expect(mainTab.activePage.id != originalActivePage.id, "Active page should change")
    }
}

@Suite("TabManager Multi-Page Layout", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerMultiPageLayoutTests {
    @Test("Add page to tab creates multi-page layout")
    func addPageToTabCreatesLayout() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        #expect(tab.pages.count == 1)
        #expect(!tab.isMultiPage, "Single page should not have layout")

        let newPage = try env.tabManager.addPageToTab(
            tab,
            url: #require(URL(string: "https://second.com")),
            at: .topRight,
        )

        #expect(tab.pages.count == 2, "Should have 2 pages")
        #expect(newPage.position == .topRight, "Page should be at specified position")
        #expect(tab.isMultiPage, "Should have layout after adding page")
    }

    @Test("Add page increments list version")
    func addPageIncrementsVersion() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        let versionBefore = env.browserState.tabListVersion

        try env.tabManager.addPageToTab(tab, url: #require(URL(string: "https://second.com")), at: .topRight)

        #expect(env.browserState.tabListVersion > versionBefore)
    }

    @Test("Remove page from tab updates layout")
    func removePageFromTabUpdatesLayout() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        let secondPage = try env.tabManager.addPageToTab(
            tab,
            url: #require(URL(string: "https://second.com")),
            at: .topRight,
        )

        #expect(tab.pages.count == 2)

        env.tabManager.removePageFromTab(tab, page: secondPage)

        #expect(tab.pages.count == 1, "Should have 1 page")
    }

    @Test("Move tab to layout requires single-page source")
    func moveTabToLayoutRequiresSinglePage() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let destTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://dest.com")),
            in: space,
            makeActive: true,
        )

        let sourceTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://source.com")),
            in: space,
            makeActive: false,
        )

        // Make source multi-page
        try env.tabManager.addPageToTab(sourceTab, url: #require(URL(string: "https://extra.com")), at: .topRight)

        #expect(sourceTab.pages.count == 2)

        let result = env.tabManager.moveTabToLayout(sourceTab, into: destTab, at: .topRight)

        #expect(result == nil, "Should not move multi-page tab into layout")
    }

    @Test("Move tab to layout transfers page")
    func moveTabToLayoutTransfersPage() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let destTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://dest.com")),
            in: space,
            makeActive: true,
        )

        let sourceTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://source.com")),
            in: space,
            makeActive: false,
        )

        let sourceTabID = sourceTab.id
        let initialTabCount = space.tabs.count

        let newPage = env.tabManager.moveTabToLayout(sourceTab, into: destTab, at: .topRight)

        #expect(newPage != nil, "Should return new page")
        #expect(destTab.pages.count == 2, "Destination should have 2 pages")
        #expect(space.tabs.count == initialTabCount - 1, "Source tab should be removed")
        #expect(!space.tabs.contains(where: { $0.id == sourceTabID }), "Source tab should be gone")
    }

    @Test("Move tab to layout preserves favicon")
    func moveTabToLayoutPreservesFavicon() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let destTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://dest.com")),
            in: space,
            makeActive: true,
        )

        let sourceTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://source.com")),
            in: space,
            makeActive: false,
        )

        let faviconData = Data([0x89, 0x50, 0x4E, 0x47])
        sourceTab.activePage.faviconData = faviconData

        let newPage = env.tabManager.moveTabToLayout(sourceTab, into: destTab, at: .topRight)

        #expect(newPage?.faviconData == faviconData, "Favicon should be preserved")
    }

    @Test("Move page to new tab requires multi-page source")
    func movePageToNewTabRequiresMultiPage() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://single.com")),
            in: space,
            makeActive: true,
        )

        #expect(tab.pages.count == 1)

        let result = env.tabManager.movePageToNewTab(tab.activePage, from: tab)

        #expect(result == nil, "Should not move from single-page tab")
    }

    @Test("Move page to new tab creates tab")
    func movePageToNewTabCreatesTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        let secondPage = try env.tabManager.addPageToTab(
            tab,
            url: #require(URL(string: "https://second.com")),
            at: .topRight,
        )

        let initialTabCount = space.tabs.count

        let newTab = env.tabManager.movePageToNewTab(secondPage, from: tab)

        #expect(newTab != nil, "Should create new tab")
        #expect(tab.pages.count == 1, "Source tab should have 1 page")
        #expect(space.tabs.count == initialTabCount + 1, "Should have one more tab")
    }

    @Test("Move page to new tab activates if makeActive=true")
    func movePageToNewTabActivates() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab = try env.createActiveTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            for: windowState,
        )

        let secondPage = try env.tabManager.addPageToTab(
            tab,
            url: #require(URL(string: "https://second.com")),
            at: .topRight,
        )

        let newTab = env.tabManager.movePageToNewTab(secondPage, from: tab, makeActive: true)

        #expect(windowState.activeTabID == newTab?.id, "New tab should be active")
    }

    @Test("Move page to new tab updates source active page")
    func movePageToNewTabUpdatesSourceActivePage() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        let secondPage = try env.tabManager.addPageToTab(
            tab,
            url: #require(URL(string: "https://second.com")),
            at: .topRight,
        )

        // Make second page active via manager (mutation methods are internal)
        env.tabManager.setActivePage(in: tab, page: secondPage)
        #expect(tab.activePage.id == secondPage.id)

        env.tabManager.movePageToNewTab(secondPage, from: tab, makeActive: false)

        // Source tab should now have first page as active
        #expect(tab.activePage.id == tab.pages.first?.id, "Should fall back to first page")
    }

    @Test("Set active page updates active page property")
    func setActivePageUpdatesProperty() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        let secondPage = try env.tabManager.addPageToTab(
            tab,
            url: #require(URL(string: "https://second.com")),
            at: .topRight,
        )

        let originalActivePage = tab.activePage

        env.tabManager.setActivePage(in: tab, page: secondPage)

        #expect(tab.activePage.id == secondPage.id, "Active page should be updated")
        #expect(tab.activePage.id != originalActivePage.id)
    }

    @Test("Next available position returns topRight for single page tab")
    func nextAvailablePositionSinglePage() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        #expect(tab.pages.count == 1)

        let nextPos = env.tabManager.nextAvailablePosition(in: tab)

        #expect(nextPos == .topRight, "First additional page should be at topRight")
    }

    @Test("Add multiple pages fills positions")
    func addMultiplePagesFillsPositions() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        try env.tabManager.addPageToTab(tab, url: #require(URL(string: "https://two.com")), at: .topRight)
        try env.tabManager.addPageToTab(tab, url: #require(URL(string: "https://three.com")), at: .bottomLeft)
        try env.tabManager.addPageToTab(tab, url: #require(URL(string: "https://four.com")), at: .bottomRight)

        #expect(tab.pages.count == 4, "Should have 4 pages")

        // Verify all positions are used
        let positions = tab.pages.compactMap(\.position)
        #expect(positions.contains(.topRight))
        #expect(positions.contains(.bottomLeft))
        #expect(positions.contains(.bottomRight))
    }
}
