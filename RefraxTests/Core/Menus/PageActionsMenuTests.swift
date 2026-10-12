import Foundation
import Testing
@testable import Refrax

/// The ⋯ menus of the page card and the floating cards, as a person reads them.
@Suite(.serialized)
@MainActor
struct PageActionsMenuTests {
    @MainActor private struct Fixture {
        let env: TabManagerTestEnvironment
        let space: Space
        let window: WindowState
        let canvas: TabCanvasManager
        let readerMode: ReaderModeManager
        let sharing = SharingCoordinator()
        let area = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let active: Tab
        let other: Tab

        init() throws {
            self.env = try TabManagerTestEnvironment()
            self.space = env.makeSpace()
            self.window = env.makeActiveWindowState(with: space)
            self.canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
            self.readerMode = ReaderModeManager(state: env.browserState)
            self.active = env.createActiveTab(url: try #require(URL(string: "https://example.com/active")), in: space, for: window)
            self.other = env.tabManager.createTab(url: try #require(URL(string: "https://example.com/other")), in: space, makeActive: false)
        }

        func tree(for tab: Tab, surface: MenuSurface) -> MenuTree {
            PageActionsMenu.tree(
                for: tab, surface: surface, area: area, windowState: window, tabs: env.tabManager,
                bookmarks: env.bookmarksManager, canvas: canvas, readerMode: readerMode, sharing: sharing,
            )
        }

        func keepRegion(on tab: Tab) throws {
            var placement = canvas.floatingPlacement(for: tab)
            placement.isPinned = true
            placement.isCompact = false
            placement.region = FloatingPageRegion(
                sourceURL: tab.activePage.url, viewportSize: CGSize(width: 800, height: 600), rect: CGRect(x: 10, y: 10, width: 200, height: 100),
            )
            try #require(placement.region?.isValid == true)
            canvas.updateFloatingPlacement(placement, for: tab)
        }
    }

    private func topLevel(_ tree: MenuTree) -> [String] {
        tree.outline.filter { !$0.hasPrefix(" ") }
    }

    @Test
    func `a floating card offers the page, Look, placement, selection, and the tab`() throws {
        let fixture = try Fixture()
        let tree = fixture.tree(for: fixture.other, surface: .floatingCard)
        #expect(tree.outline == [
            "Copy Address", "Copy as Markdown Link", "——", "Share…", "Look, then Return", "Keep Visible", "Select for Group", "Duplicate Tab", "Close Tab",
        ])
        #expect(tree.ids == [
            "page.copyAddress", "page.copyMarkdownLink", "page.share", "tab.look", "tab.keepVisible", "tab.select", "tab.duplicate", "tab.close",
        ])
    }

    @Test
    func `the page card offers Find and Reader, toggles the presentation, and never Look`() throws {
        let fixture = try Fixture()
        _ = try #require(fixture.env.pagePool.page(for: fixture.active.activePage))
        let tree = fixture.tree(for: fixture.active, surface: .pageCard)
        #expect(tree.outline == [
            "Copy Address", "Copy as Markdown Link", "——", "Share…", "——", "Find on Page…", "Reader", "——", "Keep Visible", "Show as Preview", "——",
            "Select for Group", "Duplicate Tab", "Close Tab",
        ])
        #expect(!tree.ids.contains("tab.look"))
        #expect(tree.ids.contains("tab.compact"))
    }

    @Test
    func `the active tab's floating card keeps the presentation toggle for the page card`() throws {
        let fixture = try Fixture()
        let tree = fixture.tree(for: fixture.active, surface: .floatingCard)
        #expect(!tree.ids.contains("tab.compact"))
        #expect(!tree.ids.contains("tab.look"))
    }

    @Test
    func `pinned with a selection, Show in Every Space and Group Selected Tabs join the selection section`() throws {
        let fixture = try Fixture()
        var placement = fixture.canvas.floatingPlacement(for: fixture.other)
        placement.isPinned = true
        placement.isCompact = false
        fixture.canvas.updateFloatingPlacement(placement, for: fixture.other)
        fixture.canvas.selectedFloatingTabIDs = [fixture.other.id, fixture.active.id]
        let tree = fixture.tree(for: fixture.other, surface: .floatingCard)
        #expect(tree.outline == [
            "Copy Address", "Copy as Markdown Link", "——", "Share…", "Look, then Return", "Hide Preview", "——",
            "Deselect for Group", "Group Selected Tabs", "Show in Every Space", "——", "Duplicate Tab", "Close Tab",
        ])
    }

    @Test
    func `region actions appear only behind the flag and fold on the page card`() throws {
        let fixture = try Fixture()
        try fixture.keepRegion(on: fixture.other)
        #expect(!fixture.tree(for: fixture.other, surface: .floatingCard).ids.contains("tab.region"))

        fixture.env.settings.floatingTabRegionsEnabled = true
        let floating = fixture.tree(for: fixture.other, surface: .floatingCard)
        #expect(topLevel(floating) == [
            "Copy Address", "Copy as Markdown Link", "——", "Share…", "Look, then Return", "——", "Hide Preview", "Adjust Region…", "Preview Zoom ▸ (6)", "——",
            "Select for Group", "Show in Every Space", "——", "Duplicate Tab", "Close Tab",
        ])

        try fixture.keepRegion(on: fixture.active)
        let page = fixture.tree(for: fixture.active, surface: .pageCard)
        #expect(page.outline.contains("Hide Preview"))
        #expect(page.outline.contains("Preview ▸ (3)"))
        #expect(page.outline.contains("  Show as Compact Tab"))
        #expect(page.outline.contains("  Adjust Region…"))
        #expect(page.outline.contains("  Preview Zoom ▸ (6)"))
        #expect(page.outline.contains("    Show Whole Page"))

        let unplaced = fixture.env.tabManager.createTab(url: try #require(URL(string: "https://example.com/new")), in: fixture.space, makeActive: false)
        let fresh = fixture.tree(for: unplaced, surface: .floatingCard)
        #expect(fresh.outline.contains("Keep Part Visible… (Experimental)"))
        #expect(!fresh.ids.contains("tab.zoom"))
    }

    @Test
    func `a favorite can update its saved address beside Duplicate`() throws {
        let fixture = try Fixture()
        ControlIslandTabActions(tab: fixture.other, windowState: fixture.window, tabs: fixture.env.tabManager, bookmarks: fixture.env.bookmarksManager)
            .toggleFavorite()
        let favorite = try #require(fixture.env.tabManager.state.liveFavoriteTabs.first)
        let tree = fixture.tree(for: favorite, surface: .floatingCard)
        #expect(Array(topLevel(tree).suffix(4)) == ["Update Saved Address", "Duplicate Tab", "——", "Close Tab"])
        #expect(!tree.ids.contains("tab.select"))
    }
}
