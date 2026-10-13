import AppKit

/// Actions bound to the page identified by the current-tab card.
struct ControlIslandTabActions {
    let tab: Tab
    let windowState: WindowState
    let tabs: TabManager
    let bookmarks: BookmarksManager

    var isFavorite: Bool {
        tab.isFavorite && tab.linkedBookmark?.isFavorite == true
    }

    var canFavorite: Bool {
        isFavorite || (tab.space != nil && tabs.state.favoriteTabs.count < bookmarks._maxLiveFavoriteTabs)
    }

    /// Favorite, or Remove from Favorites. The tab keeps its identity and floating place
    /// either way; a removed favorite moves into the window's active space.
    func toggleFavorite() {
        guard canFavorite else { return }
        windowState.pageVisit.isTransformingIdentity = true
        defer { windowState.pageVisit.isTransformingIdentity = false }
        let wasFavorite = isFavorite
        guard tabs.toggleFavorite(tab, in: windowState) else { return }
        windowState.showToast("\(wasFavorite ? "Removed from Favorites" : "Added to Favorites") · \(tab.displayTitle)")
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
        if tab.isFavorite {
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
