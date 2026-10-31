import AppKit
import Testing
@testable import Refrax

/// A row's drag leaving the browser window.
struct RowDragHandoffTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1_440, height: 1_080)
    private let tab = UUID()

    @Test(arguments: [CGPoint(x: 700, y: 500), CGPoint(x: 0, y: 0), CGPoint(x: -5, y: 500), CGPoint(x: 1_444, y: 1_084)])
    func `A drag inside the window or along its edge stays a move`(point: CGPoint) {
        var handoff = RowDragHandoff()
        let leaves = handoff.leaves(tab, at: point, bounds: bounds, carriesAddress: true)
        #expect(!leaves)
        #expect(handoff.handedOffTabID == nil)
    }

    @Test(arguments: [CGPoint(x: -7, y: 500), CGPoint(x: 700, y: -20), CGPoint(x: 1_500, y: 500), CGPoint(x: 700, y: 1_200)])
    func `A drag past any edge leaves, once`(point: CGPoint) {
        var handoff = RowDragHandoff()
        let first = handoff.leaves(tab, at: point, bounds: bounds, carriesAddress: true)
        #expect(first)
        #expect(handoff.isHandedOff(tab))
        let again = handoff.leaves(tab, at: point, bounds: bounds, carriesAddress: true)
        #expect(!again)
    }

    @Test
    func `A row with no address to carry never leaves`() {
        var handoff = RowDragHandoff()
        let leaves = handoff.leaves(tab, at: CGPoint(x: -100, y: 0), bounds: bounds, carriesAddress: false)
        #expect(!leaves)
    }

    @Test
    func `Once the system drag ends, the next drag can leave`() {
        var handoff = RowDragHandoff()
        _ = handoff.leaves(tab, at: CGPoint(x: -100, y: 0), bounds: bounds, carriesAddress: true)
        handoff.end()
        #expect(!handoff.isHandedOff(tab))
        let leaves = handoff.leaves(UUID(), at: CGPoint(x: -100, y: 0), bounds: bounds, carriesAddress: true)
        #expect(leaves)
    }
}

/// A dragged tab on the pasteboard.
@MainActor
struct TabDragPromiseTests {
    @Test
    func `A dragged tab offers a webloc, its address, and its identity`() throws {
        let id = UUID()
        let url = try #require(URL(string: "https://example.com/page"))
        let promise = TabDragPromise(tabID: id, url: url, title: "A Page")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("TabDragPromiseTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let types = promise.writableTypes(for: pasteboard)
        #expect(types.contains(.URL))
        #expect(types.contains(.string))
        #expect(types.contains(IslandPasteboard.tabIDs))
        #expect(promise.pasteboardPropertyList(forType: .URL) as? String == url.absoluteString)
        #expect(promise.pasteboardPropertyList(forType: IslandPasteboard.tabIDs) as? String == id.uuidString)
        #expect(promise.fileType == WeblocFile.typeIdentifier)
        #expect(promise.filePromiseProvider(promise, fileNameForType: WeblocFile.typeIdentifier) == "A Page.webloc")
    }

    @Test
    func `What a dragged tab writes is read back as that tab`() throws {
        let id = UUID()
        let url = try #require(URL(string: "https://example.com/page"))
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("TabDragPromiseTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(id.uuidString, forType: IslandPasteboard.tabIDs)
        item.setString(url.absoluteString, forType: .URL)
        pasteboard.writeObjects([item])
        #expect(IslandPasteboard.payload(from: pasteboard) == IslandDropPayload(tabIDs: [id]))
    }
}

/// When a row's drag in an island becomes a system drag.
@Suite("Row drags out of the window", .serialized)
@MainActor
struct RowDragExitTests {
    @Test
    func `Past the window's edge the drag leaves with its row, and the move is called off`() throws {
        let fixture = try IslandFixture()
        let tab = fixture.tab("Page")
        tab.activePage.url = try #require(URL(string: "https://example.com"))
        fixture.canvas.toggleFloatingTabs()
        let inside = CGPoint(x: 700, y: 500)
        guard case .inside = fixture.islands.rowDragExit(tab.id, at: inside) else {
            Issue.record("a drag inside the window left it")
            return
        }
        fixture.islands.updateRowDrag(tab.id, at: inside)
        #expect(fixture.islands.draggedTabID == tab.id)
        guard case let .leaves(tabs) = fixture.islands.rowDragExit(tab.id, at: CGPoint(x: -40, y: 500)) else {
            Issue.record("a drag past the edge stayed a move")
            return
        }
        #expect(tabs.map(\.id) == [tab.id])
        #expect(fixture.islands.draggedTabID == nil)
        #expect(fixture.islands.rowGhost == nil)
        // The gesture's later moves and its end touch nothing while the system drags.
        guard case .handedOff = fixture.islands.rowDragExit(tab.id, at: inside) else {
            Issue.record("the drag came back as a move")
            return
        }
        fixture.islands.finishRowDrag(tab.id, at: inside)
        #expect(fixture.islands.island(holding: tab.id)?.id == fixture.space.id)
        fixture.islands.endDragOut()
        guard case .inside = fixture.islands.rowDragExit(tab.id, at: inside) else {
            Issue.record("the next drag was still handed off")
            return
        }
    }

    @Test
    func `A blank tab's drag stays a move past the edge`() throws {
        let fixture = try IslandFixture()
        let tab = fixture.tab("Blank")
        fixture.canvas.toggleFloatingTabs()
        guard case .inside = fixture.islands.rowDragExit(tab.id, at: CGPoint(x: -40, y: 500)) else {
            Issue.record("a blank tab left the window")
            return
        }
    }

    @Test
    func `A selection leaves together`() throws {
        let fixture = try IslandFixture()
        let a = fixture.tab("A")
        let b = fixture.tab("B")
        for tab in [a, b] {
            tab.activePage.url = try #require(URL(string: "https://example.com/\(tab.displayTitle)"))
        }
        fixture.islands.select(a.id, extending: false, toggling: false)
        fixture.islands.select(b.id, extending: false, toggling: true)
        guard case let .leaves(tabs) = fixture.islands.rowDragExit(a.id, at: CGPoint(x: 2_000, y: 500)) else {
            Issue.record("the selection stayed")
            return
        }
        #expect(Set(tabs.map(\.id)) == [a.id, b.id])
    }
}
