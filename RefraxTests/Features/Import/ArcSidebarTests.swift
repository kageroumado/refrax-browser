import Foundation
import SwiftUI
import Testing
@testable import Refrax

@Suite("Arc sidebar")
@MainActor
struct ArcSidebarTests {
    private typealias Row = ArcSidebarFixture.Row

    @Test
    func `spaces keep their order, name, emoji, color, and profile`() throws {
        var fixture = ArcSidebarFixture()
        fixture.spaces = [
            .init(title: "Work", emoji: "🌿", color: (0.2, 0.4, 0.6)),
            .init(title: nil, isDefaultProfile: false),
        ]
        let sidebar = try ArcSidebar.parse(fixture.json())

        #expect(sidebar.spaces.map(\.title) == ["Work", nil])
        #expect(sidebar.spaces.map(\.id) == fixture.spaces.map(\.id))
        #expect(sidebar.spaces[0].emoji == "🌿")
        #expect(sidebar.spaces[0].color == Color.Components(red: 0.2, green: 0.4, blue: 0.6, colorSpace: .sRGB))
        #expect(sidebar.spaces[0].isInDefaultProfile)
        #expect(sidebar.spaces[1].emoji == nil)
        #expect(sidebar.spaces[1].color == nil)
        #expect(!sidebar.spaces[1].isInDefaultProfile)
    }

    @Test
    func `pinned and unpinned rows keep their tree and order`() throws {
        var fixture = ArcSidebarFixture()
        fixture.spaces = [.init(
            title: "Home",
            pinned: [
                .tab("Mail", "https://mail.example.com/"),
                .folder("Reading", [
                    .tab("One", "https://one.example.com/"),
                    .folder("Later", [.tab("Two", "https://two.example.com/")]),
                ]),
            ],
            unpinned: [.tab("Today", "https://today.example.com/")],
        )]
        let space = try #require(ArcSidebar.parse(fixture.json()).spaces.first)

        #expect(space.pinned == [
            .tab(.init(url: URL(string: "https://mail.example.com/")!, title: "Mail")),
            .folder(.init(title: "Reading", items: [
                .tab(.init(url: URL(string: "https://one.example.com/")!, title: "One")),
                .folder(.init(title: "Later", items: [.tab(.init(url: URL(string: "https://two.example.com/")!, title: "Two"))])),
            ])),
        ])
        #expect(space.unpinned == [.tab(.init(url: URL(string: "https://today.example.com/")!, title: "Today"))])
    }

    @Test
    func `split views give their tabs in their place and notes are left out`() throws {
        var fixture = ArcSidebarFixture()
        fixture.spaces = [.init(title: "Home", pinned: [
            .note,
            .split([.tab("Left", "https://left.example.com/"), .tab("Right", "https://right.example.com/")]),
            .tab("Internal", "arc://settings"),
        ])]
        let space = try #require(ArcSidebar.parse(fixture.json()).spaces.first)

        #expect(space.pinned.map(Self.title) == ["Left", "Right"])
    }

    @Test
    func `escaped slashes are read as slashes, and a missing title falls back to the host`() throws {
        let data = Data(#"""
        {"sidebar": {"containers": [{"global": {}}, {
            "spaces": ["s", {"id": "s", "title": "Home", "containerIDs": ["pinned", "p", "unpinned", "u"]}],
            "items": [
                "p", {"id": "p", "parentID": null, "childrenIds": ["t"], "data": {"itemContainer": {}}},
                "t", {"id": "t", "parentID": "p", "childrenIds": [], "title": null,
                      "data": {"tab": {"savedURL": "https:\/\/escaped.example.com\/page"}}},
                "x", {"id": "x", "parentID": "p", "childrenIds": [], "title": "Unlisted",
                      "data": {"tab": {"savedURL": "https://unlisted.example.com/"}}}
            ]
        }]}}
        """#.utf8)
        let space = try #require(ArcSidebar.parse(data).spaces.first)

        #expect(space.pinned == [
            .tab(.init(url: URL(string: "https://escaped.example.com/page")!, title: "escaped.example.com")),
            .tab(.init(url: URL(string: "https://unlisted.example.com/")!, title: "Unlisted")),
        ])
        #expect(space.unpinned.isEmpty)
    }

    @Test
    func `favorites come from the top container, each address once`() throws {
        var fixture = ArcSidebarFixture()
        fixture.spaces = [.init(title: "Home")]
        fixture.favorites = [
            .tab("Calendar", "https://calendar.example.com/"),
            .tab("Notes", "https://notes.example.com/"),
            .tab("Calendar again", "https://calendar.example.com/"),
        ]
        let sidebar = try ArcSidebar.parse(fixture.json())

        #expect(sidebar.favorites.map(\.title) == ["Calendar", "Notes"])
    }

    @Test
    func `the sidebar file is found above the Chromium profile`() throws {
        var fixture = ArcSidebarFixture()
        fixture.spaces = [.init(title: "Home")]
        let (profile, cleanup) = try fixture.writeProfile()
        defer { cleanup() }

        let file = try #require(ArcSidebar.sidebarFile(for: profile))
        #expect(file.lastPathComponent == ArcSidebar.fileName)
        #expect(file.deletingLastPathComponent().standardizedFileURL
            == profile.path.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL)
    }

    @Test
    func `a profile without a sidebar reports the missing file`() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("arc-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let profile = BrowserProfile(id: "default", name: "Default", path: folder, browser: .arc)

        #expect(ArcSidebar.sidebarFile(for: profile) == nil)
        await #expect(throws: ImportError.self) { try await ArcSidebar.load(from: profile) }
    }

    @Test(arguments: ["not json", #"{"sidebar": {}}"#, #"{"sidebar": {"containers": [null, {"items": []}]}}"#])
    func `data in another shape is a parse error`(text: String) {
        #expect(throws: ImportError.self) { try ArcSidebar.parse(Data(text.utf8)) }
    }

    private static func title(_ item: ArcSidebar.Item) -> String {
        switch item {
        case let .tab(tab): tab.title
        case let .folder(folder): folder.title
        }
    }
}
