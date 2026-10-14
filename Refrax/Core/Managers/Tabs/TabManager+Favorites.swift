import Foundation

// MARK: - Favorites

extension TabManager {
    /// Makes a tab a favorite in place: it leaves its space and group, belongs to every space,
    /// and gets a favorited bookmark at `home`, its current address by default.
    ///
    /// The tab keeps its identity, pages, and floating placement. A page loaded in a space with
    /// its own website data unloads, because favorites use the global data store.
    ///
    /// - Parameters:
    ///   - tab: A tab in a space.
    ///   - home: The favorite's home address. Defaults to the tab's current address.
    ///   - targetWindow: The window that keeps the tab active if it was. Defaults to the active window.
    /// - Returns: The favorite's bookmark, or `nil` if the tab is already a favorite or has no space.
    @discardableResult
    func makeFavorite(_ tab: Tab, home: URL? = nil, in targetWindow: WindowState? = nil) -> Bookmark? {
        guard !tab.isFavorite, let space = tab.space else { return nil }
        let windowState = targetWindow ?? activeWindowState
        let wasActive = windowState?.activeTabID(for: space.id) == tab.id

        if !space.dataStoreMode.isGlobal {
            pagePool.removePages(for: tab)
        }
        moveToFavorites(tab, from: space)
        let bookmark = bookmarksManager.createFavoriteBookmark(for: tab, home: home ?? tab.activePage.url)

        if wasActive, let windowState {
            setActiveTab(tab, in: windowState)
        }
        state.extensionManager?.dispatchPinnedChanged(tab)
        return bookmark
    }

    /// Adds a tab to Favorites, or removes a favorite into the window's active space.
    ///
    /// - Returns: Whether the tab changed.
    @discardableResult
    func toggleFavorite(_ tab: Tab, in windowState: WindowState? = nil) -> Bool {
        if tab.isFavorite {
            guard let bookmark = tab.linkedBookmark else { return false }
            bookmarksManager.removeFromFavorites(bookmark, in: windowState)
            state.extensionManager?.dispatchPinnedChanged(tab)
            return !tab.isFavorite
        }
        guard state.favoriteTabs.count < bookmarksManager._maxLiveFavoriteTabs else { return false }
        return makeFavorite(tab, in: windowState) != nil
    }

    /// Closes a favorite by returning it home: its pages unload, its address resets to its
    /// home, and it stays in every space.
    func returnFavoriteHome(_ tab: Tab) {
        guard tab.isFavorite else { return }
        pagePool.removePages(for: tab)
        if let home = tab.homeURL {
            let page = tab.activePage
            page.url = home
            page.title = tab.linkedBookmark?.title ?? home.host ?? page.title
            page.scrollPositionY = nil
        }
        for controller in windowManager.windowControllers where controller.windowState.activeTabID == tab.id {
            controller.windowState.clearActiveLiveFavorite()
        }
        state.incrementContentVersion()
        scheduleSave()
    }

    /// Loads a favorite's home address in its page.
    func goHome(_ tab: Tab) {
        guard let home = tab.homeURL else { return }
        if let page = pagePool.existingPage(for: tab.activePage) {
            page.load(home)
        } else {
            tab.activePage.url = home
        }
    }

    /// Makes the favorite's current address its home.
    func setCurrentPageAsHome(_ tab: Tab) {
        guard tab.isFavorite, let bookmark = tab.linkedBookmark else { return }
        bookmark.url = tab.activePage.url
        bookmarksManager.refreshFavoritesCache()
        scheduleSave()
    }

    /// Moves a tab out of its space and group into the favorites, keeping it indexed.
    private func moveToFavorites(_ tab: Tab, from space: Space) {
        let mainTabIndex = space.mainTabs.firstIndex(of: tab) ?? 0
        mutationPipeline.withMutation { effects in
            if let groupID = tab.groupID, let group = space.groups.first(where: { $0.id == groupID }) {
                group._removeTab(tab)
            }
            tab.groupID = nil
            space.tabs.removeAll { $0.id == tab.id }
            tab.space = nil
            tab.status = .favorite
            tab.originURL = nil
            tab.position = state.favoriteTabs.count
            state.addFavoriteTab(tab)

            effects.didChangeList = true
            effects.spaceIDsToNormalize.insert(space.id)
            effects.spaceIDsToSyncActiveTab.insert(space.id)
            effects.closedTabContexts[space.id] = TabMutationPipeline.ClosedTabContext(
                tabID: tab.id,
                mainTabIndex: mainTabIndex,
            )
        }
    }
}

// MARK: - Migration

extension TabManager {
    /// Turns sidebar pins and cards shown in every space into favorites, once per store.
    ///
    /// Runs at launch after the spaces load. See ``FavoriteMigration`` for the mapping.
    func migrateFavoritesIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: FavoriteMigration.completedKey) else { return }

        var migrated = 0
        for space in state.spaces {
            spaceManager.ensureLoaded(space)
            let isShared = space.dataStoreMode != .private && !space.isLockEnabled
            for tab in space.tabs {
                let candidate = FavoriteMigration.Candidate(
                    status: tab.status,
                    isInSpace: true,
                    isInGroup: tab.groupID != nil,
                    spaceIsShared: isShared,
                    showsInEverySpace: FavoriteMigration.showsInEverySpace(tab.boardFrameData),
                    originURL: tab.originURL,
                    currentURL: tab.activePage.url,
                )
                switch FavoriteMigration.outcome(for: candidate) {
                case .unchanged:
                    break
                case .regular:
                    tab.status = .regular
                    tab.originURL = nil
                case let .favorite(home):
                    if !space.dataStoreMode.isGlobal {
                        pagePool.removePages(for: tab)
                    }
                    let placement = tab.floatingPlacement
                    tab.floatingPlacement = placement
                    moveToFavorites(tab, from: space)
                    bookmarksManager.createFavoriteBookmark(for: tab, home: home)
                    migrated += 1
                }
            }
        }
        defaults.set(true, forKey: FavoriteMigration.completedKey)
        scheduleSave()
        Logger.info("Favorites migration moved \(migrated) tabs into favorites", category: Logger.tabs)
    }
}

/// The once-per-store move of sidebar pins and "Show in Every Space" cards into favorites.
///
/// Sidebar pins (stored status `pinned`) read as `.favorite` while still sitting in a space;
/// see ``TabStatus/init(rawValue:)``. Each becomes a favorite with its pin address as home,
/// except a pin inside a pinned group, which stays in its group as a regular tab (the group
/// keeps its pin), and a pin in a private or locked space, which stays there as a regular
/// tab so it never shows in other spaces. A kept-visible card marked to show in every space
/// becomes a favorite at its current address, under the same private-or-locked rule.
nonisolated enum FavoriteMigration {
    /// The defaults key set once the migration has run.
    static let completedKey = "website.refrax.migration.favorites"

    /// A tab as the migration sees it.
    struct Candidate: Equatable, Sendable {
        var status: TabStatus
        var isInSpace: Bool
        var isInGroup: Bool
        /// The space is neither private nor locked.
        var spaceIsShared: Bool
        var showsInEverySpace: Bool
        var originURL: URL?
        var currentURL: URL
    }

    /// What the migration does to a tab.
    enum Outcome: Equatable, Sendable {
        case unchanged
        /// Stays in its space as a regular tab.
        case regular
        /// Becomes a favorite with this home address.
        case favorite(home: URL)
    }

    static func outcome(for candidate: Candidate) -> Outcome {
        switch candidate.status {
        case .favorite:
            guard candidate.isInSpace else { return .unchanged }
            guard !candidate.isInGroup, candidate.spaceIsShared else { return .regular }
            return .favorite(home: candidate.originURL ?? candidate.currentURL)
        case .regular:
            guard candidate.isInSpace, candidate.showsInEverySpace, candidate.spaceIsShared else { return .unchanged }
            return .favorite(home: candidate.currentURL)
        }
    }

    /// Whether a tab's stored board data marks its kept-visible card to show in every space.
    static func showsInEverySpace(_ boardFrameData: Data?) -> Bool {
        guard let boardFrameData,
              let stored = try? JSONDecoder().decode(StoredBoardFrame.self, from: boardFrameData),
              let floating = stored.floating else { return false }
        return floating.showsInEverySpace == true && floating.isPinned == true
    }

    /// The part of a stored ``BoardFrame`` the migration reads.
    private struct StoredBoardFrame: Decodable {
        struct Floating: Decodable {
            var isPinned: Bool?
            var showsInEverySpace: Bool?
        }

        var floating: Floating?
    }
}
