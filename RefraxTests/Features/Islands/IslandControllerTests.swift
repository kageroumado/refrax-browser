import AppKit
import SwiftData
import Testing
@testable import Refrax

@Suite("Island interactions", .serialized)
@MainActor
struct IslandControllerTests {
    @Test
    func `Moving an island clears its header from the control rail`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("Page")
        fixture.window.controlIsland.railFrame = CGRect(x: 8, y: 8, width: 36, height: 282)
        fixture.islands.moveIsland(fixture.space.id, to: CGPoint(x: 8, y: 300))
        fixture.islands.endIslandMove(keeping: fixture.space.id)
        let island = try #require(fixture.islands.island(fixture.space.id))
        #expect(!fixture.islands.fullFrame(of: island).intersects(fixture.window.controlIsland.railFrame))
    }

    @Test
    func `The library drawer takes precedence over latched and pinned island windows`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("Page")
        fixture.canvas.toggleFloatingTabs()
        fixture.islands.togglePin(fixture.space.id)
        #expect(!fixture.islands.visibleIslands.isEmpty)
        fixture.window.showDetailTray(.favorites)
        #expect(fixture.islands.visibleIslands.isEmpty)
        fixture.window.showDetailTray(.history)
        #expect(fixture.islands.visibleIslands.isEmpty)
        fixture.window.hideDetailTray()
        #expect(!fixture.islands.visibleIslands.isEmpty)
    }

    @Test
    func `Icon rails keep independent snapped placements and clear moving controls`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("Page")
        let id = fixture.space.id
        fixture.window.controlIsland.railFrame = CGRect(x: 8, y: 8, width: 36, height: 282)
        let original = try #require(fixture.islands.island(id)).placement
        fixture.islands.setIconsOnly(true, for: id)
        var island = try #require(fixture.islands.island(id))
        #expect(fixture.islands.fullFrame(of: island).width == 36)
        #expect(!fixture.islands.fullFrame(of: island).intersects(fixture.window.controlIsland.railFrame))
        fixture.islands.moveIsland(id, to: CGPoint(x: 1_405, y: 700))
        fixture.islands.endIslandMove(keeping: id)
        island = try #require(fixture.islands.island(id))
        #expect(island.placement.railPlacement?.x == 1)
        let railFrame = fixture.islands.fullFrame(of: island)
        fixture.window.controlIsland.railFrame = railFrame
        #expect(!fixture.islands.fullFrame(of: island).intersects(railFrame))
        fixture.islands.setIconsOnly(false, for: id)
        #expect(fixture.islands.island(id)?.placement.x == original.x)
        #expect(fixture.islands.island(id)?.placement.y == original.y)
        fixture.islands.setIconsOnly(true, for: id)
        #expect(fixture.islands.island(id)?.placement.railPlacement?.x == 1)
    }

    @Test
    func `Latched and pinned islands keep their names and add buttons reachable`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("Page")
        #expect(fixture.islands.showsHeader(of: fixture.space.id) == false)
        fixture.canvas.toggleFloatingTabs()
        #expect(fixture.islands.showsHeader(of: fixture.space.id))
        fixture.canvas.dismissFloatingTabs()
        fixture.islands.togglePin(fixture.space.id)
        #expect(fixture.islands.showsHeader(of: fixture.space.id))
    }

    @Test
    func `Returning a card releases its page identity and undo restores the card`() throws {
        let fixture = try IslandFixture()
        let main = fixture.tab("Main")
        let reference = fixture.tab("Reference")
        fixture.window.setActiveTabID(main.id, for: fixture.space.id)
        fixture.edit { fixture.islands.detach(reference.id, at: CGPoint(x: 700, y: 400)) }
        fixture.window.recordInteraction(with: reference.activePage.id)
        fixture.edit { fixture.islands.returnToIsland(reference.id) }
        #expect(fixture.window.focusedPageID == nil)
        #expect(fixture.islands.state.detached.contains(reference.id) == false)
        fixture.env.undoRedoManager.undoManager.undo()
        #expect(fixture.islands.state.detached.contains(reference.id))
        #expect(fixture.window.activeTabID == main.id)
        fixture.env.undoRedoManager.undoManager.redo()
        #expect(fixture.islands.state.detached.contains(reference.id) == false)
    }

    @Test
    func `Floating the active row hands the main page to a neighbor and undo restores selection`() throws {
        let fixture = try IslandFixture()
        let main = fixture.tab("Main")
        let reference = fixture.tab("Reference")
        fixture.window.setActiveTabID(main.id, for: fixture.space.id)
        fixture.edit { fixture.islands.detach(main.id, at: CGPoint(x: 700, y: 400)) }
        #expect(fixture.window.activeTabID == reference.id)
        #expect(fixture.islands.state.detached.contains(main.id))
        fixture.env.undoRedoManager.undoManager.undo()
        #expect(fixture.window.activeTabID == main.id)
        #expect(fixture.islands.state.detached.contains(main.id) == false)
        fixture.env.undoRedoManager.undoManager.redo()
        #expect(fixture.window.activeTabID == reference.id)
        #expect(fixture.islands.state.detached.contains(main.id))
    }

    @Test
    func `Automatic arrangement preserves free positions and reserves page space`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("Main")
        fixture.canvas.toggleFloatingTabs()
        let islandID = fixture.space.id
        fixture.islands.moveIsland(islandID, to: CGPoint(x: 800, y: 400))
        fixture.islands.endIslandMove(keeping: islandID)
        let island = try #require(fixture.islands.island(islandID))
        let original = fixture.islands.frame(of: island)
        fixture.islands.arrangeAutomatically()
        #expect(fixture.islands.navigationInset > 0)
        #expect(fixture.islands.frame(of: island).maxX < fixture.islands.navigationInset)
        fixture.islands.useFreePlacement()
        #expect(fixture.islands.navigationInset == 0)
        #expect(fixture.islands.frame(of: island) == original)
    }

    @Test
    func `Moving between islands restores membership and row order through undo and redo`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("First")
        let moved = fixture.tab("Moved")
        _ = fixture.tab("Last")
        let group = try fixture.env.groupManager.createGroup(in: fixture.space, name: "References")
        _ = fixture.tab("Reference", group: group)
        let original = fixture.space.mainTabs.map(\.id)
        let originalRows = fixture.islands.island(fixture.space.id)?.tabIDs
        fixture.edit { fixture.islands.moveTab(moved.id, to: 0, in: group.id) }
        #expect(moved.groupID == group.id)
        fixture.env.undoRedoManager.undoManager.undo()
        #expect(moved.groupID == nil)
        #expect(fixture.space.mainTabs.map(\.id) == original)
        #expect(fixture.islands.island(holding: moved.id)?.tabIDs == originalRows)
        fixture.env.undoRedoManager.undoManager.redo()
        #expect(moved.groupID == group.id)
        #expect(fixture.islands.island(group.id)?.tabIDs.first == moved.id)
    }

    @Test
    func `Combining tabs restores IDs metadata layout and live session through repeated undo`() throws {
        let fixture = try IslandFixture()
        let group = try fixture.env.groupManager.createGroup(in: fixture.space, name: "Reference")
        let target = fixture.tab("Main")
        let source = fixture.tab("Reference", group: group)
        source.customName = "My reference"
        source.activePage.scrollPositionY = 240
        fixture.edit { fixture.islands.detach(source.id, at: CGPoint(x: 900, y: 500)) }
        let originalPlacement = source.floatingPlacement
        let sourceID = source.id
        let originalOrder = fixture.space.mainTabs.map(\.id)
        let runtime = try #require(fixture.env.pagePool.page(for: source.activePage))
        fixture.window.setActiveTabID(target.id, for: fixture.space.id)
        fixture.edit { fixture.islands.join(sourceID, with: target.id) }
        #expect(target.pages.count == 2)
        #expect(fixture.env.undoRedoManager.undoManager.undoActionName == "Combine Tabs")
        try fixture.env.modelContext.save()
        for _ in 0 ..< 2 {
            fixture.env.undoRedoManager.undoManager.undo()
            let restored = try #require(fixture.env.browserState.tab(for: sourceID))
            #expect(restored.customName == "My reference")
            #expect(restored.groupID == group.id)
            #expect(restored.activePage.scrollPositionY == 240)
            #expect(restored.floatingPlacement == originalPlacement)
            #expect(fixture.islands.state.detached.contains(restored.id))
            #expect(fixture.space.mainTabs.map(\.id) == originalOrder)
            #expect(fixture.env.pagePool.existingPage(for: restored.activePage) === runtime)
            #expect(target.pages.count == 1)
            #expect(target.layoutConfiguration == nil)
            try fixture.env.modelContext.save()
            fixture.env.undoRedoManager.undoManager.redo()
            #expect(target.pages.count == 2)
            #expect(fixture.env.browserState.tab(for: sourceID) == nil)
            try fixture.env.modelContext.save()
        }
    }

    @Test
    func `Arrow navigation reaches island rows in the browser window and leaves renaming alone`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("First")
        _ = fixture.tab("Second")
        let rows = try #require(fixture.islands.island(fixture.space.id)?.tabIDs)
        let firstID = try #require(rows.first)
        let secondID = try #require(rows.dropFirst().first)
        fixture.window.setActiveTabID(firstID, for: fixture.space.id)
        fixture.canvas.toggleFloatingTabs()
        let parent = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 900, height: 700), styleMask: .titled, backing: .buffered, defer: false)
        let gestures = CanvasPageGestures(window: parent, canvas: fixture.canvas, floatingEligible: { true }, floatingContains: { _ in false }, floatingHasKeyboardFocus: { false })
        gestures.islands = fixture.islands
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: parent.windowNumber, context: nil, characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}", isARepeat: false, keyCode: 125))
        #expect(gestures.handle(event) == nil)
        #expect(fixture.window.activeTabID == secondID)
        let editor = NSTextView()
        parent.contentView = editor
        parent.makeFirstResponder(editor)
        #expect(gestures.handle(event) != nil)
    }
}

/// A row dragged off its island: on empty space it makes an island where its ghost stood; on
/// another island it joins; with ⇧ it leaves as a card.
@Suite("Making islands by dropping", .serialized)
@MainActor
struct IslandDropTests {
    private func firstRowMiddle(of frame: CGRect) -> CGPoint {
        CGPoint(x: frame.midX, y: frame.minY + IslandGeometry.headerReserve + IslandGeometry.padding + IslandGeometry.rowHeight / 2)
    }

    @Test
    func `A row let go on empty space makes an island where its ghost stood`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("A")
        let b = fixture.tab("B")
        fixture.canvas.toggleFloatingTabs()
        let point = CGPoint(x: 900, y: 500)
        fixture.islands.updateRowDrag(b.id, at: point)
        let ghost = try #require(fixture.islands.islandGhost)
        #expect(fixture.islands.drop == nil)
        #expect(fixture.islands.sideDrop == nil)
        #expect(!fixture.islands.dropsAsCard)
        #expect(ghost.rows == 1)
        #expect(ghost.title == fixture.islands.islandName(for: b))
        let middle = firstRowMiddle(of: ghost.frame)
        #expect(abs(middle.x - point.x) < 0.5 && abs(middle.y - point.y) < 0.5)

        fixture.edit { fixture.islands.finishRowDrag(b.id, at: point) }
        #expect(fixture.islands.islands.count == 2)
        let island = try #require(fixture.islands.island(holding: b.id))
        #expect(!island.isDefault)
        #expect(island.tabIDs == [b.id])
        let landed = fixture.islands.fullFrame(of: island)
        #expect(abs(landed.minX - ghost.frame.minX) < 0.5 && abs(landed.minY - ghost.frame.minY) < 0.5)
        #expect(!fixture.islands.state.detached.contains(b.id))
        #expect(fixture.islands.islandGhost == nil)
        #expect(fixture.islands.draggedTabID == nil)
    }

    @Test
    func `A ghost at the window's corner is held inside the area and the island lands there`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("A")
        let b = fixture.tab("B")
        fixture.canvas.toggleFloatingTabs()
        let area = fixture.bounds.insetBy(dx: 16, dy: 16)
        let point = CGPoint(x: fixture.bounds.maxX - 2, y: fixture.bounds.maxY - 2)
        fixture.islands.updateRowDrag(b.id, at: point)
        let ghost = try #require(fixture.islands.islandGhost)
        #expect(area.contains(ghost.frame))
        #expect(abs(ghost.frame.maxX - area.maxX) < 0.5 && abs(ghost.frame.maxY - area.maxY) < 0.5)
        fixture.edit { fixture.islands.finishRowDrag(b.id, at: point) }
        let island = try #require(fixture.islands.island(holding: b.id))
        let landed = fixture.islands.fullFrame(of: island)
        #expect(abs(landed.minX - ghost.frame.minX) < 0.5 && abs(landed.minY - ghost.frame.minY) < 0.5)
    }

    @Test
    func `With shift the row leaves as a card instead`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("A")
        let b = fixture.tab("B")
        fixture.canvas.toggleFloatingTabs()
        let point = CGPoint(x: 900, y: 500)
        fixture.islands.updateRowDrag(b.id, at: point, asCard: true)
        #expect(fixture.islands.islandGhost == nil)
        #expect(fixture.islands.dropsAsCard)
        fixture.edit { fixture.islands.finishRowDrag(b.id, at: point, asCard: true) }
        #expect(fixture.islands.state.detached.contains(b.id))
        #expect(fixture.islands.islands.count == 1)
        #expect(!fixture.islands.dropsAsCard)
    }

    @Test
    func `A row let go over another island joins it with no ghost`() throws {
        let fixture = try IslandFixture()
        let a = fixture.tab("A")
        let b = fixture.tab("B")
        fixture.edit { fixture.islands.makeIsland(from: b.id) }
        fixture.canvas.toggleFloatingTabs()
        let target = try #require(fixture.islands.island(holding: a.id))
        let point = firstRowMiddle(of: fixture.islands.fullFrame(of: target))
        fixture.islands.updateRowDrag(b.id, at: point)
        #expect(fixture.islands.drop?.island == target.id)
        #expect(fixture.islands.islandGhost == nil)
        fixture.edit { fixture.islands.finishRowDrag(b.id, at: point) }
        #expect(fixture.islands.island(holding: b.id)?.id == target.id)
    }

    @Test
    func `A selection let go on empty space makes one island of every chosen row`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("A")
        let b = fixture.tab("B")
        let c = fixture.tab("C")
        fixture.canvas.toggleFloatingTabs()
        fixture.islands.select(b.id, extending: false, toggling: false)
        fixture.islands.select(c.id, extending: true, toggling: false)
        let point = CGPoint(x: 900, y: 500)
        fixture.islands.updateRowDrag(c.id, at: point)
        #expect(fixture.islands.islandGhost?.rows == 2)
        #expect(fixture.islands.islandGhost?.title == fixture.islands.islandName(for: b))
        fixture.edit { fixture.islands.finishRowDrag(c.id, at: point) }
        let island = try #require(fixture.islands.island(holding: c.id))
        // The rows keep the tab list's order, whatever it is for two tabs made at once.
        #expect(Set(island.tabIDs) == [b.id, c.id])
        #expect(fixture.islands.islands.count == 2)
    }
}

/// The one-time hint on starting an island, and where New Island sits in the menus.
@Suite("Island doors", .serialized)
@MainActor
struct IslandDoorTests {
    @Test
    func `The hint stands by the loose tabs' island while a space has no other and tabs to spare`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("A")
        fixture.canvas.toggleFloatingTabs()
        #expect(fixture.islands.startHintIsland == nil)
        let b = fixture.tab("B")
        let island = try #require(fixture.islands.startHintIsland)
        #expect(island.isDefault)
        fixture.islands.updateRowDrag(b.id, at: CGPoint(x: 900, y: 500))
        #expect(fixture.islands.startHintIsland == nil)
        fixture.islands.cancelRowDrag()
        #expect(fixture.islands.startHintIsland != nil)
        fixture.canvas.toggleFloatingTabs()
        #expect(fixture.islands.startHintIsland == nil)
    }

    @Test
    func `Dismissing the hint keeps it away in every later controller on the same defaults`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("A")
        _ = fixture.tab("B")
        fixture.canvas.toggleFloatingTabs()
        #expect(fixture.islands.startHintIsland != nil)
        fixture.islands.dismissStartHint()
        #expect(fixture.islands.startHintIsland == nil)
        #expect(fixture.defaults.bool(forKey: IslandController.startHintKey))
        let later = try IslandFixture(defaults: fixture.defaults)
        _ = later.tab("A")
        _ = later.tab("B")
        later.canvas.toggleFloatingTabs()
        #expect(later.islands.startHintDismissed)
        #expect(later.islands.startHintIsland == nil)
    }

    @Test
    func `The first island puts the hint away for good`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("A")
        let b = fixture.tab("B")
        _ = fixture.tab("C")
        fixture.canvas.toggleFloatingTabs()
        #expect(fixture.islands.startHintIsland != nil)
        fixture.edit { fixture.islands.makeIsland(from: b.id) }
        #expect(fixture.islands.startHintDismissed)
        let made = try #require(fixture.islands.island(holding: b.id))
        fixture.edit { fixture.islands.dissolve(made.id) }
        #expect(fixture.islands.islands.count == 1)
        #expect(fixture.islands.startHintIsland == nil)
    }

    @Test
    func `New Island with This Tab sits once under the page's essentials in a row's menu`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("A")
        let b = fixture.tab("B")
        let rows = try fixture.rowMenu(b)
        let island = try #require(rows.firstIndex(of: "New Island with This Tab"))
        let copy = try #require(rows.firstIndex(of: "Copy Address"))
        let share = try #require(rows.firstIndex(of: "Share…"))
        #expect(copy < island && share < island)
        #expect(island <= 4)
        #expect(rows.filter { $0 == "New Island with This Tab" }.count == 1)
        #expect(rows.contains("Open as Card") || rows.contains { $0.hasPrefix("Move ▸") })
    }

    @Test
    func `A selection's menu leads with New Island from N Tabs`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("A")
        let b = fixture.tab("B")
        let c = fixture.tab("C")
        fixture.islands.select(b.id, extending: false, toggling: false)
        fixture.islands.select(c.id, extending: true, toggling: false)
        let rows = try fixture.rowMenu(c)
        #expect(rows.first == "New Island from 2 Tabs")
    }

    @Test
    func `The page card's menu shows New Island once, near the top`() throws {
        let fixture = try IslandFixture()
        let active = try fixture.env.createActiveTab(url: #require(URL(string: "https://example.com/active")), in: fixture.space, for: fixture.window)
        fixture.islands.refresh()
        let tree = PageActionsMenu.tree(
            for: active, surface: .pageCard, area: fixture.bounds, windowState: fixture.window, tabs: fixture.env.tabManager,
            bookmarks: fixture.env.bookmarksManager, canvas: fixture.canvas, sharing: fixture.sharing,
        )
        let rows = tree.outline.filter { !$0.hasPrefix(" ") && $0 != "——" }
        let island = try #require(rows.firstIndex(of: "New Island with This Tab"))
        #expect(island <= 4)
        #expect(tree.outline.filter { $0.contains("New Island") }.count == 1)
    }
}
