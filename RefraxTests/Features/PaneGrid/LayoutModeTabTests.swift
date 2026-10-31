import AppKit
import Foundation
import SwiftData
import Testing
@testable import Refrax

/// Layout mode with real tabs: the edit is written to the tab it began on whatever the window
/// shows by then, and pages joining or leaving the tab meanwhile go into the edit.
@Suite(.serialized)
@MainActor
struct LayoutModeTabTests {
    private typealias Fixtures = PaneGridFixtures

    private struct Fixture {
        let env: TabManagerTestEnvironment
        let space: Space
        let window: WindowState
    }

    private func makeWindow() throws -> Fixture {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        return Fixture(env: env, space: space, window: env.makeActiveWindowState(with: space))
    }

    /// A tab of two pages: side by side, or one above the other.
    private func splitTab(in fixture: Fixture, sideBySide: Bool, active: Bool) throws -> Refrax.Tab {
        let url = try #require(URL(string: "https://one.example"))
        let tab = active
            ? fixture.env.createActiveTab(url: url, in: fixture.space, for: fixture.window)
            : fixture.env.tabManager.createTab(url: url, in: fixture.space, makeActive: false)
        try fixture.env.tabManager.addPageToTab(tab, url: #require(URL(string: "https://two.example")), at: .cell(sideBySide ? .topRight : .bottomLeft))
        return tab
    }

    /// Switching tabs while editing once wrote the edit against the incoming tab: none of its
    /// pages were in the edit, so its layout was cleared and the edit was lost.
    @Test
    func `Switching tabs in layout mode commits the edit to the tab it began on`() throws {
        let fixture = try makeWindow()
        let edited = try splitTab(in: fixture, sideBySide: true, active: true)
        let other = try splitTab(in: fixture, sideBySide: false, active: false)
        let otherLayout = other.layoutConfiguration
        let first = try #require(edited.paneGrid.page(at: .topLeft))

        fixture.window.enterLayoutMode()
        fixture.window.editLayout(animated: false) { $0.move(first, to: .topRight) }
        fixture.env.tabManager.setActiveTab(other, in: fixture.window)

        #expect(fixture.window.isInLayoutMode == false)
        #expect(edited.paneGrid.span(of: first) == Fixtures.rightColumn)
        #expect(edited.pages.first { $0.id == first }?.position == .topRight)
        #expect(other.layoutConfiguration == otherLayout)
        let top = try #require(other.paneGrid.page(at: .topLeft))
        #expect(other.paneGrid.span(of: top)?.isWide == true)
    }

    @Test
    func `A tab shown by any other way ends the edit the same`() throws {
        let fixture = try makeWindow()
        let edited = try splitTab(in: fixture, sideBySide: true, active: true)
        let other = try splitTab(in: fixture, sideBySide: false, active: false)
        let first = try #require(edited.paneGrid.page(at: .topLeft))

        fixture.window.enterLayoutMode()
        fixture.window.editLayout(animated: false) { $0.move(first, to: .bottomRight) }
        fixture.window.setActiveTabID(other.id, for: fixture.space.id)

        #expect(fixture.window.isInLayoutMode == false)
        #expect(edited.paneGrid.span(of: first) == Fixtures.rightColumn)
    }

    @Test
    func `Done stores the edit on the tab`() throws {
        let fixture = try makeWindow()
        let tab = try splitTab(in: fixture, sideBySide: true, active: true)
        let first = try #require(tab.paneGrid.page(at: .topLeft))

        fixture.window.enterLayoutMode()
        fixture.window.editLayout(animated: false) { $0.shrink(first, from: .bottom) }
        fixture.window.editLayout(animated: false) { editor in
            editor.setSplits(column: 0.3)
            return true
        }
        fixture.window.exitLayoutMode(animated: false)

        #expect(tab.paneGrid.isComplete)
        #expect(tab.layoutConfiguration?.horizontalDivider == 0.3)
    }

    /// A row dropped on an empty cell while the grid is edited joins the tab there, and the
    /// commit keeps it there.
    @Test
    func `Joining a tab in layout mode lands in the cell it was dropped on`() throws {
        let fixture = try makeWindow()
        let tab = try splitTab(in: fixture, sideBySide: true, active: true)
        let first = try #require(tab.paneGrid.page(at: .topLeft))
        let source = try fixture.env.tabManager.createTab(url: #require(URL(string: "https://three.example")), in: fixture.space, makeActive: false)

        fixture.window.enterLayoutMode()
        fixture.window.editLayout(animated: false) { $0.shrink(first, from: .bottom) }
        let joined = try #require(fixture.env.tabManager.moveTabToLayout(source, into: tab, at: .cell(.bottomLeft)))

        #expect(fixture.window.paneEditor.session?.grid.span(of: joined.id) == PaneSpan(.bottomLeft))
        fixture.window.exitLayoutMode(animated: false)
        #expect(tab.pages.count == 3)
        #expect(tab.paneGrid.span(of: joined.id) == PaneSpan(.bottomLeft))
        #expect(tab.paneGrid.span(of: first) == PaneSpan(.topLeft))
    }

    @Test
    func `A pane taken out as a tab leaves the edit`() throws {
        let fixture = try makeWindow()
        let tab = try splitTab(in: fixture, sideBySide: true, active: true)
        let second = try #require(tab.paneGrid.page(at: .topRight))
        let page = try #require(tab.pages.first { $0.id == second })

        fixture.window.enterLayoutMode()
        fixture.env.tabManager.movePageToNewTab(page, from: tab)

        #expect(fixture.window.paneEditor.session?.grid.contains(second) == false)
        fixture.window.exitLayoutMode(animated: false)
        #expect(tab.pages.count == 1)
        #expect(tab.layoutConfiguration == nil)
    }

    @Test
    func `Pages joining a tab fill its grid by where they were put`() throws {
        let fixture = try makeWindow()
        let tab = try fixture.env.createActiveTab(url: #require(URL(string: "https://one.example")), in: fixture.space, for: fixture.window)
        let first = tab.pages[0].id
        let below = try fixture.env.tabManager.addPageToTab(tab, url: #require(URL(string: "https://two.example")), at: .split(PaneSplit(target: first, edge: .bottom)))
        let beside = try fixture.env.tabManager.addPageToTab(tab, url: #require(URL(string: "https://three.example")), at: .split(PaneSplit(target: first, edge: .trailing)))

        let grid = tab.paneGrid
        #expect(grid.span(of: below.id) == Fixtures.bottomRow)
        #expect(grid.span(of: first) == PaneSpan(.topLeft))
        #expect(grid.span(of: beside.id) == PaneSpan(.topRight))
    }
}
