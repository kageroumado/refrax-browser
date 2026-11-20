import AppKit
import Testing
@testable import Refrax

/// When presses on the page and drags over the window bring the islands up or let them go.
struct IslandDragRevealTests {
    @Test
    func `A press on the page keeps latched islands and gives the page the keyboard`() {
        var reveal = IslandDragReveal()
        #expect(reveal.handle(.pressOnPage, latched: true) == .returnKeyboard)
    }

    @Test
    func `A press with the islands only held lets them go at once`() {
        var reveal = IslandDragReveal()
        #expect(reveal.handle(.pressOnPage, latched: false) == .dismiss)
    }

    @Test
    func `A droppable drag brings the islands up, and puts them away when it leaves`() {
        var reveal = IslandDragReveal()
        #expect(reveal.handle(.dragEntered(.droppable), latched: false) == .reveal)
        // Up now, latched by the drag: a second entry asks nothing more.
        #expect(reveal.handle(.dragEntered(.droppable), latched: true) == .none)
        #expect(reveal.handle(.dragExited, latched: true) == .putAway)
        #expect(reveal.handle(.dragEntered(.droppable), latched: false) == .reveal)
        #expect(reveal.handle(.dragEnded, latched: true) == .putAway)
        #expect(!reveal.isRevealedForDrag)
    }

    @Test
    func `Islands up before the drag stay up after it`() {
        var reveal = IslandDragReveal()
        #expect(reveal.handle(.dragEntered(.droppable), latched: true) == .none)
        #expect(reveal.handle(.dragExited, latched: true) == .none)
        #expect(reveal.handle(.dragEnded, latched: true) == .none)
    }

    @Test
    func `A drag the islands cannot take brings nothing up`() {
        var reveal = IslandDragReveal()
        #expect(reveal.handle(.dragEntered(.other), latched: false) == .none)
        #expect(reveal.handle(.dragEnded, latched: false) == .none)
    }

    @Test(arguments: [
        ([NSPasteboard.PasteboardType.URL], IslandDragReveal.DragKind.droppable),
        ([.fileURL], .droppable),
        ([.string], .droppable),
        ([IslandPasteboard.tabIDs], .droppable),
        ([NSPasteboard.PasteboardType("NSFilenamesPboardType")], .droppable),
        ([.png, .tiff], .other),
        ([], .other),
    ])
    func `Links, text, files, and rows are droppable; a bare image is not`(types: [NSPasteboard.PasteboardType], kind: IslandDragReveal.DragKind) {
        #expect(IslandDragReveal.DragKind(types: types) == kind)
    }
}

/// The islands following presses and drags over a window.
@Suite("Islands during drags", .serialized)
@MainActor
struct IslandWindowDragTests {
    @Test
    func `Dragging a link from the page keeps latched islands up to drop on`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("A")
        fixture.canvas.toggleFloatingTabs()
        fixture.islands.windowInput(.pressOnPage)
        fixture.islands.windowInput(.dragEntered(.droppable))
        #expect(fixture.canvas.floatingVisibility.isLatched)
        #expect(!fixture.islands.visibleIslands.isEmpty)
        fixture.islands.windowInput(.dragEnded)
        #expect(fixture.canvas.floatingVisibility.isLatched)
    }

    @Test
    func `A click on the page keeps latched islands, and the arrows go back to the page`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("A")
        _ = fixture.tab("B")
        fixture.canvas.toggleFloatingTabs()
        #expect(fixture.islands.handleKey(.down))

        fixture.islands.windowInput(.pressOnPage)

        #expect(fixture.canvas.floatingVisibility.isLatched)
        #expect(fixture.islands.keyboardCursorID == nil)
        #expect(!fixture.islands.handleKey(.down))
    }

    @Test
    func `Latching the islands again gives them the arrows`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("A")
        _ = fixture.tab("B")
        fixture.canvas.toggleFloatingTabs()
        fixture.islands.windowInput(.pressOnPage)
        fixture.canvas.toggleFloatingTabs()
        fixture.canvas.toggleFloatingTabs()

        #expect(fixture.islands.handleKey(.down))
    }

    @Test
    func `Latched islands stay through a change of space`() async throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("A")
        fixture.canvas.toggleFloatingTabs()
        let other = fixture.env.makeSpace(name: "Other")
        await fixture.env.spaceManager.switchToSpace(other, for: fixture.window)

        fixture.canvas.floatingSpaceChanged()

        #expect(fixture.canvas.floatingVisibility.isLatched)
    }

    @Test
    func `A link dragged in from another app brings the islands up, and they go when it leaves`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("A")
        #expect(fixture.islands.visibleIslands.isEmpty)
        fixture.islands.windowInput(.dragEntered(.droppable))
        #expect(!fixture.islands.visibleIslands.isEmpty)
        fixture.islands.windowInput(.dragExited)
        #expect(fixture.islands.visibleIslands.isEmpty)
        fixture.islands.windowInput(.dragEntered(.droppable))
        fixture.islands.windowInput(.dragEnded)
        #expect(!fixture.canvas.floatingVisibility.isRevealed)
    }
}
