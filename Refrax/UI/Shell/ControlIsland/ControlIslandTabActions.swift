import AppKit

/// Actions bound to the page identified by the current-tab card.
struct ControlIslandTabActions {
    let tab: Tab
    let windowState: WindowState
    let tabs: TabManager
    let bookmarks: BookmarksManager

    var isFavorite: Bool {
        tab.isLiveFavorite && tab.linkedBookmark?.isFavorite == true
    }

    var canFavorite: Bool {
        isFavorite || (tab.space != nil && tabs.state.liveFavoriteTabs.count < bookmarks._maxLiveFavoriteTabs)
    }

    func toggleFavorite() {
        guard canFavorite else { return }
        windowState.pageVisit.isTransformingIdentity = true
        defer { windowState.pageVisit.isTransformingIdentity = false }
        if isFavorite, let bookmark = tab.linkedBookmark {
            bookmarks.removeFromFavorites(bookmark, in: windowState)
            windowState.showToast("Removed from Favorites · \(tab.displayTitle)")
        } else {
            let placement = tab.boardFrameData
            guard let id = tabs.convertTabToFavorite(tab, mode: .liveFavorite, in: windowState),
                  let favorite = tabs.state.liveFavoriteTab(for: id) else { return }
            favorite.boardFrameData = placement
            windowState.pageVisit.replaceIdentity(of: tab.id, with: favorite)
            if let layout = windowState.floatingPlacements.removeValue(forKey: tab.id) {
                windowState.floatingPlacements[favorite.id] = layout
            }
            windowState.showToast("Added to Favorites · \(favorite.displayTitle)")
        }
        bookmarks.refreshFavoritesCache()
    }

    func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tabs.copyableURL(for: tab), forType: .string)
    }

    func copyMarkdownLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("[\(tab.displayTitle)](\(tabs.copyableURL(for: tab)))", forType: .string)
    }

    @discardableResult
    func duplicate() -> Tab? {
        let duplicate: Tab
        if tab.isLiveFavorite {
            guard let space = windowState.activeSpace else { return nil }
            duplicate = tabs.createTab(url: tab.activePage.url, in: space, makeActive: false)
            duplicate.activePage.title = tab.activePage.title
            duplicate.activePage.faviconData = tab.activePage.faviconData
            duplicate.activePage.largeFaviconData = tab.activePage.largeFaviconData
        } else {
            duplicate = tabs.duplicateTab(tab)
        }
        tabs.setActiveTab(duplicate, in: windowState)
        return duplicate
    }
}
