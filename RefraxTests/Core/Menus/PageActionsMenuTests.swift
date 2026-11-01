import Foundation
import Testing
@testable import Refrax

/// The ⋯ menus of the page card and the floating cards, as a person reads them.
@Suite(.serialized)
@MainActor
struct PageActionsMenuTests {
    @MainActor
    private struct Fixture {
        let env: TabManagerTestEnvironment
        let space: Space
        let window: WindowState
        let canvas: TabCanvasManager
        let sharing = SharingCoordinator()
        let area = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let active: Tab
        let other: Tab

        init() throws {
            self.env = try TabManagerTestEnvironment()
            self.space = env.makeSpace()
            self.window = env.makeActiveWindowState(with: space)
            self.canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool)
            self.active = try env.createActiveTab(url: #require(URL(string: "https://example.com/active")), in: space, for: window)
            self.other = try env.tabManager.createTab(url: #require(URL(string: "https://example.com/other")), in: space, makeActive: false)
        }

        func tree(for tab: Tab, surface: MenuSurface) -> MenuTree {
            PageActionsMenu.tree(
                for: tab, surface: surface, area: area, windowState: window, tabs: env.tabManager,
                bookmarks: env.bookmarksManager, canvas: canvas, sharing: sharing,
            )
        }

        func keepRegion(on tab: Tab) throws {
            var placement = canvas.floatingPlacement(for: tab)
            placement.isPinned = true
            placement.shape = .live
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
    func `a floating card leads with Look and placement, keeps Close Tab inline, and ends with More`() throws {
        let fixture = try Fixture()
        let tree = fixture.tree(for: fixture.other, surface: .floatingCard)
        #expect(tree.outline == [
            "Look, then Return", "Keep Visible", "Preview ▸ (2)", "  Dock Left", "  Dock Right", "——",
            "Copy Address", "Copy as Markdown Link", "Share…", "——",
            "Rename…", "Duplicate Tab", "Favorite", "——",
            "Close Tab", "——",
            "Move to New Window", "——",
            "More ▸ (2)", "  Mark as Read", "  Open Reflected Window",
        ])
        #expect(tree.ids == [
            "tab.look", "tab.keepVisible", "group.preview", "page.copyAddress", "page.copyMarkdownLink", "page.share",
            "tab.rename", "tab.duplicate", "tab.favorite", "tab.close", "tab.moveToNewWindow", "more",
        ])
    }

    @Test
    func `the page card offers Find, toggles the presentation, and never Look`() throws {
        let fixture = try Fixture()
        _ = try #require(fixture.env.pagePool.page(for: fixture.active.activePage))
        let tree = fixture.tree(for: fixture.active, surface: .pageCard)
        #expect(tree.outline == [
            "Keep Visible", "Preview ▸ (4)", "  Show as Icon", "  Show Live Page", "  Dock Left", "  Dock Right", "——",
            "Copy Address", "Copy as Markdown Link", "Share…", "Find on Page…", "——",
            "Rename…", "Duplicate Tab", "Favorite", "——",
            "Close Tab", "——",
            "Move to New Window", "——",
            "More ▸ (2)", "  Mark as Unread", "  Open Reflected Window",
        ])
        #expect(!tree.ids.contains("tab.look"))
        #expect(tree.outline.contains("  Show Live Page"))
        #expect(!tree.outline.contains("  Show as Tab"))
    }

    @Test
    func `the active tab's floating card keeps the shape verbs for the page card`() throws {
        let fixture = try Fixture()
        let tree = fixture.tree(for: fixture.active, surface: .floatingCard)
        #expect(!tree.ids.contains { $0.hasPrefix("tab.shape.") })
        #expect(!tree.ids.contains("tab.look"))
    }

    @Test
    func `region actions appear only behind the flag and fold on the page card`() throws {
        let fixture = try Fixture()
        try fixture.keepRegion(on: fixture.other)
        #expect(!fixture.tree(for: fixture.other, surface: .floatingCard).ids.contains("tab.region"))

        fixture.env.settings.floatingTabRegionsEnabled = true
        let floating = fixture.tree(for: fixture.other, surface: .floatingCard)
        #expect(topLevel(floating) == [
            "Look, then Return", "Hide Preview", "Preview ▸ (4)", "——", "Copy Address", "Copy as Markdown Link", "Share…", "——",
            "Rename…", "Duplicate Tab", "Favorite", "——", "Close Tab", "——", "Move to New Window", "——", "More ▸ (2)",
        ])

        try fixture.keepRegion(on: fixture.active)
        let page = fixture.tree(for: fixture.active, surface: .pageCard)
        #expect(page.outline.contains("Hide Preview"))
        #expect(page.outline.contains("Preview ▸ (6)"))
        #expect(page.outline.contains("  Show as Icon"))
        #expect(page.outline.contains("  Show as Tab"))
        #expect(page.outline.contains("  Adjust Region…"))
        #expect(page.outline.contains("  Preview Zoom ▸ (6)"))
        #expect(page.outline.contains("    Show Whole Page"))

        let unplaced = try fixture.env.tabManager.createTab(url: #require(URL(string: "https://example.com/new")), in: fixture.space, makeActive: false)
        let fresh = fixture.tree(for: unplaced, surface: .floatingCard)
        #expect(fresh.outline.contains("  Keep Part Visible… (Experimental)"))
        #expect(!fresh.ids.contains("tab.zoom"))
    }

    @Test
    func `a favorite can be removed in the tab family, and stays in every space`() throws {
        let fixture = try Fixture()
        ControlIslandTabActions(tab: fixture.other, windowState: fixture.window, tabs: fixture.env.tabManager, bookmarks: fixture.env.bookmarksManager)
            .toggleFavorite()
        let favorite = try #require(fixture.env.tabManager.state.favoriteTabs.first)
        let tree = fixture.tree(for: favorite, surface: .floatingCard)
        #expect(tree.outline.contains("Remove from Favorites"))
        #expect(!tree.ids.contains("tab.select"))
        #expect(!tree.ids.contains("tab.moveToSpace"))
        #expect(!tree.ids.contains("tab.moveToNewWindow"))
    }

    @Test
    func `the page card's options popover lists the tab actions in the page card menu's layout`() throws {
        let fixture = try Fixture()
        _ = try #require(fixture.env.pagePool.page(for: fixture.active.activePage))
        let rows = PageCardOptionsPopover.tabTree(
            for: fixture.active, area: fixture.area, windowState: fixture.window, tabs: fixture.env.tabManager,
            bookmarks: fixture.env.bookmarksManager, canvas: fixture.canvas,
        )
        #expect(rows.outline == [
            "Keep Visible", "Preview ▸ (4)", "  Show as Icon", "  Show Live Page", "  Dock Left", "  Dock Right", "——",
            "Rename…", "Duplicate Tab", "Favorite", "——", "Close Tab", "——", "Move to New Window", "——",
            "More ▸ (2)", "  Mark as Unread", "  Open Reflected Window",
        ])
        // The same layout as the page card's menu, without the page's rows the popover lists above it.
        let card = fixture.tree(for: fixture.active, surface: .pageCard)
        #expect(card.ids.filter { !$0.hasPrefix("page.") } == rows.ids)
        #expect(rows.ids.allSatisfy { $0.hasPrefix("tab.") || $0.hasPrefix("group.") || $0 == "more" })
    }

    @Test
    func `Move to Space lists the other spaces as a submenu`() throws {
        let fixture = try Fixture()
        _ = fixture.env.makeSpace(name: "Research")
        let tree = fixture.tree(for: fixture.other, surface: .floatingCard)
        #expect(tree.ids.contains("tab.moveToSpace"))
        #expect(tree.outline.contains("  Research"))
        #expect(!tree.outline.contains("  \(fixture.space.name)"))
    }
}
