import Testing
@testable import Refrax

/// Editing an island's name, icon, and color together.
@Suite("Island appearance", .serialized)
@MainActor
struct IslandAppearanceTests {
    private let base = IslandAppearance(name: "Research", iconName: "book.fill", colorString: GroupColor.steel.rawValue)

    @Test
    func `A name is trimmed, and a blank one keeps the name there`() {
        var edit = base
        edit.name = "  Reading  "
        #expect(base.applying(edit).name == "Reading")
        edit.name = "   "
        #expect(base.applying(edit).name == "Research")
    }

    @Test
    func `A blank icon clears it, and a blank color keeps the color`() {
        var edit = base
        edit.iconName = " "
        edit.colorString = ""
        let next = base.applying(edit)
        #expect(next.iconName == nil)
        #expect(next.colorString == GroupColor.steel.rawValue)
    }

    @Test(arguments: [("📚", true), ("⭐️", true), ("book.fill", false), ("A", false), ("1", false)])
    func `Emoji draw as text and symbol names as symbols`(icon: String, isEmoji: Bool) {
        #expect(IslandAppearance.isEmoji(icon) == isEmoji)
    }

    @Test
    func `An edit reaches the group, and the island shows it`() throws {
        let fixture = try IslandFixture()
        let group = try fixture.env.groupManager.createGroup(in: fixture.space, name: "Trip")
        _ = fixture.tab("Flights", group: group)
        let edit = IslandAppearance(name: " Japan ", iconName: "airplane", colorString: GroupColor.coral.rawValue)
        fixture.islands.setAppearance(edit, of: group.id)
        #expect(group.name == "Japan")
        #expect(group.iconName == "airplane")
        #expect(group.colorString == GroupColor.coral.rawValue)
        let island = try #require(fixture.islands.island(group.id))
        #expect(island.title == "Japan")
        #expect(island.iconName == "airplane")
        #expect(island.colorString == GroupColor.coral.rawValue)
    }

    @Test
    func `Renaming with only spaces keeps the island's name`() throws {
        let fixture = try IslandFixture()
        let group = try fixture.env.groupManager.createGroup(in: fixture.space, name: "Trip")
        _ = fixture.tab("Flights", group: group)
        fixture.islands.rename(group.id, to: "   ")
        #expect(fixture.islands.island(group.id)?.title == "Trip")
    }

    @Test
    func `The loose tabs' island has nothing to edit`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("Page")
        #expect(fixture.islands.appearance(of: fixture.space.id) == nil)
        fixture.islands.setAppearance(base, of: fixture.space.id)
        #expect(fixture.islands.island(fixture.space.id)?.title == "Tabs")
    }

    @Test
    func `An island being edited stays on screen without the reveal`() throws {
        let fixture = try IslandFixture()
        let group = try fixture.env.groupManager.createGroup(in: fixture.space, name: "Trip")
        _ = fixture.tab("Flights", group: group)
        #expect(fixture.islands.visibleIslands.isEmpty)
        fixture.islands.holdControls(group.id, true)
        #expect(fixture.islands.visibleIslands.map(\.id) == [group.id])
        fixture.islands.holdControls(group.id, false)
        #expect(fixture.islands.visibleIslands.isEmpty)
    }
}
