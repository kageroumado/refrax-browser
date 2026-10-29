import AppKit
import SwiftData
import Testing
@testable import Refrax

@MainActor
private final class IslandFixture {
    let env: TabManagerTestEnvironment
    let space: Space
    let window: WindowState
    let canvas: TabCanvasManager
    let islands: IslandController

    init() throws {
        self.env = try TabManagerTestEnvironment()
        self.space = env.makeSpace()
        self.window = env.makeActiveWindowState(with: space)
        self.canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool)
        self.islands = IslandController(windowState: window, tabManager: env.tabManager, groupManager: env.groupManager, canvas: canvas, pagePool: env.pagePool)
        window.islandController = islands
        islands.start()
        let bounds = CGRect(x: 0, y: 0, width: 1_440, height: 1_080)
        islands.updateArea(bounds.insetBy(dx: 16, dy: 16), in: bounds)
        env.undoRedoManager.undoManager.groupsByEvent = false
    }

    isolated deinit { islands.stop() }

    func tab(_ title: String, group: TabGroup? = nil) -> Refrax.Tab {
        let tab = env.tabManager.createTab(url: .blank, in: space, groupID: group?.id, makeActive: false, loadImmediately: false)
        tab.activePage.title = title
        islands.refresh()
        return tab
    }

    func edit(_ action: () -> Void) {
        let undo = env.undoRedoManager.undoManager
        undo.beginUndoGrouping()
        action()
        undo.endUndoGrouping()
    }
}

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
