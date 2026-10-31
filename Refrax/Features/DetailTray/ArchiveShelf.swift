import Foundation

/// The archive as the library drawer lists it: archived tabs by space, this window's space
/// first, the most recently archived first in each, narrowed by a search.
nonisolated struct ArchiveShelf: Equatable, Sendable {
    /// One archived tab, read off the model once.
    struct Entry: Equatable, Sendable, Identifiable {
        let id: UUID
        let title: String
        let address: String
        let archivedAt: Date
        let spaceID: UUID
    }

    /// A space's archived tabs.
    struct Section: Equatable, Sendable, Identifiable {
        let id: UUID
        let title: String
        let entries: [Entry]
    }

    let sections: [Section]

    /// - Parameters:
    ///   - entries: Every archived tab that may be listed.
    ///   - currentSpaceID: The window's space, listed first.
    ///   - spaceNames: Each space's name, and the order other spaces follow in.
    ///   - query: Words a tab's title or address must contain; blank lists every tab.
    init(entries: [Entry], currentSpaceID: UUID?, spaceNames: [(id: UUID, name: String)], query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = entries.filter { query.isEmpty || $0.title.localizedStandardContains(query) || $0.address.localizedStandardContains(query) }
        let bySpace = Dictionary(grouping: matching, by: \.spaceID)
        let order = spaceNames.filter { $0.id == currentSpaceID } + spaceNames.filter { $0.id != currentSpaceID }
        self.sections = order.compactMap { space in
            guard let entries = bySpace[space.id], !entries.isEmpty else { return nil }
            return Section(id: space.id, title: space.name, entries: entries.sorted { $0.archivedAt > $1.archivedAt })
        }
    }

    var isEmpty: Bool {
        sections.isEmpty
    }

    var count: Int {
        sections.reduce(0) { $0 + $1.entries.count }
    }
}

/// The archive's verbs in the library drawer: restore a tab to its space's loose tabs,
/// opening it when it is this window's space; delete tabs for good; empty the archive of
/// every space that may be listed.
@MainActor
struct ArchiveActions {
    let tabs: TabManager
    let windowState: WindowState

    /// The shelf for this window, narrowed by `query`.
    func shelf(query: String) -> ArchiveShelf {
        let archived = tabs.browsableArchivedTabs
        let entries = archived.compactMap { tab -> ArchiveShelf.Entry? in
            guard let space = tab.space else { return nil }
            return ArchiveShelf.Entry(
                id: tab.id, title: tab.customName ?? tab.displayTitle, address: tab.displayURL, archivedAt: tab.archivedAt ?? .distantPast,
                spaceID: space.id,
            )
        }
        let spaces = tabs.spaceManager.spaces.map { (id: $0.id, name: $0.name) }
        return ArchiveShelf(entries: entries, currentSpaceID: windowState.activeSpaceID, spaceNames: spaces, query: query)
    }

    /// Restores `tabID`; with `open`, a tab of this window's space becomes the page.
    func restore(_ tabID: UUID, open: Bool) {
        guard let tab = tabs.state.tab(for: tabID), tab.isArchived else { return }
        try? tabs.archiveManager.restoreTab(tab)
        if open, tab.space?.id == windowState.activeSpaceID {
            tabs.setActiveTab(tab, in: windowState)
        }
    }

    /// Deletes the archived tabs among `tabIDs` for good.
    func delete(_ tabIDs: some Sequence<UUID>) {
        for tab in tabIDs.compactMap(tabs.state.tab(for:)) where tab.isArchived {
            tabs.archiveManager.deleteArchivedTab(tab, in: tabs.state.modelContext)
        }
    }

    /// Deletes every archived tab the drawer may list; locked and private spaces keep theirs.
    func emptyArchive() {
        delete(tabs.browsableArchivedTabs.map(\.id))
    }
}
