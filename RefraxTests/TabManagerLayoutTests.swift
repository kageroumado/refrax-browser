import Foundation
import SwiftData
import SwiftUI
import Testing
import WebKit
@testable import Refrax

// MARK: - TabManager+Layout Tests

@Suite("TabManager Multi-Page Layout", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerMultiPageLayoutTests {
    @Test
    func `Add page to tab creates multi-page layout`() throws {
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
            at: .cell(.topRight),
        )

        #expect(tab.pages.count == 2, "Should have 2 pages")
        #expect(newPage.position == .topRight, "Page should be at specified position")
        #expect(tab.isMultiPage, "Should have layout after adding page")
    }

    @Test
    func `Add page increments list version`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        let versionBefore = env.browserState.tabListVersion

        try env.tabManager.addPageToTab(tab, url: #require(URL(string: "https://second.com")), at: .cell(.topRight))

        #expect(env.browserState.tabListVersion > versionBefore)
    }

    @Test
    func `Remove page from tab updates layout`() throws {
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
            at: .cell(.topRight),
        )

        #expect(tab.pages.count == 2)

        env.tabManager.removePageFromTab(tab, page: secondPage)

        #expect(tab.pages.count == 1, "Should have 1 page")
    }

    @Test
    func `Move tab to layout requires single-page source`() throws {
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
        try env.tabManager.addPageToTab(sourceTab, url: #require(URL(string: "https://extra.com")), at: .cell(.topRight))

        #expect(sourceTab.pages.count == 2)

        let result = env.tabManager.moveTabToLayout(sourceTab, into: destTab, at: .cell(.topRight))

        #expect(result == nil, "Should not move multi-page tab into layout")
    }

    @Test
    func `Move tab to layout transfers page`() throws {
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

        let newPage = env.tabManager.moveTabToLayout(sourceTab, into: destTab, at: .cell(.topRight))

        #expect(newPage != nil, "Should return new page")
        #expect(destTab.pages.count == 2, "Destination should have 2 pages")
        #expect(space.tabs.count == initialTabCount - 1, "Source tab should be removed")
        #expect(!space.tabs.contains(where: { $0.id == sourceTabID }), "Source tab should be gone")
    }

    @Test
    func `Move tab to layout preserves favicon`() throws {
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

        let newPage = env.tabManager.moveTabToLayout(sourceTab, into: destTab, at: .cell(.topRight))

        #expect(newPage?.faviconData == faviconData, "Favicon should be preserved")
    }

    @Test
    func `Move page to new tab requires multi-page source`() throws {
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

    @Test
    func `Move page to new tab creates tab`() throws {
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
            at: .cell(.topRight),
        )

        let initialTabCount = space.tabs.count

        let newTab = env.tabManager.movePageToNewTab(secondPage, from: tab)

        #expect(newTab != nil, "Should create new tab")
        #expect(tab.pages.count == 1, "Source tab should have 1 page")
        #expect(space.tabs.count == initialTabCount + 1, "Should have one more tab")
    }

    @Test
    func `Move page to new tab activates if makeActive=true`() throws {
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
            at: .cell(.topRight),
        )

        let newTab = env.tabManager.movePageToNewTab(secondPage, from: tab, makeActive: true)

        #expect(windowState.activeTabID == newTab?.id, "New tab should be active")
    }

    @Test
    func `Move page to new tab updates source active page`() throws {
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
            at: .cell(.topRight),
        )

        // Make second page active via manager (mutation methods are internal)
        env.tabManager.setActivePage(in: tab, page: secondPage)
        #expect(tab.activePage.id == secondPage.id)

        env.tabManager.movePageToNewTab(secondPage, from: tab, makeActive: false)

        // Source tab should now have first page as active
        #expect(tab.activePage.id == tab.pages.first?.id, "Should fall back to first page")
    }

    @Test
    func `Set active page updates active page property`() throws {
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
            at: .cell(.topRight),
        )

        let originalActivePage = tab.activePage

        env.tabManager.setActivePage(in: tab, page: secondPage)

        #expect(tab.activePage.id == secondPage.id, "Active page should be updated")
        #expect(tab.activePage.id != originalActivePage.id)
    }

    @Test
    func `Add multiple pages fills positions`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://main.com")),
            in: space,
            makeActive: true,
        )

        try env.tabManager.addPageToTab(tab, url: #require(URL(string: "https://two.com")), at: .cell(.topRight))
        try env.tabManager.addPageToTab(tab, url: #require(URL(string: "https://three.com")), at: .cell(.bottomLeft))
        try env.tabManager.addPageToTab(tab, url: #require(URL(string: "https://four.com")), at: .cell(.bottomRight))

        #expect(tab.pages.count == 4, "Should have 4 pages")

        // Verify all positions are used
        let positions = tab.pages.compactMap(\.position)
        #expect(positions.contains(.topRight))
        #expect(positions.contains(.bottomLeft))
        #expect(positions.contains(.bottomRight))
    }
}
