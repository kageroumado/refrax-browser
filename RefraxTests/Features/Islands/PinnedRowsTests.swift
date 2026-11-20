import AppKit
import Foundation
import Testing
@testable import Refrax

/// A pinned tab is a row with a home: first on its island above a hairline, home again when
/// closed, and left alone by the closes that sweep an island.
@Suite("Pinned rows", .serialized)
@MainActor
struct PinnedRowsTests {
    private func loose(_ fixture: IslandFixture) throws -> Island {
        fixture.islands.refresh()
        return try #require(fixture.islands.island(fixture.space.id))
    }

    /// Three loose tabs in their island's order, top to bottom.
    private func threeRows(_ fixture: IslandFixture) throws -> [Refrax.Tab] {
        for title in ["Mail", "News", "Docs"] {
            _ = fixture.tab(title)
        }
        return try loose(fixture).tabIDs.compactMap(fixture.islands.tab(for:))
    }

    @Test
    func `A pinned tab keeps its address as home and sits first on its island`() throws {
        let fixture = try IslandFixture()
        let rows = try threeRows(fixture)
        let last = rows[2]

        #expect(fixture.env.tabManager.pin(last))

        let island = try loose(fixture)
        #expect(last.isPinned)
        #expect(last.homeURL == last.activePage.url)
        #expect(island.tabIDs == [last.id, rows[0].id, rows[1].id])
        #expect(island.layout.lastPinnedRowIDs == [last.id])
    }

    @Test
    func `The next pin goes under the first, and an unpinned tab goes first under the pinned rows`() throws {
        let fixture = try IslandFixture()
        let rows = try threeRows(fixture)
        fixture.env.tabManager.pin(rows[2])
        fixture.env.tabManager.pin(rows[1])
        #expect(try loose(fixture).tabIDs == [rows[2].id, rows[1].id, rows[0].id])

        #expect(fixture.env.tabManager.unpin(rows[2]))

        let island = try loose(fixture)
        #expect(!rows[2].isPinned)
        #expect(rows[2].homeURL == nil)
        #expect(island.tabIDs == [rows[1].id, rows[2].id, rows[0].id])
        #expect(island.layout.lastPinnedRowIDs == [rows[1].id])
    }

    @Test
    func `Closing a pinned tab returns it home and keeps its row`() throws {
        let fixture = try IslandFixture()
        let rows = try threeRows(fixture)
        let mail = rows[0]
        let home = mail.activePage.url
        fixture.env.tabManager.pin(mail)
        fixture.env.tabManager.setActiveTab(mail, in: fixture.window)
        mail.activePage.url = try #require(URL(string: "https://elsewhere.test/inbox"))
        #expect(mail.hasNavigatedFromHome)

        fixture.env.tabManager.closeTab(mail)

        #expect(mail.space?.id == fixture.space.id)
        #expect(mail.isPinned)
        #expect(mail.activePage.url == home)
        #expect(try loose(fixture).tabIDs.contains(mail.id))
        #expect(fixture.window.activeTabID != mail.id)
    }

    @Test
    func `The only tab of a space stays the window's page when it returns home`() throws {
        let fixture = try IslandFixture()
        let mail = fixture.tab("Mail")
        fixture.env.tabManager.pin(mail)
        fixture.env.tabManager.setActiveTab(mail, in: fixture.window)

        fixture.env.tabManager.closeTab(mail)

        #expect(fixture.window.activeTabID == mail.id)
        #expect(mail.isPinned)
    }

    @Test
    func `The closes that sweep an island leave its pinned rows`() throws {
        let fixture = try IslandFixture()
        let rows = try threeRows(fixture)
        fixture.env.tabManager.pin(rows[0])
        fixture.islands.refresh()

        fixture.edit { fixture.islands.closeOthers(than: rows[1].id) }

        #expect(Set(fixture.space.mainTabs.map(\.id)) == [rows[0].id, rows[1].id])

        fixture.edit { fixture.islands.closeAll(in: fixture.space.id) }

        #expect(fixture.space.mainTabs.map(\.id) == [rows[0].id])
    }

    @Test
    func `A row dropped among the pinned rows is pinned, and a pinned row dropped under them is unpinned`() throws {
        let fixture = try IslandFixture()
        let rows = try threeRows(fixture)
        fixture.env.tabManager.pin(rows[0])
        fixture.env.tabManager.pin(rows[1])
        fixture.islands.refresh()

        fixture.edit { fixture.islands.moveTab(rows[2].id, to: 1, in: fixture.space.id) }

        #expect(rows[2].isPinned)
        #expect(try loose(fixture).tabIDs == [rows[0].id, rows[2].id, rows[1].id])

        fixture.edit { fixture.islands.moveTab(rows[0].id, to: 2, in: fixture.space.id) }
        #expect(rows[0].isPinned, "the slot on the line keeps the row as it was")

        let news = fixture.tab("Later")
        fixture.edit { fixture.islands.moveTab(rows[0].id, to: Int.max, in: fixture.space.id) }

        #expect(!rows[0].isPinned)
        #expect(try loose(fixture).tabIDs.last == rows[0].id)
        #expect(!news.isPinned)
    }

    @Test
    func `Undo of a drop gives the row its pin back`() throws {
        let fixture = try IslandFixture()
        let rows = try threeRows(fixture)
        fixture.env.tabManager.pin(rows[0])
        fixture.env.tabManager.pin(rows[1])
        let home = rows[0].homeURL
        let before = try loose(fixture).tabIDs

        fixture.edit { fixture.islands.moveTab(rows[0].id, to: Int.max, in: fixture.space.id) }
        #expect(!rows[0].isPinned)
        fixture.env.undoRedoManager.undoManager.undo()

        #expect(rows[0].homeURL == home)
        #expect(try loose(fixture).tabIDs == before)
    }

    @Test
    func `Move to Island keeps the pin, on top of an island that had none`() throws {
        let fixture = try IslandFixture()
        let rows = try threeRows(fixture)
        let group = try fixture.env.groupManager.createGroup(in: fixture.space, name: "References")
        let reference = fixture.tab("Reference", group: group)
        fixture.env.tabManager.pin(rows[0])
        fixture.islands.refresh()

        fixture.edit { fixture.islands.moveTab(rows[0].id, toEndOf: group.id) }

        let island = try #require(fixture.islands.island(group.id))
        #expect(rows[0].isPinned)
        #expect(island.tabIDs == [rows[0].id, reference.id])
    }

    @Test
    func `A tab that lands among the pinned rows settles under them`() throws {
        let fixture = try IslandFixture()
        let rows = try threeRows(fixture)
        fixture.env.tabManager.pin(rows[0])
        fixture.env.tabManager.pin(rows[1])
        fixture.islands.refresh()

        fixture.env.tabManager.placeTab(rows[2], after: rows[0], before: rows[1])

        #expect(try loose(fixture).tabIDs == [rows[0].id, rows[1].id, rows[2].id])
    }

    @Test
    func `A row's menu pins, then unpins and shows the way home once the tab has left`() throws {
        let fixture = try IslandFixture()
        let mail = fixture.tab("Mail")

        #expect(try fixture.rowMenu(mail).contains("Pin Tab"))
        fixture.env.tabManager.pin(mail)
        let atHome = try fixture.rowMenu(mail)
        #expect(atHome.contains("Unpin Tab"))
        #expect(!atHome.contains("Pin Tab"))
        #expect(!atHome.contains("Go to Home"))

        mail.activePage.url = try #require(URL(string: "https://elsewhere.test/inbox"))
        let away = try fixture.rowMenu(mail)
        #expect(away.contains("Go to Home"))
        #expect(away.contains("Set Current Page as Home"))

        fixture.env.tabManager.setCurrentPageAsHome(mail)
        #expect(!mail.hasNavigatedFromHome)
    }

    @Test
    func `A favorite's row menu has no pin`() throws {
        let fixture = try IslandFixture()
        let mail = fixture.tab("Mail")
        try #require(fixture.env.tabManager.makeFavorite(mail, in: fixture.window) != nil)
        fixture.islands.refresh()

        let menu = try fixture.rowMenu(mail)
        #expect(!menu.contains("Pin Tab"))
        #expect(!menu.contains("Unpin Tab"))
    }

    @Test
    func `A session export carries a pinned tab's home`() throws {
        let fixture = try IslandFixture()
        let mail = fixture.tab("Mail")
        let news = fixture.tab("News")
        let home = mail.activePage.url
        fixture.env.tabManager.pin(mail)
        mail.activePage.url = try #require(URL(string: "https://elsewhere.test/inbox"))

        #expect(ExportedTab(tab: mail).home == home.absoluteString)
        #expect(ExportedTab(tab: news).home == nil)
    }

    @Test
    func `A pinned group gives its pin to its tabs, once`() throws {
        let fixture = try IslandFixture()
        let group = try fixture.env.groupManager.createGroup(in: fixture.space, name: "Work")
        group.isPinned = true
        let board = fixture.tab("Board", group: group)
        let outside = fixture.tab("News")

        fixture.env.tabManager.migratePinnedGroupsIfNeeded(defaults: fixture.defaults)

        #expect(board.isPinned)
        #expect(board.homeURL == board.activePage.url)
        #expect(!group.isPinned)
        #expect(!outside.isPinned)

        fixture.env.tabManager.unpin(board)
        group.isPinned = true
        fixture.env.tabManager.migratePinnedGroupsIfNeeded(defaults: fixture.defaults)
        #expect(!board.isPinned)
    }
}

@Suite("Pinned rows layout")
struct PinnedRowLayoutTests {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    @Test
    func `The hairline is under the last pinned row that has an unpinned row below it`() {
        #expect(IslandRowLayout(ownTabIDs: [a, b, c], pinned: [a, b]).lastPinnedRowIDs == [b])
        #expect(IslandRowLayout(ownTabIDs: [a, b], pinned: [a, b]).lastPinnedRowIDs.isEmpty)
        #expect(IslandRowLayout(ownTabIDs: [a, b], pinned: []).lastPinnedRowIDs.isEmpty)
    }

    @Test
    func `A slot above a pinned row pins, a slot under an unpinned row unpins, and the line between keeps`() {
        let layout = IslandRowLayout(ownTabIDs: [a, b, c, d], pinned: [a, b])

        #expect(layout.pinChange(at: layout.insertion(at: 0)) == true)
        #expect(layout.pinChange(at: layout.insertion(at: 1)) == true)
        #expect(layout.pinChange(at: layout.insertion(at: 2)) == nil)
        #expect(layout.pinChange(at: layout.insertion(at: 3)) == false)
        #expect(layout.pinChange(at: layout.insertion(at: 4)) == false)
    }

    @Test
    func `A gap parts the pinned rows from the rows under them`() {
        let layout = IslandRowLayout(ownTabIDs: [a, b, c, d], pinned: [a, b])
        let plain = IslandGeometry(iconsOnly: false)
        let geometry = IslandGeometry(iconsOnly: false, gapRows: layout.pinnedGapRows)
        let gap = IslandGeometry.pinnedGap

        #expect(layout.pinnedGapRows == [1])
        #expect(geometry.rowFrame(1) == plain.rowFrame(1))
        #expect(geometry.rowFrame(2).minY == plain.rowFrame(2).minY + gap)
        #expect(geometry.contentHeight(rows: 4) == plain.contentHeight(rows: 4) + gap)
        #expect(geometry.insertionLineY(2) == geometry.rowFrame(1).maxY + gap / 2)
    }

    @Test
    func `A drop reads the same rows above, in, and under the gap`() {
        let geometry = IslandGeometry(iconsOnly: false, gapRows: [1])
        let second = geometry.rowFrame(1)
        let third = geometry.rowFrame(2)

        #expect(geometry.insertion(at: CGPoint(x: 20, y: second.maxY - 2), count: 4) == 2)
        #expect(geometry.insertion(at: CGPoint(x: 20, y: second.maxY + IslandGeometry.pinnedGap / 2), count: 4) == 2)
        #expect(geometry.insertion(at: CGPoint(x: 20, y: third.minY + 2), count: 4) == 2)
        #expect(geometry.insertion(at: CGPoint(x: 20, y: third.maxY - 2), count: 4) == 3)
        #expect(geometry.joinedRow(at: CGPoint(x: 20, y: third.midY), count: 4) == 2)
        #expect(geometry.joinedRow(at: CGPoint(x: 20, y: second.maxY + IslandGeometry.pinnedGap / 2), count: 4) == nil)
    }

    @Test
    func `An island with no pinned row changes no pin`() {
        let layout = IslandRowLayout(ownTabIDs: [a, b], pinned: [])

        #expect(layout.pinChange(at: layout.insertion(at: 0)) == nil)
        #expect(layout.pinChange(at: layout.insertion(at: 2)) == nil)
    }
}
