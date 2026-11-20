import Foundation

// MARK: - Pinned tabs

extension TabManager {
    /// Pins a tab in its space: `home`, its current address by default, becomes its home, and
    /// it takes the last place among the pinned tabs of its island.
    ///
    /// - Returns: Whether the tab became pinned.
    @discardableResult
    func pin(_ tab: Tab, home: URL? = nil) -> Bool {
        guard !tab.isFavorite, !tab.isArchived, !tab.isPinned, let space = tab.space else { return false }
        tab.originURL = home ?? tab.activePage.url
        didChangePin(of: tab, in: space)
        return true
    }

    /// Unpins a tab: it forgets its home and takes the first place under its island's pinned tabs.
    ///
    /// - Returns: Whether the tab was pinned.
    @discardableResult
    func unpin(_ tab: Tab) -> Bool {
        guard tab.isPinned, let space = tab.space else { return false }
        tab.originURL = nil
        didChangePin(of: tab, in: space)
        return true
    }

    /// Pins a tab, or unpins a pinned one.
    ///
    /// - Returns: Whether the tab changed.
    @discardableResult
    func togglePin(_ tab: Tab) -> Bool {
        tab.isPinned ? unpin(tab) : pin(tab)
    }

    private func didChangePin(of tab: Tab, in space: Space) {
        settlePinnedTabs(in: space)
        state.extensionManager?.dispatchPinnedChanged(tab)
        state.incrementListVersion()
        state.incrementContentVersion()
        scheduleSave()
    }

    /// Puts each island's pinned tabs first, keeping the order among the pinned tabs and among
    /// the rest. An island's tabs trade the positions they already hold, so no other tab moves.
    ///
    /// - Returns: Whether any tab moved.
    @discardableResult
    func settlePinnedTabs(in space: Space) -> Bool {
        var moved = false
        for members in Dictionary(grouping: space.mainTabs, by: \.groupID).values {
            guard members.contains(where: \.isPinned) else { continue }
            let settled = members.filter(\.isPinned) + members.filter { !$0.isPinned }
            guard settled.map(\.id) != members.map(\.id) else { continue }
            for (tab, position) in zip(settled, members.map(\.position)) {
                tab.position = position
            }
            members.first?.group?.invalidateTabCache()
            moved = true
        }
        if moved {
            space.invalidateTabCaches()
            state.incrementListVersion()
            scheduleSave()
        }
        return moved
    }

    /// Closes a pinned tab by returning it home: its pages unload, its address resets to its
    /// home, and a window showing it moves to the row a closed tab hands over to. The only tab
    /// of its space loads its home again.
    func returnPinnedTabHome(_ tab: Tab) {
        guard tab.isPinned, let home = tab.homeURL, let space = tab.space else { return }
        let windows = layoutWindows(in: space).filter { $0.activeTabID(for: space.id) == tab.id }
        let successors = windows.map { successor(of: tab, in: $0) }

        pagePool.removePages(for: tab)
        let page = tab.activePage
        if page.url != home {
            page.url = home
            page.title = home.host ?? page.title
        }
        page.scrollPositionY = nil

        for (windowState, next) in zip(windows, successors) {
            if let next {
                setActiveTab(next, in: windowState)
            } else {
                _ = pagePool.page(for: page)
            }
        }
        state.incrementContentVersion()
        scheduleSave()
    }

    /// The tab a window shows once `tab` leaves its page: the row below it, then above, then
    /// beside, as for a closed tab; else its neighbor in the tab list.
    private func successor(of tab: Tab, in windowState: WindowState) -> Tab? {
        if windowState.activeTabID == tab.id, let islands = windowState.islandController {
            for direction in [TableDirection.down, .up, .right, .left] {
                if let neighbor = islands.destination(toward: direction), neighbor.id != tab.id {
                    return neighbor
                }
            }
        }
        guard let tabs = tab.space?.mainTabs, let index = tabs.firstIndex(of: tab) else { return nil }
        return index + 1 < tabs.count ? tabs[index + 1] : index > 0 ? tabs[index - 1] : nil
    }
}

// MARK: - Migration

extension TabManager {
    /// Turns the tabs of pinned groups into pinned tabs, once per store: each takes its current
    /// address as its home, and the group gives up its flag.
    ///
    /// Runs at launch after the spaces load.
    func migratePinnedGroupsIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: PinnedGroupMigration.completedKey) else { return }

        var migrated = 0
        for space in state.spaces {
            spaceManager.ensureLoaded(space)
            let pinnedGroups = space.groups.filter { $0.isPinned && !$0.isArchive }
            guard !pinnedGroups.isEmpty else { continue }
            let groupIDs = Set(pinnedGroups.map(\.id))
            for tab in space.tabs where tab.groupID.map(groupIDs.contains) == true {
                guard tab.status == .regular, !tab.isArchived, tab.originURL == nil else { continue }
                tab.originURL = tab.activePage.url
                migrated += 1
            }
            for group in pinnedGroups {
                group.isPinned = false
            }
            settlePinnedTabs(in: space)
        }
        defaults.set(true, forKey: PinnedGroupMigration.completedKey)
        if migrated > 0 {
            state.incrementListVersion()
            scheduleSave()
        }
        Logger.info("Pinned-group migration pinned \(migrated) tabs", category: Logger.tabs)
    }
}

/// The once-per-store move of a group's pin onto its tabs.
nonisolated enum PinnedGroupMigration {
    /// The defaults key set once the migration has run.
    static let completedKey = "website.refrax.migration.pinnedGroups"
}
