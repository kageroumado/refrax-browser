import AppKit
import Testing
@testable import Refrax

@Suite(.serialized)
@MainActor
struct ControlIslandTabInfoTests {
    @Test
    func `Control is momentary and hovering preserves reachable actions`() {
        let state = ControlIslandTabInfoState()
        state.hold()
        #expect(state.isVisible)
        state.release()
        #expect(!state.isVisible)
        state.hold()
        state.isHovered = true
        state.release()
        #expect(state.isVisible)
        state.isHovered = false
        #expect(!state.isVisible)
    }

    @Test
    func `native menu survives Control release and clears when it closes`() {
        let state = ControlIslandTabInfoState()
        state.hold()
        state.isMenuPresented = true
        state.release()
        #expect(state.isVisible)
        state.isMenuPresented = false
        #expect(!state.isVisible)
    }

    @Test
    func `native popup builds current actions and owns the card lifetime`() throws {
        let state = ControlIslandTabInfoState()
        let button = ControlIslandTabMenuNSButton(frame: .zero, pullsDown: true)
        button.infoState = state
        var closeCount = 0
        button.onClose = { closeCount += 1 }
        button.makeMenu = {
            let menu = NSMenu()
            menu.addItem(withTitle: "Reload", action: nil, keyEquivalent: "")
            return menu
        }
        let menu = try #require(button.menu)
        button.menuNeedsUpdate(menu)
        button.menuNeedsUpdate(menu)
        #expect(menu.items.map(\.title) == ["", "Reload"])
        state.hold()
        button.menuWillOpen(menu)
        state.release()
        #expect(state.isMenuPresented)
        #expect(state.isVisible)
        #expect(closeCount == 0)
        button.menuDidClose(menu)
        #expect(!state.isMenuPresented)
        #expect(closeCount == 1)
        button.menuWillOpen(menu)
        button.cancelPresentation()
        #expect(!state.isMenuPresented)
    }

    @Test
    func `explicit disclosure stays until dismissal and a held card can be dismissed`() {
        let state = ControlIslandTabInfoState()
        state.show()
        state.release()
        #expect(state.isVisible)
        state.hold()
        state.isHovered = true
        state.dismiss()
        #expect(!state.isVisible)
    }

    @Test
    func `outside clicks dismiss the card while menu tracking preserves it`() {
        let controls = ControlIslandState(defaults: nil, configuration: .init(defaults: nil))
        controls.mode = .button
        controls.hitRegions = [CGRect(x: 10, y: 10, width: 48, height: 500), CGRect(x: 66, y: 10, width: 304, height: 136)]
        controls.tabInfo.show()
        controls.dismissIfOutside(CGPoint(x: 90, y: 60))
        #expect(controls.tabInfo.isVisible)
        controls.tabInfo.isMenuPresented = true
        controls.dismissIfOutside(CGPoint(x: 800, y: 600))
        #expect(controls.tabInfo.isVisible)
        controls.tabInfo.isMenuPresented = false
        controls.dismissIfOutside(CGPoint(x: 800, y: 600))
        #expect(!controls.tabInfo.isVisible)
        #expect(!controls.isRevealed)
    }

    @Test(arguments: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0.5, y: 0.5)])
    func `tab card stays inside each window edge`(point: CGPoint) {
        let bounds = CGRect(x: 0, y: 0, width: 650, height: 400)
        let placement = ControlIslandPlacement(x: point.x, y: point.y)
        let rail = placement.railFrame(in: bounds, height: 500)
        let card = placement.pageBranchFrame(in: bounds, anchor: rail, height: 40)
        #expect(bounds.contains(card))
        #expect(!card.intersects(rail))
    }

    @Test
    func `favorite and unfavorite use the card window and preserve placement`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let cardWindow = env.makeActiveWindowState(with: space)
        let tab = env.createActiveTab(url: try #require(URL(string: "about:blank#current-tab")), in: space, for: cardWindow)
        tab.floatingPlacement = FloatingTabPlacement(x: 0.6, y: 0.3, isCompact: false, isPinned: true)
        let originalPlacement = tab.floatingPlacement
        let otherSpace = env.makeSpace(name: "Other Window")
        let otherWindow = env.makeActiveWindowState(with: otherSpace)
        let otherTab = env.createActiveTab(url: try #require(URL(string: "about:blank#other-tab")), in: otherSpace, for: otherWindow)

        ControlIslandTabActions(tab: tab, windowState: cardWindow, tabs: env.tabManager, bookmarks: env.bookmarksManager).toggleFavorite()
        let favorite = try #require(cardWindow.activeTab)
        #expect(favorite.isLiveFavorite)
        #expect(favorite.activePage.url.absoluteString == "about:blank#current-tab")
        #expect(favorite.floatingPlacement == originalPlacement)
        #expect(otherWindow.activeTabID == otherTab.id)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: cardWindow, pagePool: env.pagePool, groupManager: env.groupManager)
        #expect(canvas.floatingTabs.contains(where: { $0.id == favorite.id }))

        ControlIslandTabActions(tab: favorite, windowState: cardWindow, tabs: env.tabManager, bookmarks: env.bookmarksManager).toggleFavorite()
        #expect(!favorite.isLiveFavorite)
        #expect(favorite.space?.id == space.id)
        #expect(cardWindow.activeTabID == favorite.id)
        #expect(otherWindow.activeTabID == otherTab.id)
        #expect(favorite.floatingPlacement == originalPlacement)
    }

    @Test
    func `duplicating a favorite opens a regular tab in the card window`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let bookmark = env.bookmarksManager.createBookmark(url: try #require(URL(string: "about:blank#favorite")), title: "Favorite", isFavorite: true)
        let favorite = try #require(env.browserState.liveFavoriteTab(for: bookmark.id))
        env.tabManager.setActiveTab(favorite, in: window)
        let other = env.makeActiveWindowState(with: env.makeSpace(name: "Other"))
        let duplicate = try #require(ControlIslandTabActions(tab: favorite, windowState: window, tabs: env.tabManager, bookmarks: env.bookmarksManager).duplicate())
        #expect(duplicate.id != favorite.id)
        #expect(!duplicate.isLiveFavorite)
        #expect(duplicate.space?.id == space.id)
        #expect(window.activeTabID == duplicate.id)
        #expect(other.activeTabID == nil)
        #expect(bookmark.isFavorite)
    }

    @Test
    func `floating reveal and deactivation share the card lifetime`() throws {
        let env = try TabManagerTestEnvironment()
        let window = env.makeActiveWindowState(with: env.makeSpace())
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        canvas.revealFloatingTabs()
        #expect(window.controlIsland.tabInfo.isHeld)
        canvas.releaseFloatingTabs()
        #expect(!window.controlIsland.tabInfo.isVisible)
        window.controlIsland.tabInfo.show()
        canvas.dismissFloatingTabs()
        #expect(!window.controlIsland.tabInfo.isVisible)
    }
}
