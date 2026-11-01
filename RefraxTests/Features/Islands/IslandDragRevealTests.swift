import AppKit
import Testing
@testable import Refrax

/// When presses on the page and drags over the window bring the islands up or let them go.
struct IslandDragRevealTests {
    @Test
    func `A click on the page lets latched islands go when the button comes up, not before`() {
        var reveal = IslandDragReveal()
        #expect(reveal.handle(.pressOnPage, latched: true) == .none)
        #expect(reveal.handle(.pointerUp, latched: true) == .dismiss)
    }

    @Test
    func `A press that moves is a drag, which keeps latched islands`() {
        var reveal = IslandDragReveal()
        _ = reveal.handle(.pressOnPage, latched: true)
        #expect(reveal.handle(.pointerDragged, latched: true) == .none)
        #expect(reveal.handle(.dragEntered(.droppable), latched: true) == .none)
        #expect(reveal.handle(.dragEnded, latched: true) == .none)
        #expect(reveal.handle(.pointerUp, latched: true) == .none)
    }

    @Test
    func `A press with the islands only held lets them go at once`() {
        var reveal = IslandDragReveal()
        #expect(reveal.handle(.pressOnPage, latched: false) == .dismiss)
        #expect(reveal.handle(.pointerUp, latched: false) == .none)
    }

    @Test
    func `A button coming up after a press elsewhere lets nothing go`() {
        var reveal = IslandDragReveal()
        #expect(reveal.handle(.pointerDragged, latched: true) == .none)
        #expect(reveal.handle(.pointerUp, latched: true) == .none)
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
        fixture.islands.windowInput(.pointerDragged)
        fixture.islands.windowInput(.dragEntered(.droppable))
        #expect(fixture.canvas.floatingVisibility.isLatched)
        #expect(!fixture.islands.visibleIslands.isEmpty)
        fixture.islands.windowInput(.dragEnded)
        #expect(fixture.canvas.floatingVisibility.isLatched)
    }

    @Test
    func `A click on the page lets latched islands go on mouse-up`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("A")
        fixture.canvas.toggleFloatingTabs()
        fixture.islands.windowInput(.pressOnPage)
        #expect(fixture.canvas.floatingVisibility.isLatched)
        fixture.islands.windowInput(.pointerUp)
        #expect(!fixture.canvas.floatingVisibility.isRevealed)
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
