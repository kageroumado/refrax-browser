import Foundation

/// A favorite item displayed in the sidebar grid.
///
/// Represents a live favorite tab, shortcut bookmark, folder, or app shortcut.
/// Live favorites are the default and create persistent global tabs.
struct FavoriteItem: Identifiable {
    let id: UUID
    let type: ItemType
    let position: FavoritePosition

    /// The type of favorite item.
    enum ItemType {
        /// A live favorite with its underlying tab.
        ///
        /// Live favorites are persistent global tabs visible across all spaces.
        /// The associated `Tab` is the actual tab instance stored in BrowserState.
        case liveFavorite(Bookmark, Tab)

        /// A shortcut bookmark that navigates the current tab.
        case shortcut(Bookmark)

        /// A folder of bookmarks.
        case folder(BookmarkFolder)

        /// An app feature shortcut (Downloads, Bookmarks, History, Settings).
        case appShortcut(AppShortcut)
    }

    /// The bookmark associated with this item, if any.
    var bookmark: Bookmark? {
        switch type {
        case let .liveFavorite(bookmark, _), let .shortcut(bookmark):
            bookmark
        case .folder, .appShortcut:
            nil
        }
    }

    /// The live favorite tab, if this is a live favorite.
    var tab: Tab? {
        if case let .liveFavorite(_, tab) = type {
            return tab
        }
        return nil
    }

    /// The app shortcut, if this is an app shortcut.
    var appShortcut: AppShortcut? {
        if case let .appShortcut(shortcut) = type {
            return shortcut
        }
        return nil
    }

    var displayName: String {
        switch type {
        case let .liveFavorite(_, tab):
            // Use the tab's display title for live favorites - it reflects the current page title
            tab.displayTitle
        case let .shortcut(bookmark):
            bookmark.displayName
        case let .folder(folder):
            folder.name
        case let .appShortcut(shortcut):
            shortcut.displayName
        }
    }

    var color: String? {
        switch type {
        case let .liveFavorite(bookmark, _), let .shortcut(bookmark):
            bookmark.favoriteColor
        case let .folder(folder):
            folder.color
        case let .appShortcut(shortcut):
            shortcut.color
        }
    }

    var customIcon: BookmarkIcon? {
        switch type {
        case let .liveFavorite(bookmark, _), let .shortcut(bookmark):
            bookmark.customIcon
        case let .folder(folder):
            folder.customIcon
        case .appShortcut:
            nil // App shortcuts use SF Symbols, not custom icons
        }
    }

    /// SF Symbol name for app shortcuts and folders.
    var sfSymbol: String? {
        switch type {
        case let .appShortcut(shortcut):
            shortcut.iconName
        case .folder:
            "folder.fill"
        case .liveFavorite, .shortcut:
            nil
        }
    }

    /// Small favicon data for bookmarks (~64px, for tab lists).
    ///
    /// For live favorites, prioritizes the tab's favicon since it stays current
    /// as the user navigates. Falls back to bookmark's cached favicon.
    var faviconData: Data? {
        switch type {
        case let .liveFavorite(bookmark, tab):
            // Prefer live tab's favicon (updated during navigation)
            tab.activePage.faviconData ?? bookmark.faviconData
        case let .shortcut(bookmark):
            bookmark.faviconData
        case .folder, .appShortcut:
            nil
        }
    }

    /// Large favicon data for bookmarks (~180px, for favorites grid).
    ///
    /// For live favorites, prioritizes the tab's large favicon since it stays current
    /// as the user navigates. Falls back to bookmark's cached large favicon, then small favicon.
    var largeFaviconData: Data? {
        switch type {
        case let .liveFavorite(bookmark, tab):
            // Prefer large favicon from either source, fall back to small
            tab.activePage.largeFaviconData
                ?? bookmark.largeFaviconData
                ?? tab.activePage.faviconData
                ?? bookmark.faviconData
        case let .shortcut(bookmark):
            bookmark.largeFaviconData ?? bookmark.faviconData
        case .folder, .appShortcut:
            nil
        }
    }

    var itemCount: Int? {
        if case let .folder(folder) = type {
            return folder.itemCount
        }
        return nil
    }

    /// The URL associated with this item, if any.
    var url: URL? {
        bookmark?.url
    }

    /// Whether this item is draggable to the tab list.
    ///
    /// App shortcuts and folders cannot be converted to tabs.
    var isDraggableToTabs: Bool {
        switch type {
        case .liveFavorite, .shortcut:
            true
        case .folder, .appShortcut:
            false
        }
    }
}
