import AppKit
import Foundation
import Observation
import Testing
@testable import Refrax

/// The glue around the pane grid: which pane holds focus, which sides can take a page, how a
/// damaged layout loads, how layout mode ends when the window leaves its tab, and what a pane
/// re-renders for.
struct PaneFocusRuleTests {
    private let active = UUID()
    private let other = UUID()

    @Test
    func `A click focuses its pane, whichever it is`() {
        #expect(PaneFocus.takesFocus(on: .clicked, pageID: other, activePageID: active))
    }

    @Test(arguments: [PaneFocus.Event.appeared, .windowBecameKey])
    func `Appearing or a key window focuses only the tab's active pane`(event: PaneFocus.Event) {
        #expect(PaneFocus.takesFocus(on: event, pageID: active, activePageID: active))
        #expect(PaneFocus.takesFocus(on: event, pageID: other, activePageID: active) == false)
    }

    /// Two pages stored in one cell, and a page without a cell, once loaded in the tab's
    /// unordered page order: which kept the cell changed between launches.
    @Test
    func `A damaged layout loads the same whatever order the pages come in`() {
        let ids = [UUID(), UUID(), UUID()]
        let config = PaneGridFixtures.legacyConfiguration([(ids[0], .topLeft), (ids[1], .topLeft)])
        let orders = [ids, ids.reversed(), [ids[1], ids[2], ids[0]], [ids[2], ids[0], ids[1]]]
        let grids = orders.map { PaneGrid(configuration: config, pageIDs: PaneGrid.loadOrder($0, configuration: config)) }
        #expect(Set(grids.map { $0.spans.map { "\($0.key)\($0.value)" }.sorted().joined() }).count == 1)
        #expect(grids[0].isComplete)
    }

    @Test
    func `Focusing the pane already focused changes nothing`() {
        let a = UUID()
        let b = UUID()
        var editor = PaneLayoutEditor()
        editor.enter(tabID: UUID(), configuration: nil, pageIDs: [a, b], activePageID: a)
        let again = editor.focus(a)
        let moved = editor.focus(b)
        #expect(again == false)
        #expect(moved)
    }
}

@Suite(.serialized)
@MainActor
struct PaneGlueTabTests {
    private struct Fixture {
        let env: TabManagerTestEnvironment
        let space: Space
        let window: WindowState
    }

    private func makeFixture() throws -> Fixture {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        return Fixture(env: env, space: space, window: env.makeActiveWindowState(with: space))
    }

    /// A tab of two side-by-side pages, `A` on the left, shown in the window.
    private func splitTab(_ fixture: Fixture) throws -> (tab: Refrax.Tab, left: UUID, right: UUID) {
        let tab = try fixture.env.createActiveTab(url: #require(URL(string: "https://a.example")), in: fixture.space, for: fixture.window)
        try fixture.env.tabManager.addPageToTab(tab, url: #require(URL(string: "https://b.example")), at: .cell(.topRight))
        let grid = tab.paneGrid
        return try (tab, #require(grid.page(at: .topLeft)), #require(grid.page(at: .topRight)))
    }

    /// Every pane recorded itself as focused when it appeared, so the last one to appear
    /// (in the tab's unordered page order) took focus from the tab's active pane.
    @Test
    func `After a split tab is shown and its panes appear, its active pane holds focus`() throws {
        let fixture = try makeFixture()
        let (tab, _, right) = try splitTab(fixture)
        let rightPage = try #require(tab.pages.first { $0.id == right })
        fixture.env.tabManager.setActivePage(in: tab, page: rightPage)
        let other = try fixture.env.createActiveTab(url: #require(URL(string: "https://c.example")), in: fixture.space, for: fixture.window)
        #expect(fixture.window.activeTabID == other.id)

        for order in [tab.pages, tab.pages.reversed()] {
            fixture.env.tabManager.setActiveTab(tab, in: fixture.window)
            for page in order where PaneFocus.takesFocus(on: .appeared, pageID: page.id, activePageID: tab.activePage.id) {
                fixture.window.recordInteraction(with: page.id)
            }
            #expect(fixture.window.focusedPageID == tab.activePage.id)
            #expect(fixture.window.focusedPageID == right)
        }
    }

    /// "Open on the Left" for the left pane of two columns once fell through to the automatic
    /// place and opened the page below it.
    @Test
    func `A side offers a new page only where it has room`() throws {
        let fixture = try makeFixture()
        let (_, left, right) = try splitTab(fixture)
        fixture.window.recordInteraction(with: left)
        #expect(PaneCommand.isAvailable(.openBeside(.leading), in: fixture.window) == false)
        #expect(PaneCommand.isAvailable(.openBeside(.trailing), in: fixture.window) == false)
        #expect(PaneCommand.isAvailable(.openBeside(.top), in: fixture.window))
        #expect(PaneCommand.placement(beside: .bottom, in: fixture.window) == .split(PaneSplit(target: left, edge: .bottom)))
        #expect(PaneCommand.placement(beside: right, at: .trailing, in: PaneGrid(spans: [left: PaneGridFixtures.leftColumn, right: PaneGridFixtures.rightColumn])) == nil)
    }

    @Test
    func `A space switch while editing commits the edit to the tab it began on`() throws {
        let fixture = try makeFixture()
        let (tab, left, _) = try splitTab(fixture)
        let elsewhere = fixture.env.makeSpace(name: "Elsewhere")

        fixture.window.enterLayoutMode()
        fixture.window.editLayout(animated: false) { $0.move(left, to: .topRight) }
        fixture.env.spaceManager.switchToSpaceSync(elsewhere, for: fixture.window)

        #expect(fixture.window.isInLayoutMode == false)
        #expect(tab.paneGrid.span(of: left) == PaneGridFixtures.rightColumn)
    }

    @Test
    func `Closing the edited tab discards the edit`() throws {
        let fixture = try makeFixture()
        let (tab, left, _) = try splitTab(fixture)
        _ = try fixture.env.tabManager.createTab(url: #require(URL(string: "https://c.example")), in: fixture.space, makeActive: false)

        fixture.window.enterLayoutMode()
        fixture.window.editLayout(animated: false) { $0.move(left, to: .topRight) }
        fixture.env.tabManager.closeTab(tab, registerUndo: false, bypassArchive: true)

        #expect(fixture.window.isInLayoutMode == false)
        #expect(fixture.window.paneEditor.session == nil)
    }

    @Test
    func `Entering again during an exit's settle ends that exit's transition`() throws {
        let fixture = try makeFixture()
        _ = try splitTab(fixture)
        fixture.window.enterLayoutMode()
        fixture.window.exitLayoutMode()
        #expect(fixture.window.isAnimatingLayoutTransition)
        fixture.window.enterLayoutMode()
        #expect(fixture.window.isAnimatingLayoutTransition == false)
        fixture.window.exitLayoutMode(animated: false)
        #expect(fixture.window.isAnimatingLayoutTransition == false)
    }

    /// Every pane re-rendered whenever any page anywhere was made or evicted.
    @Test
    func `A pane is told only about its own page`() throws {
        let fixture = try makeFixture()
        let (tab, left, right) = try splitTab(fixture)
        let pool = fixture.env.pagePool
        let leftPage = try #require(tab.pages.first { $0.id == left })
        let rightPage = try #require(tab.pages.first { $0.id == right })
        pool.removePage(for: leftPage)
        pool.removePage(for: rightPage)

        final class Flag: @unchecked Sendable {
            var isSet = false
        }
        let told = Flag()
        withObservationTracking {
            _ = pool.shownPage(for: leftPage)
        } onChange: {
            told.isSet = true
        }
        pool.page(for: rightPage)
        #expect(told.isSet == false)
        pool.page(for: leftPage)
        #expect(told.isSet)
    }
}
