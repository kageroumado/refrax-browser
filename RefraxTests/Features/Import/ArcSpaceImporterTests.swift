import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Refrax

@Suite("Arc space import", .serialized)
@MainActor
struct ArcSpaceImporterTests {
    private typealias Row = ArcSidebarFixture.Row

    private static func workFixture() -> ArcSidebarFixture {
        var fixture = ArcSidebarFixture()
        fixture.spaces = [.init(
            title: "Work",
            emoji: "🛠️",
            color: (0.8, 0.2, 0.1),
            pinned: [
                .tab("Inbox", "https://mail.example.com/"),
                .folder("Projects", [
                    .tab("Board", "https://board.example.com/"),
                    .folder("Specs", [
                        .tab("Spec A", "https://spec-a.example.com/"),
                        .folder("Archive", [.tab("Spec Old", "https://spec-old.example.com/")]),
                    ]),
                ]),
                .tab("Docs", "https://docs.example.com/"),
            ],
            unpinned: [.tab("Article", "https://news.example.com/a")],
        )]
        fixture.favorites = [.tab("Calendar", "https://calendar.example.com/")]
        return fixture
    }

    private func importing(_ fixture: ArcSidebarFixture, into env: TabManagerTestEnvironment) throws -> SpaceImportResult {
        try ArcSpaceImporter(tabManager: env.tabManager).importSidebar(ArcSidebar.parse(fixture.json()))
    }

    private func space(named name: String, in env: TabManagerTestEnvironment) throws -> Space {
        try #require(env.browserState.spaces.first { $0.name == name })
    }

    private func titles(_ tabs: [Refrax.Tab]) -> [String] {
        tabs.map(\.activePage.title)
    }

    @Test
    func `a space comes over with its name, emoji, color, and source`() throws {
        let env = try TabManagerTestEnvironment()
        let fixture = Self.workFixture()
        let result = try importing(fixture, into: env)

        let work = try space(named: "Work", in: env)
        #expect(result.spacesCreated == 1)
        #expect(work.iconName == "🛠️")
        #expect(work.colorHex == Color.Components(red: 0.8, green: 0.2, blue: 0.1, colorSpace: .sRGB).taggedString)
        #expect(work.importedSourceID == fixture.spaces[0].id)
        #expect(work.dataStoreMode == .global)
    }

    @Test
    func `folders become pinned islands with sections, and loose pinned tabs a Pinned island`() throws {
        let env = try TabManagerTestEnvironment()
        let result = try importing(Self.workFixture(), into: env)
        let work = try space(named: "Work", in: env)

        let islands = work.groups.filter(\.isRoot).sorted { $0.position < $1.position }
        #expect(islands.map(\.name) == [ArcSpaceImporter.pinnedIslandName, "Projects"])
        #expect(islands.allSatisfy { $0.isPinned })
        #expect(titles(islands[0].sortedTabs) == ["Inbox", "Docs"])
        #expect(titles(islands[1].sortedTabs) == ["Board"])

        let section = try #require(work.groups.first { $0.parentGroupID == islands[1].id })
        #expect(section.name == "Specs")
        #expect(titles(section.sortedTabs) == ["Spec A", "Spec Old"])
        #expect(work.groups.count == 3)
        #expect(result.islandsCreated == 2)
        #expect(result.sectionsCreated == 1)
    }

    @Test
    func `unpinned tabs are the space's loose tabs, and every tab waits to load`() throws {
        let env = try TabManagerTestEnvironment()
        let result = try importing(Self.workFixture(), into: env)
        let work = try space(named: "Work", in: env)

        #expect(titles(work.mainTabs.filter { $0.group == nil }) == ["Article"])
        #expect(result.tabsImported == 6)
        #expect(work.mainTabs.allSatisfy { !$0.isUnread && env.pagePool.existingPage(for: $0.activePage) == nil })
    }

    @Test
    func `Arc favorites become favorites`() throws {
        let env = try TabManagerTestEnvironment()
        let result = try importing(Self.workFixture(), into: env)

        #expect(result.favoritesImported == 1)
        let favorite = try #require(env.browserState.favoriteTabs.first)
        #expect(favorite.isFavorite)
        #expect(favorite.homeURL == URL(string: "https://calendar.example.com/"))
        #expect(favorite.linkedBookmark?.isFavorite == true)
    }

    @Test
    func `importing the same sidebar again changes nothing`() throws {
        let env = try TabManagerTestEnvironment()
        let fixture = Self.workFixture()
        try importing(fixture, into: env)
        let spaceCount = env.browserState.spaces.count
        let work = try space(named: "Work", in: env)
        let groupCount = work.groups.count
        let tabCount = work.tabs.count

        let again = try importing(fixture, into: env)

        #expect(env.browserState.spaces.count == spaceCount)
        #expect(work.groups.count == groupCount)
        #expect(work.tabs.count == tabCount)
        #expect(env.browserState.favoriteTabs.count == 1)
        #expect(again.spacesCreated == 0)
        #expect(again.spacesMerged == 1)
        #expect(again.tabsImported == 0)
        #expect(again.tabsSkipped == 6)
        #expect(again.favoritesSkipped == 1)
    }

    @Test
    func `a renamed space is still found by its Arc space`() throws {
        let env = try TabManagerTestEnvironment()
        var fixture = Self.workFixture()
        try importing(fixture, into: env)
        try space(named: "Work", in: env).name = "Day Job"

        fixture.spaces[0].unpinned.append(.tab("New", "https://new.example.com/"))
        let again = try importing(fixture, into: env)

        let renamed = try space(named: "Day Job", in: env)
        #expect(again.spacesCreated == 0)
        #expect(again.tabsImported == 1)
        #expect(titles(renamed.mainTabs.filter { $0.group == nil }) == ["Article", "New"])
    }

    @Test
    func `a space of the same name takes the import into its own islands`() throws {
        let env = try TabManagerTestEnvironment()
        let existing = env.makeSpace(name: "Work")
        let projects = try env.groupManager.createGroup(in: existing, name: "projects")
        env.tabManager.createTab(
            url: URL(string: "https://board.example.com/")!, in: existing, groupID: projects.id, makeActive: false, loadImmediately: false,
        )

        let result = try importing(Self.workFixture(), into: env)

        #expect(result.spacesMerged == 1)
        #expect(result.spacesCreated == 0)
        #expect(existing.importedSourceID != nil)
        #expect(existing.groups.filter { $0.isRoot && $0.name.lowercased() == "projects" }.count == 1)
        #expect(projects.tabs.count == 1)
        #expect(result.tabsSkipped == 1)
        #expect(result.tabsImported == 5)
    }

    @Test
    func `an unnamed space is numbered and a space of another profile keeps its own data`() throws {
        let env = try TabManagerTestEnvironment()
        var fixture = ArcSidebarFixture()
        fixture.spaces = [.init(title: nil, isDefaultProfile: false, unpinned: [.tab("Page", "https://page.example.com/")])]
        try importing(fixture, into: env)

        let space = try #require(env.browserState.spaces.first { $0.importedSourceID == fixture.spaces[0].id })
        #expect(space.name == "Space 1")
        #expect(space.dataStoreMode == .separate)
        #expect(space.iconName.isEmpty)
        #expect(space.colorHex == GroupColor.steel.rawValue)
    }

    @Test
    func `the favorites stop at their limit`() throws {
        let env = try TabManagerTestEnvironment()
        let limit = env.bookmarksManager._maxLiveFavoriteTabs
        var fixture = ArcSidebarFixture()
        fixture.favorites = (0 ... limit).map { .tab("Site \($0)", "https://site\($0).example.com/") }

        let result = try importing(fixture, into: env)

        #expect(result.favoritesImported == limit)
        #expect(result.favoritesSkipped == 1)
        #expect(env.browserState.favoriteTabs.count == limit)
    }
}

@Suite("Import options")
@MainActor
struct ImportOptionsSelectionTests {
    @Test
    func `Arc offers spaces and no bookmarks`() {
        var options = ImportOptions()
        options.availableDataTypes = ThirdPartyBrowser.arc.supportedImportTypes

        #expect(options.includes(.spaces))
        #expect(!options.includes(.bookmarks))
        #expect(ImporterFactory.importer(for: .arc) == nil)
    }

    @Test
    func `a choice the source does not offer is not selected`() {
        var options = ImportOptions()
        options.importBookmarks = false
        options.importHistory = false
        options.importPasswords = false
        options.importExtensions = false
        options.availableDataTypes = ThirdPartyBrowser.chrome.supportedImportTypes

        #expect(options.importSpaces)
        #expect(options.selectedDataTypes.isEmpty)
        #expect(!options.hasSelection)
    }
}
