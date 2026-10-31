import AppKit
import Foundation
import Testing
@testable import Refrax

/// A row dragged from an island onto the page joins the current tab as a pane where it was
/// let go: beside the pane under the pointer, or in an empty cell while layout mode is on.
@Suite(.serialized)
@MainActor
struct IslandPaneJoinTests {
    @MainActor
    private final class Fixture {
        let env: TabManagerTestEnvironment
        let space: Space
        let window: WindowState
        let canvas: TabCanvasManager
        let islands: IslandController
        let bounds = CGRect(x: 0, y: 0, width: 1_440, height: 1_080)
        private let suite = "IslandPaneJoinTests.\(UUID().uuidString)"

        init() throws {
            self.env = try TabManagerTestEnvironment()
            self.space = env.makeSpace()
            self.window = env.makeActiveWindowState(with: space)
            self.canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool)
            self.islands = try IslandController(
                windowState: window, tabManager: env.tabManager, groupManager: env.groupManager, canvas: canvas, pagePool: env.pagePool,
                defaults: #require(UserDefaults(suiteName: suite)),
            )
            window.islandController = islands
            islands.start()
            islands.updateArea(bounds.insetBy(dx: 16, dy: 16), in: bounds)
        }

        isolated deinit { islands.stop() }

        func tab(_ title: String) -> Refrax.Tab {
            let tab = env.tabManager.createTab(url: .blank, in: space, makeActive: false, loadImmediately: false)
            tab.activePage.title = title
            islands.refresh()
            return tab
        }

        func show(_ tab: Refrax.Tab) {
            window.setActiveTabID(tab.id, for: space.id)
            islands.refresh()
        }
    }

    @Test(arguments: [
        (PaneEdge.bottom, CGPoint(x: 720, y: 1_050)),
        (.top, CGPoint(x: 720, y: 30)),
        (.leading, CGPoint(x: 30, y: 540)),
        (.trailing, CGPoint(x: 1_410, y: 540)),
    ])
    func `A row let go near a side of the page joins the page on that side`(edge: PaneEdge, point: CGPoint) throws {
        let fixture = try Fixture()
        let page = fixture.tab("Page")
        let row = fixture.tab("Row")
        fixture.show(page)
        let target = page.activePage.id

        fixture.islands.updateRowDrag(row.id, at: point)
        #expect(fixture.islands.sideDrop == .split(PaneSplit(target: target, edge: edge)))
        fixture.islands.finishRowDrag(row.id, at: point)

        #expect(page.pages.count == 2)
        let joined = try #require(page.pages.first { $0.id != target })
        #expect(page.paneGrid.span(of: joined.id) == PaneSpan.whole.half(at: edge))
        #expect(fixture.env.browserState.tab(for: row.id) == nil)
    }

    @Test
    func `The middle of the page joins nothing`() throws {
        let fixture = try Fixture()
        let page = fixture.tab("Page")
        let row = fixture.tab("Row")
        fixture.show(page)
        fixture.islands.updateRowDrag(row.id, at: CGPoint(x: 720, y: 540))
        #expect(fixture.islands.sideDrop == nil)
        fixture.islands.cancelRowDrag()
    }

    @Test
    func `In layout mode a row let go on an empty cell joins the page there`() throws {
        let fixture = try Fixture()
        let page = fixture.tab("Page")
        let row = fixture.tab("Row")
        fixture.show(page)
        let first = page.activePage.id
        let second = try fixture.env.tabManager.addPageToTab(page, url: #require(URL(string: "https://two.example")), at: .cell(.topRight))
        fixture.window.enterLayoutMode()
        fixture.window.editLayout(animated: false) { $0.shrink(first, from: .bottom) }
        let point = CGPoint(x: 300, y: 900)

        fixture.islands.updateRowDrag(row.id, at: point)
        #expect(fixture.islands.sideDrop == .cell(.bottomLeft))
        fixture.islands.finishRowDrag(row.id, at: point)
        fixture.window.exitLayoutMode(animated: false)

        let joined = try #require(page.pages.first { $0.id != first && $0.id != second.id })
        #expect(page.paneGrid.span(of: joined.id) == PaneSpan(.bottomLeft))
        #expect(page.paneGrid.span(of: first) == PaneSpan(.topLeft))
    }

    @Test
    func `A tab of four panes takes no more`() throws {
        let fixture = try Fixture()
        let page = fixture.tab("Page")
        for host in ["two", "three", "four"] {
            try fixture.env.tabManager.addPageToTab(page, url: #require(URL(string: "https://\(host).example")), at: .automatic)
        }
        let row = fixture.tab("Row")
        fixture.show(page)
        #expect(fixture.islands.canJoin(row.id, with: page.id) == false)
        fixture.islands.updateRowDrag(row.id, at: CGPoint(x: 720, y: 1_050))
        #expect(fixture.islands.sideDrop == nil)
        fixture.islands.cancelRowDrag()
    }
}
