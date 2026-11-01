import Foundation
import Testing
@testable import Refrax

/// Reading what a drop from another app brings.
struct IslandDropPayloadTests {
    @Test
    func `Links open in the order dropped, each once`() throws {
        let a = try #require(URL(string: "https://a.example/one"))
        let b = try #require(URL(string: "https://b.example/two"))
        let payload = IslandDropPayload(urls: [a, b, a])
        #expect(payload.urls == [a, b])
        #expect(payload.tabIDs.isEmpty)
    }

    @Test
    func `A webloc opens the address inside it, and another file opens itself`() throws {
        let page = try #require(URL(string: "https://example.com/article"))
        let webloc = URL(filePath: "/tmp/Article.webloc")
        let pdf = URL(filePath: "/tmp/paper.pdf")
        let contents = try WeblocFile.data(for: page)
        let payload = IslandDropPayload(urls: [webloc, pdf]) { $0 == webloc ? contents : nil }
        #expect(payload.urls == [page, pdf])
    }

    @Test
    func `A folder or an unreadable webloc opens nothing`() {
        let folder = URL(filePath: "/tmp/Folder/", directoryHint: .isDirectory)
        let broken = URL(filePath: "/tmp/Broken.webloc")
        #expect(IslandDropPayload(urls: [folder, broken]) { _ in Data("nonsense".utf8) }.isEmpty)
    }

    @Test
    func `Text is read for addresses only when no link or file came with it`() throws {
        let text = "Read example.com/guide and https://swift.org/blog, then mail me@example.org"
        let fromText = IslandDropPayload(strings: [text])
        #expect(fromText.urls.map(\.absoluteString) == ["https://example.com/guide", "https://swift.org/blog"])
        let link = try #require(URL(string: "https://kagerou.glass"))
        #expect(IslandDropPayload(urls: [link], strings: [text]).urls == [link])
    }

    @Test
    func `A tab dragged from an island keeps its address, to open where it cannot move`() throws {
        let id = UUID()
        let url = try #require(URL(string: "https://example.com"))
        let payload = IslandDropPayload(tabIDs: [id], urls: [url], strings: ["https://example.com"])
        #expect(payload.tabIDs == [id])
        #expect(payload.urls == [url])
    }

    @Test
    func `Plain words bring nothing`() {
        #expect(IslandDropPayload(strings: ["just some words"]).isEmpty)
    }

    @Test(arguments: [
        "javascript:alert(document.cookie)",
        "data:text/html,<script>alert(1)</script>",
        "refrax://settings",
        "webkit-extension://abc/page.html",
        "x-apple.systempreferences:com.apple.preference.security",
        "mailto:me@example.org",
    ])
    func `A dropped link opens only over http or https`(address: String) throws {
        let url = try #require(URL(string: address))
        #expect(IslandDropPayload(urls: [url]).isEmpty, "\(address)")
    }

    @Test(arguments: ["javascript:alert(1)", "file:///Users/someone/.ssh/id_ed25519", "data:text/html,hi", "refrax://settings"])
    func `A webloc pointing anywhere but the web opens nothing`(address: String) throws {
        let webloc = URL(filePath: "/tmp/Trap.webloc")
        let contents = try WeblocFile.data(for: #require(URL(string: address)))
        #expect(IslandDropPayload(urls: [webloc]) { _ in contents }.isEmpty, "\(address)")
    }

    @Test(arguments: [
        "javascript:alert(1)",
        "data:text/html,hi",
        "file:///etc/passwd",
        "refrax://settings",
    ])
    func `Addresses written in text open only over http or https`(text: String) {
        #expect(IslandDropPayload(strings: [text]).isEmpty, "\(text)")
    }

    @Test
    func `Web links, a dropped file itself, and a webloc to the web all open`() throws {
        let http = try #require(URL(string: "http://example.com/plain"))
        let https = try #require(URL(string: "https://example.com/secure"))
        let file = URL(filePath: "/tmp/notes.html")
        let webloc = URL(filePath: "/tmp/Page.webloc")
        let inside = try #require(URL(string: "https://example.com/inside"))
        let contents = try WeblocFile.data(for: inside)
        let payload = IslandDropPayload(urls: [http, https, file, webloc]) { $0 == webloc ? contents : nil }
        #expect(payload.urls == [http, https, file, inside])
    }
}

/// The internet location file a row dragged to Finder becomes.
struct WeblocFileTests {
    @Test
    func `The address survives a round trip through the file`() throws {
        let url = try #require(URL(string: "https://example.com/a?b=c#d"))
        #expect(try WeblocFile.url(from: WeblocFile.data(for: url)) == url)
    }

    @Test(arguments: [
        ("Swift / Concurrency: Guide", "Swift - Concurrency- Guide.webloc"),
        ("  What? *Really*  ", "What Really.webloc"),
        ("", "example.com.webloc"),
        ("...", "example.com.webloc"),
    ])
    func `A title becomes a safe file name, the host standing in for none`(title: String, name: String) throws {
        #expect(try WeblocFile.filename(title: title, url: #require(URL(string: "https://example.com/page"))) == name)
    }

    @Test
    func `A long title is cut to leave room for the extension`() throws {
        let name = try WeblocFile.filename(title: String(repeating: "a", count: 400), url: #require(URL(string: "https://example.com")))
        #expect(name.count == 200 + ".webloc".count)
    }
}

/// Links and tabs let go on an island land on the row under the pointer.
@Suite("Island drops from outside", .serialized)
@MainActor
struct IslandExternalDropTests {
    private let page = URL(string: "https://example.com/dropped")!

    /// A point on row `row` of `island` as drawn, a little under the row's top.
    private func point(onRow row: Int, of island: Island, in fixture: IslandFixture) -> CGPoint {
        let frame = fixture.islands.frame(of: island)
        return CGPoint(x: frame.midX, y: frame.minY + IslandGeometry.padding + CGFloat(row) * IslandGeometry.rowHeight + 4)
    }

    @Test
    func `A link opens as a tab at the row under the pointer, and is shown`() throws {
        let fixture = try IslandFixture()
        let group = try fixture.env.groupManager.createGroup(in: fixture.space, name: "Reading")
        for title in ["One", "Two", "Three"] {
            _ = fixture.tab(title, group: group)
        }
        fixture.canvas.toggleFloatingTabs()
        let island = try #require(fixture.islands.island(group.id))
        let rowsBefore = island.tabIDs
        #expect(fixture.islands.performDrop(IslandDropPayload(urls: [page]), at: point(onRow: 1, of: island, in: fixture)))
        let after = try #require(fixture.islands.island(group.id))
        #expect(after.tabIDs.count == 4)
        let opened = try #require(fixture.islands.tab(for: after.tabIDs[1]))
        #expect(opened.activePage.url == page)
        #expect(opened.groupID == group.id)
        #expect(after.tabIDs.filter { $0 != opened.id } == rowsBefore)
        #expect(fixture.window.activeTabID == opened.id)
        #expect(fixture.islands.drop == nil)
    }

    @Test
    func `A drop on a scrolled island counts the rows scrolled away`() throws {
        let fixture = try IslandFixture()
        for index in 0 ..< 30 {
            _ = fixture.tab("Tab \(index)")
        }
        fixture.canvas.toggleFloatingTabs()
        let island = try #require(fixture.islands.island(fixture.space.id))
        let frame = fixture.islands.frame(of: island)
        #expect(fixture.islands.geometry(for: island).contentHeight(rows: island.rows.count) > frame.height)
        fixture.islands.scrollOffsets[island.id] = 10 * IslandGeometry.rowHeight
        let target = try #require(fixture.islands.dropTarget(at: point(onRow: 2, of: island, in: fixture)))
        #expect(target.row == 12)
        #expect(fixture.islands.performDrop(IslandDropPayload(urls: [page]), at: point(onRow: 2, of: island, in: fixture)))
        let after = try #require(fixture.islands.island(fixture.space.id))
        #expect(fixture.islands.tab(for: after.tabIDs[12])?.activePage.url == page)
    }

    @Test
    func `Several pages open in order from the row, only the first shown`() throws {
        let fixture = try IslandFixture()
        let existing = fixture.tab("Existing")
        fixture.window.setActiveTabID(existing.id, for: fixture.space.id)
        fixture.canvas.toggleFloatingTabs()
        let island = try #require(fixture.islands.island(fixture.space.id))
        let second = try #require(URL(string: "https://example.com/second"))
        fixture.islands.performDrop(IslandDropPayload(urls: [page, second]), at: point(onRow: 0, of: island, in: fixture))
        let after = try #require(fixture.islands.island(fixture.space.id))
        let urls = after.tabIDs.compactMap { fixture.islands.tab(for: $0)?.activePage.url }
        #expect(Array(urls.prefix(2)) == [page, second])
        #expect(after.tabIDs[2] == existing.id)
        #expect(fixture.window.activeTabID == after.tabIDs[0])
        #expect(fixture.islands.tab(for: after.tabIDs[1])?.isUnread == true)
    }

    @Test
    func `A tab dragged back from another window moves to the row`() throws {
        let fixture = try IslandFixture()
        let group = try fixture.env.groupManager.createGroup(in: fixture.space, name: "Reading")
        _ = fixture.tab("One", group: group)
        _ = fixture.tab("Two", group: group)
        let loose = fixture.tab("Loose")
        fixture.canvas.toggleFloatingTabs()
        let island = try #require(fixture.islands.island(group.id))
        // A move registers its undo, which needs the group an event opens in the app.
        var took = false
        fixture.edit { took = fixture.islands.performDrop(IslandDropPayload(tabIDs: [loose.id]), at: point(onRow: 1, of: island, in: fixture)) }
        #expect(took)
        #expect(loose.groupID == group.id)
        #expect(fixture.islands.island(group.id)?.tabIDs[1] == loose.id)
    }

    @Test
    func `A drop off every island is refused and leaves no insertion line`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("One")
        fixture.canvas.toggleFloatingTabs()
        let island = try #require(fixture.islands.island(fixture.space.id))
        let away = CGPoint(x: fixture.islands.frame(of: island).maxX + 200, y: 900)
        #expect(!fixture.islands.updateExternalDrop(at: away))
        #expect(fixture.islands.drop == nil)
        #expect(fixture.islands.updateExternalDrop(at: point(onRow: 0, of: island, in: fixture)))
        #expect(fixture.islands.drop?.island == island.id)
        #expect(!fixture.islands.performDrop(IslandDropPayload(urls: [page]), at: away))
        #expect(fixture.islands.drop == nil)
        #expect(fixture.islands.island(fixture.space.id)?.tabIDs.count == 1)
    }

    @Test
    func `A row dragged back onto its own island lands at the row under the pointer`() throws {
        let fixture = try IslandFixture()
        for title in ["One", "Two", "Three"] {
            _ = fixture.tab(title)
        }
        fixture.canvas.toggleFloatingTabs()
        let island = try #require(fixture.islands.island(fixture.space.id))
        let rows = island.tabIDs
        let (b, x, y) = (rows[0], rows[1], rows[2])
        // Between X and Y: B goes there, one row up from where the rows stand now.
        // A move registers its undo, which needs the group an event opens in the app.
        var took = false
        fixture.edit { took = fixture.islands.performDrop(IslandDropPayload(tabIDs: [b]), at: point(onRow: 2, of: island, in: fixture)) }
        #expect(took)
        #expect(fixture.islands.island(fixture.space.id)?.tabIDs == [x, b, y])
    }

    @Test
    func `Two rows dropped together, one from above the target, land in order at the slot`() throws {
        let fixture = try IslandFixture()
        for title in ["A", "B", "X", "Y"] {
            _ = fixture.tab(title)
        }
        let group = try fixture.env.groupManager.createGroup(in: fixture.space, name: "Other")
        let z = fixture.tab("Z", group: group)
        fixture.canvas.toggleFloatingTabs()
        let island = try #require(fixture.islands.island(fixture.space.id))
        let rows = island.tabIDs
        let (a, b, x, y) = (rows[0], rows[1], rows[2], rows[3])
        // A move registers its undo, which needs the group an event opens in the app.
        var took = false
        fixture.edit { took = fixture.islands.performDrop(IslandDropPayload(tabIDs: [a, z.id]), at: point(onRow: 3, of: island, in: fixture)) }
        #expect(took)
        #expect(fixture.islands.island(fixture.space.id)?.tabIDs == [b, x, a, z.id, y])
        #expect(z.groupID == nil)
    }

    @Test
    func `A row from another space's window opens its page here`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("Here")
        let elsewhere = fixture.env.makeSpace(name: "Elsewhere")
        let address = try #require(URL(string: "https://example.com/elsewhere"))
        let foreign = fixture.env.tabManager.createTab(url: address, in: elsewhere, makeActive: false, loadImmediately: false)
        fixture.canvas.toggleFloatingTabs()
        let island = try #require(fixture.islands.island(fixture.space.id))
        let payload = IslandDropPayload(tabIDs: [foreign.id], urls: [address])
        #expect(fixture.islands.performDrop(payload, at: point(onRow: 0, of: island, in: fixture)))
        let opened = try #require(fixture.islands.island(fixture.space.id)?.tabIDs.first.flatMap(fixture.islands.tab(for:)))
        #expect(opened.id != foreign.id)
        #expect(opened.activePage.url == address)
        #expect(foreign.space?.id == elsewhere.id)
    }

    @Test
    func `Hidden islands take no drop`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("One")
        let island = try #require(fixture.islands.island(fixture.space.id))
        #expect(fixture.islands.dropTarget(at: point(onRow: 0, of: island, in: fixture)) == nil)
    }
}

/// Chosen rows dragged together within the islands.
@Suite("Dragging a selection", .serialized)
@MainActor
struct IslandSelectionDragTests {
    @Test
    func `A drag keeps the selection, and its rows land together in order`() throws {
        let fixture = try IslandFixture()
        for title in ["A", "B", "X", "Y"] {
            _ = fixture.tab(title)
        }
        fixture.canvas.toggleFloatingTabs()
        let island = try #require(fixture.islands.island(fixture.space.id))
        let rows = island.tabIDs
        let (a, b, x, y) = (rows[0], rows[1], rows[2], rows[3])
        fixture.islands.select(a, extending: false, toggling: false)
        fixture.islands.select(b, extending: false, toggling: true)
        let frame = fixture.islands.frame(of: island)
        fixture.islands.updateRowDrag(a, at: CGPoint(x: frame.midX, y: frame.minY + IslandGeometry.padding + 2.5 * IslandGeometry.rowHeight))
        #expect(fixture.islands.selectedTabIDs == [a, b])
        // Two rows down among the rows without the dragged one: between X and Y.
        fixture.edit { fixture.islands.moveRows(dragging: a, to: 2, in: island.id) }
        #expect(fixture.islands.island(fixture.space.id)?.tabIDs == [x, a, b, y])
        #expect(fixture.islands.selectedTabIDs == [a, b])
        fixture.islands.cancelRowDrag()
    }

    @Test
    func `A row dragged alone moves alone`() throws {
        let fixture = try IslandFixture()
        for title in ["A", "B", "X"] {
            _ = fixture.tab(title)
        }
        let rows = try #require(fixture.islands.island(fixture.space.id)?.tabIDs)
        fixture.islands.select(rows[1], extending: false, toggling: false)
        fixture.edit { fixture.islands.moveRows(dragging: rows[0], to: 2, in: fixture.space.id) }
        #expect(fixture.islands.island(fixture.space.id)?.tabIDs == [rows[1], rows[2], rows[0]])
    }
}
