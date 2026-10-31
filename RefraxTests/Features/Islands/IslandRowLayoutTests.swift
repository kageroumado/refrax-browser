import Foundation
import Testing
@testable import Refrax

/// An island's rows with nested groups as foldable sections, and where a row let go lands.
struct IslandRowLayoutTests {
    private let own = [UUID(), UUID()]
    private let reading = IslandSection(id: UUID(), title: "Reading", tabIDs: [UUID(), UUID(), UUID()], isCollapsed: false)
    private let later = IslandSection(id: UUID(), title: "Later", tabIDs: [UUID(), UUID()], isCollapsed: true)

    private var layout: IslandRowLayout {
        IslandRowLayout(ownTabIDs: own, sections: [reading, later])
    }

    @Test
    func `Own tabs come first, then each section's header and its tabs`() {
        let expected: [IslandRow] = own.map(IslandRow.tab) + [.section(reading.id)] + reading.tabIDs.map(IslandRow.tab) + [.section(later.id)]
        #expect(layout.rows == expected)
        #expect(layout.tabIDs == own + reading.tabIDs)
        #expect(layout.allTabIDs == own + reading.tabIDs + later.tabIDs)
    }

    @Test
    func `A folded section hides its tabs but keeps the current one under its header`() {
        let current = later.tabIDs[1]
        let folded = IslandRowLayout(ownTabIDs: own, sections: [reading, later], currentTabID: current)
        #expect(folded.rows.suffix(2) == [.section(later.id), .tab(current)])
        #expect(folded.row(of: current) == folded.rows.count - 1)
        #expect(folded.row(of: later.tabIDs[0]) == nil)
        #expect(folded.tabIDs.last == current)
    }

    @Test
    func `A section's header is a row the island's height counts`() {
        #expect(layout.count == own.count + 1 + reading.tabIDs.count + 1)
    }

    @Test
    func `The first slot is the island's own, before its first tab`() {
        #expect(layout.insertion(at: 0) == IslandInsertion(section: nil, after: nil, before: own[0]))
    }

    @Test
    func `The slot under a section's header is the section's first`() {
        #expect(layout.insertion(at: own.count + 1) == IslandInsertion(section: reading.id, after: nil, before: reading.tabIDs[0]))
    }

    @Test
    func `The slot under a folded section's header is that section's last`() {
        #expect(layout.insertion(at: layout.count) == IslandInsertion(section: later.id, after: later.tabIDs.last, before: nil))
    }

    @Test
    func `The slot after the island's last own tab stays the island's, ahead of its sections`() {
        #expect(layout.insertion(at: own.count) == IslandInsertion(section: nil, after: own[1], before: nil))
        #expect(layout.endOfOwnTabs() == IslandInsertion(section: nil, after: own[1], before: nil))
    }

    @Test
    func `A slot between a section's tabs keeps the tabs on both sides`() {
        let slot = layout.insertion(at: own.count + 2)
        #expect(slot == IslandInsertion(section: reading.id, after: reading.tabIDs[0], before: reading.tabIDs[1]))
    }

    @Test
    func `The row on its way is counted out of the rows and out of its neighbors`() {
        // Moving the island's first tab one row down puts it after the second.
        #expect(layout.insertion(at: 1, moving: own[0]) == IslandInsertion(section: nil, after: own[1], before: nil))
        // Moving the section's first tab to the top of its section leaves the second next.
        let slot = layout.insertion(at: own.count + 1, moving: reading.tabIDs[0])
        #expect(slot == IslandInsertion(section: reading.id, after: nil, before: reading.tabIDs[1]))
    }

    @Test
    func `A slot past the end is clamped to the last`() {
        #expect(layout.insertion(at: 99) == layout.insertion(at: layout.count))
        #expect(layout.insertion(at: -3) == layout.insertion(at: 0))
    }

    @Test
    func `An island of sections alone starts with a section`() {
        let sectionsOnly = IslandRowLayout(sections: [reading])
        #expect(sectionsOnly.rows.first == .section(reading.id))
        #expect(sectionsOnly.insertion(at: 0) == IslandInsertion(section: nil, after: nil, before: nil))
        #expect(sectionsOnly.section(of: reading.tabIDs[2])?.id == reading.id)
        #expect(sectionsOnly.section(of: UUID()) == nil)
    }
}

/// Nested groups in the islands: one island with sections, folds kept on the group.
@Suite("Island sections", .serialized)
@MainActor
struct IslandSectionTests {
    private func nested(_ fixture: IslandFixture) throws -> (parent: TabGroup, child: TabGroup, own: Refrax.Tab, inside: [Refrax.Tab]) {
        let parent = try fixture.env.groupManager.createGroup(in: fixture.space, name: "Trip")
        let child = try fixture.env.groupManager.createGroup(in: fixture.space, name: "Hotels")
        let own = fixture.tab("Flights", group: parent)
        let inside = [fixture.tab("Hotel A", group: child), fixture.tab("Hotel B", group: child)]
        try fixture.env.groupManager.nestGroup(child, in: parent)
        fixture.islands.refresh()
        return (parent, child, own, inside)
    }

    @Test
    func `A nested group is a section of its parent's island, not an island of its own`() throws {
        let fixture = try IslandFixture()
        let (parent, child, own, inside) = try nested(fixture)
        #expect(fixture.islands.island(child.id) == nil)
        let island = try #require(fixture.islands.island(parent.id))
        #expect(island.rows.first == .tab(own.id))
        #expect(island.rows[1] == .section(child.id))
        #expect(Set(island.tabIDs) == Set([own.id] + inside.map(\.id)))
        #expect(fixture.islands.island(holding: inside[0].id)?.id == parent.id)
    }

    @Test
    func `Folding a section is kept on its group and takes its rows away`() throws {
        let fixture = try IslandFixture()
        let (parent, child, _, inside) = try nested(fixture)
        let unfolded = try #require(fixture.islands.island(parent.id)).rows.count
        fixture.islands.toggleSection(child.id)
        #expect(child.isCollapsed)
        let island = try #require(fixture.islands.island(parent.id))
        #expect(island.rows.count == unfolded - inside.count)
        // A folded tab still belongs to the island: menus and closing reach it.
        #expect(fixture.islands.island(holding: inside[1].id)?.id == parent.id)
        fixture.islands.toggleSection(child.id)
        #expect(!child.isCollapsed)
        #expect(fixture.islands.island(parent.id)?.rows.count == unfolded)
    }

    @Test
    func `Folding the section of the current tab keeps its row, and stepping up leaves it`() throws {
        let fixture = try IslandFixture()
        let (parent, child, own, inside) = try nested(fixture)
        let current = inside[1]
        fixture.window.setActiveTabID(current.id, for: fixture.space.id)
        fixture.islands.toggleSection(child.id)
        let island = try #require(fixture.islands.island(parent.id))
        #expect(island.rows == [.tab(own.id), .section(child.id), .tab(current.id)])
        #expect(fixture.islands.currentTab?.id == current.id)
        // The header is not a stop: up goes to the tab above it, down finds nothing.
        #expect(fixture.islands.destination(toward: .up)?.id == own.id)
        #expect(fixture.islands.destination(toward: .down) == nil)
    }

    @Test
    func `A row let go under a section's header joins that section`() throws {
        let fixture = try IslandFixture()
        let (parent, child, _, _) = try nested(fixture)
        let loose = fixture.tab("Loose")
        fixture.edit { fixture.islands.moveTab(loose.id, to: 2, in: parent.id) }
        #expect(loose.groupID == child.id)
        let island = try #require(fixture.islands.island(parent.id))
        #expect(island.rows[2] == .tab(loose.id))
    }

    @Test
    func `Moving a tab to an island puts it with the island's own tabs, not in its last section`() throws {
        let fixture = try IslandFixture()
        let (parent, _, own, _) = try nested(fixture)
        let loose = fixture.tab("Loose")
        fixture.edit { fixture.islands.moveTab(loose.id, toEndOf: parent.id) }
        #expect(loose.groupID == parent.id)
        let island = try #require(fixture.islands.island(parent.id))
        #expect(island.rows.prefix(2) == [.tab(own.id), .tab(loose.id)])
    }

    @Test
    func `An island put inside another becomes its section, and comes back out as an island`() throws {
        let fixture = try IslandFixture()
        let outer = try fixture.env.groupManager.createGroup(in: fixture.space, name: "Outer")
        let inner = try fixture.env.groupManager.createGroup(in: fixture.space, name: "Inner")
        _ = fixture.tab("A", group: outer)
        let b = fixture.tab("B", group: inner)
        #expect(fixture.islands.canNest(inner.id, in: outer.id))
        #expect(!fixture.islands.canNest(inner.id, in: inner.id))
        #expect(!fixture.islands.canNest(fixture.space.id, in: outer.id))
        fixture.islands.nest(inner.id, in: outer.id)
        #expect(fixture.islands.island(inner.id) == nil)
        #expect(fixture.islands.island(holding: b.id)?.id == outer.id)
        // One level deep: the outer island, holding a section, cannot go inside another.
        let third = try fixture.env.groupManager.createGroup(in: fixture.space, name: "Third")
        _ = fixture.tab("C", group: third)
        #expect(!fixture.islands.canNest(outer.id, in: third.id))
        fixture.islands.unnest(inner.id)
        #expect(fixture.islands.island(inner.id)?.tabIDs == [b.id])
    }
}
