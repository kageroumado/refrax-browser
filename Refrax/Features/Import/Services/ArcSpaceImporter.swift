import Foundation
import SwiftData

/// Brings Arc's organization over as Refrax's own: spaces, islands, and favorites.
///
/// | Arc | Refrax |
/// |-----|--------|
/// | Space | ``Space``: its name, emoji, and theme color; a space of another Arc profile gets its own website data |
/// | Pinned tabs outside folders | A pinned island named "Pinned" |
/// | Pinned folder | A pinned island (a root ``TabGroup``) |
/// | Folder in a folder | A section of that island (a nested ``TabGroup``); deeper folders give their tabs to it |
/// | Unpinned tabs | The space's loose tabs, shown in its "Tabs" island |
/// | Favorites | Favorites, as long as there is room |
///
/// ## Importing Again
///
/// An import merges into what an earlier one made. A space is found by the Arc space it came
/// from (``Space/importedSourceID``), or else by name; an island or section by name in its
/// place; and an address already open in that space, or already a favorite, is skipped.
/// Importing the same sidebar twice changes nothing.
struct ArcSpaceImporter {
    let tabManager: TabManager

    /// The island that holds a space's pinned tabs that sit in no folder.
    static let pinnedIslandName = "Pinned"

    /// Imports a sidebar and reports what changed.
    @discardableResult
    func importSidebar(_ sidebar: ArcSidebar) -> SpaceImportResult {
        var result = SpaceImportResult()
        let spaces = (try? tabManager.state.modelContext.fetch(FetchDescriptor<Space>(sortBy: [SortDescriptor(\.position)]))) ?? []
        var claimed: Set<UUID> = []
        for arcSpace in sidebar.spaces {
            let space = target(for: arcSpace, among: spaces, claimed: claimed, result: &result)
            claimed.insert(space.id)
            var writer = SpaceWriter(space: space, tabManager: tabManager)
            writer.add(pinned: arcSpace.pinned, unpinned: arcSpace.unpinned)
            result.islandsCreated += writer.islandsCreated
            result.sectionsCreated += writer.sectionsCreated
            result.tabsImported += writer.tabsImported
            result.tabsSkipped += writer.tabsSkipped
        }
        importFavorites(sidebar.favorites, result: &result)
        tabManager.scheduleSave()
        return result
    }

    /// The space an Arc space goes into: the one an earlier import made from it, else one of
    /// the same name, else a new one.
    private func target(
        for arcSpace: ArcSidebar.Space,
        among spaces: [Space],
        claimed: Set<UUID>,
        result: inout SpaceImportResult,
    ) -> Space {
        let name = arcSpace.title ?? "Space \(spaces.count + result.spacesCreated + 1)"
        let open = spaces.filter { !claimed.contains($0.id) }
        let earlier = open.first { $0.importedSourceID == arcSpace.id }
            ?? arcSpace.title.flatMap { title in
                open.first { $0.importedSourceID == nil && $0.name.caseInsensitiveCompare(title) == .orderedSame }
            }
        if let earlier {
            earlier.importedSourceID = arcSpace.id
            result.spacesMerged += 1
            return earlier
        }
        let space = tabManager.spaceManager.createSpace(
            name: name,
            iconName: arcSpace.emoji ?? "",
            dataStoreMode: arcSpace.isInDefaultProfile ? .global : .separate,
        )
        space.colorHex = arcSpace.color?.taggedString ?? GroupColor.steel.rawValue
        space.importedSourceID = arcSpace.id
        result.spacesCreated += 1
        return space
    }

    private func importFavorites(_ favorites: [ArcSidebar.Tab], result: inout SpaceImportResult) {
        guard !favorites.isEmpty else { return }
        let bookmarks = tabManager.bookmarksManager!
        let descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.isFavorite })
        var favoriteURLs = Set(((try? tabManager.state.modelContext.fetch(descriptor)) ?? []).map(\.url))
        for favorite in favorites {
            guard favoriteURLs.insert(favorite.url).inserted,
                  tabManager.state.favoriteTabs.count < bookmarks._maxLiveFavoriteTabs
            else {
                result.favoritesSkipped += 1
                continue
            }
            let bookmark = bookmarks.createBookmark(url: favorite.url, title: favorite.title)
            bookmarks.addToFavorites(bookmark, mode: .liveFavorite, loadImmediately: false)
            result.favoritesImported += 1
        }
    }
}

// MARK: - Space Writer

/// Adds one Arc space's rows to a Refrax space, after what it already holds.
private struct SpaceWriter {
    let space: Space
    let tabManager: TabManager
    private let openURLs: Set<URL>
    private var nextPosition: Int

    private(set) var islandsCreated = 0
    private(set) var sectionsCreated = 0
    private(set) var tabsImported = 0
    private(set) var tabsSkipped = 0

    init(space: Space, tabManager: TabManager) {
        self.space = space
        self.tabManager = tabManager
        tabManager.spaceManager.ensureLoaded(space)
        self.openURLs = Set(space.tabs.filter { !$0.isArchived }.map(\.activePage.url))
        self.nextPosition = (space.tabs.map(\.position) + space.groups.map(\.position)).max() ?? 0
    }

    mutating func add(pinned: [ArcSidebar.Item], unpinned: [ArcSidebar.Item]) {
        var pinnedIsland: TabGroup?
        for item in pinned {
            switch item {
            case let .tab(tab):
                if pinnedIsland == nil {
                    pinnedIsland = group(named: ArcSpaceImporter.pinnedIslandName, in: nil, isPinned: true, iconName: "pin.fill")
                }
                add(tab, to: pinnedIsland)
            case let .folder(folder):
                add(folder, isPinned: true)
            }
        }
        for item in unpinned {
            switch item {
            case let .tab(tab):
                add(tab, to: nil)
            case let .folder(folder):
                add(folder, isPinned: false)
            }
        }
        tabManager.normalizePositions(in: space)
        space.invalidateTabCaches()
        for group in space.groups {
            group.invalidateTabCache()
        }
    }

    /// A folder becomes an island; its folders become sections, and folders deeper still give
    /// their tabs to the section that holds them.
    private mutating func add(_ folder: ArcSidebar.Folder, isPinned: Bool) {
        let island = group(named: folder.title, in: nil, isPinned: isPinned)
        for item in folder.items {
            switch item {
            case let .tab(tab):
                add(tab, to: island)
            case let .folder(subfolder):
                let section = group(named: subfolder.title, in: island, isPinned: isPinned)
                for tab in Self.tabs(in: subfolder.items) {
                    add(tab, to: section)
                }
            }
        }
    }

    /// The island or section of that name in its place, made if there is none.
    private mutating func group(named name: String, in parent: TabGroup?, isPinned: Bool, iconName: String? = nil) -> TabGroup? {
        if let existing = space.groups.first(where: {
            !$0.isArchive && $0.parentGroupID == parent?.id && $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            return existing
        }
        guard let group = try? tabManager.groupManager.createGroup(
            in: space, name: name, iconName: iconName, parentGroupID: parent?.id, isPinned: isPinned,
        ) else {
            return parent
        }
        group.position = advance()
        if parent == nil {
            islandsCreated += 1
        } else {
            sectionsCreated += 1
        }
        return group
    }

    /// Adds a tab to a group, or as a loose tab, unless the space already has its address.
    private mutating func add(_ tab: ArcSidebar.Tab, to group: TabGroup?) {
        guard !openURLs.contains(tab.url) else {
            tabsSkipped += 1
            return
        }
        let created = tabManager.createTab(
            url: tab.url, in: space, groupID: group?.id, makeActive: false, loadImmediately: false, insertionStrategy: .append,
        )
        created.activePage.title = tab.title
        created.isUnread = false
        created.position = advance()
        tabsImported += 1
    }

    /// A position after everything placed so far; normalization turns these into the
    /// hierarchical scheme.
    private mutating func advance() -> Int {
        nextPosition += TabPositioner.rootMultiplier
        return nextPosition
    }

    private static func tabs(in items: [ArcSidebar.Item]) -> [ArcSidebar.Tab] {
        items.flatMap { item -> [ArcSidebar.Tab] in
            switch item {
            case let .tab(tab): [tab]
            case let .folder(folder): tabs(in: folder.items)
            }
        }
    }
}
