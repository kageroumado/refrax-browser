import Foundation
import Testing
@testable import Refrax

/// How the library drawer lists the archive.
struct ArchiveShelfTests {
    private let here = UUID()
    private let there = UUID()
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func entry(_ title: String, _ address: String = "example.com", ago minutes: Double, in space: UUID) -> ArchiveShelf.Entry {
        ArchiveShelf.Entry(id: UUID(), title: title, address: address, archivedAt: now.addingTimeInterval(-minutes * 60), spaceID: space)
    }

    @Test
    func `This window's space comes first, then the others in their order, newest first in each`() {
        let old = entry("Old", ago: 90, in: here)
        let new = entry("New", ago: 5, in: here)
        let elsewhere = entry("Elsewhere", ago: 1, in: there)
        let shelf = ArchiveShelf(
            entries: [old, elsewhere, new], currentSpaceID: here, spaceNames: [(there, "Work"), (here, "Home")], query: "",
        )
        #expect(shelf.sections.map(\.title) == ["Home", "Work"])
        #expect(shelf.sections[0].entries == [new, old])
        #expect(shelf.count == 3)
    }

    @Test
    func `A search matches title or address, ignoring case and accents`() {
        let cafe = entry("Café Menu", ago: 1, in: here)
        let docs = entry("Docs", "developer.apple.com/swift", ago: 2, in: here)
        let other = entry("News", ago: 3, in: here)
        let spaces = [(id: here, name: "Home")]
        #expect(ArchiveShelf(entries: [cafe, docs, other], currentSpaceID: here, spaceNames: spaces, query: "cafe").sections.first?.entries == [cafe])
        #expect(ArchiveShelf(entries: [cafe, docs, other], currentSpaceID: here, spaceNames: spaces, query: " SWIFT ").sections.first?.entries == [docs])
        #expect(ArchiveShelf(entries: [cafe, docs, other], currentSpaceID: here, spaceNames: spaces, query: "nothing").isEmpty)
    }

    @Test
    func `A space with nothing archived, or nothing matching, has no section`() {
        let shelf = ArchiveShelf(entries: [entry("A", ago: 1, in: there)], currentSpaceID: here, spaceNames: [(here, "Home"), (there, "Work")], query: "")
        #expect(shelf.sections.map(\.title) == ["Work"])
    }
}

/// Restoring, deleting, and emptying the archive from the drawer.
@Suite("Archive drawer", .serialized)
@MainActor
struct ArchiveActionsTests {
    private func archived(_ fixture: IslandFixture, _ titles: [String]) -> [Refrax.Tab] {
        fixture.env.settings.archiveEnabled = true
        let tabs = titles.map { fixture.tab($0) }
        fixture.env.archiveManager.archiveBatch(tabs)
        fixture.islands.refresh()
        return tabs
    }

    @Test
    func `An archived tab is on the shelf and off the islands`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("Open")
        let tabs = archived(fixture, ["Gone"])
        let actions = ArchiveActions(tabs: fixture.env.tabManager, windowState: fixture.window)
        #expect(actions.shelf(query: "").sections.first?.entries.map(\.id) == [tabs[0].id])
        #expect(fixture.islands.island(holding: tabs[0].id) == nil)
    }

    @Test
    func `Restoring and opening brings the tab back to the islands as the page`() throws {
        let fixture = try IslandFixture()
        let tab = try #require(archived(fixture, ["Gone"]).first)
        let actions = ArchiveActions(tabs: fixture.env.tabManager, windowState: fixture.window)
        actions.restore(tab.id, open: true)
        fixture.islands.refresh()
        #expect(!tab.isArchived)
        #expect(fixture.window.activeTabID == tab.id)
        #expect(fixture.islands.island(holding: tab.id)?.id == fixture.space.id)
        #expect(actions.shelf(query: "").isEmpty)
    }

    @Test
    func `Restoring in the background leaves the page alone`() throws {
        let fixture = try IslandFixture()
        let open = fixture.tab("Open")
        fixture.window.setActiveTabID(open.id, for: fixture.space.id)
        let tab = try #require(archived(fixture, ["Gone"]).first)
        ArchiveActions(tabs: fixture.env.tabManager, windowState: fixture.window).restore(tab.id, open: false)
        #expect(!tab.isArchived)
        #expect(fixture.window.activeTabID == open.id)
    }

    @Test
    func `Deleting and emptying remove archived tabs for good, and nothing else`() throws {
        let fixture = try IslandFixture()
        let open = fixture.tab("Open")
        let tabs = archived(fixture, ["One", "Two", "Three"])
        let actions = ArchiveActions(tabs: fixture.env.tabManager, windowState: fixture.window)
        actions.delete([tabs[0].id, open.id])
        #expect(actions.shelf(query: "").count == 2)
        #expect(fixture.env.tabManager.state.tab(for: open.id) != nil)
        actions.emptyArchive()
        #expect(actions.shelf(query: "").isEmpty)
        #expect(fixture.env.tabManager.state.tab(for: open.id) != nil)
    }
}
