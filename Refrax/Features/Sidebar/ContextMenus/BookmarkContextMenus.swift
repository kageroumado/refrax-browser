import AppKit
import SwiftUI

// MARK: - Favorite Context Menu

extension SidebarContextMenus {
    /// Context menu for a favorite item (shortcut or live tab).
    struct Favorite: View {
        @SwiftUI.Environment(TabManager.self) private var tabManager
        @SwiftUI.Environment(BookmarksManager.self) private var bookmarksManager
        @SwiftUI.Environment(SharingCoordinator.self) private var sharingCoordinator
        @SwiftUI.Environment(WebPagePool.self) private var pagePool

        let item: FavoriteItem
        var onOpen: (() -> Void)?
        var onOpenInWindow: (() -> Void)?
        var onGetInfo: (() -> Void)?
        var onPreview: (() -> Void)?

        var body: some View {
            switch item.type {
            case let .shortcut(bookmark):
                shortcutMenu(bookmark)
            case let .liveFavorite(bookmark, tab):
                liveTabMenu(bookmark, tab: tab)
            case .folder:
                EmptyView()
            case let .appShortcut(shortcut):
                appShortcutMenu(shortcut)
            }
        }

        @ViewBuilder
        private func appShortcutMenu(_ shortcut: AppShortcut) -> some View {
            Button {
                onOpen?()
            } label: {
                Label("Open", systemImage: ContextMenuIcon.open.systemName)
            }

            Button {
                onOpenInWindow?()
            } label: {
                Label("Open in Window", systemImage: ContextMenuIcon.openInWindow.systemName)
            }

            Divider()

            Button {
                bookmarksManager.removeAppShortcut(shortcut)
            } label: {
                Label("Remove from Favorites", systemImage: ContextMenuIcon.removeFromFavorites.systemName)
            }
        }

        @ViewBuilder
        private func shortcutMenu(_ bookmark: Bookmark) -> some View {
            Button {
                onOpen?()
            } label: {
                Label("Open", systemImage: ContextMenuIcon.open.systemName)
            }

            Button {
                _ = tabManager.createTab(url: bookmark.url)
            } label: {
                Label("Open in New Tab", systemImage: ContextMenuIcon.openInNewTab.systemName)
            }

            if let onPreview {
                Button(action: onPreview) {
                    Label("Preview", systemImage: "eye")
                }
            }

            Divider()

            Button {
                bookmarksManager.changeFavoriteMode(bookmark, to: .liveFavorite)
            } label: {
                Label("Convert to Tab", systemImage: ContextMenuIcon.convertToLiveTab.systemName)
            }

            Divider()

            // Copy/Share
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(bookmark.url.absoluteString, forType: .string)
            } label: {
                Label("Copy URL", systemImage: ContextMenuIcon.copyURL.systemName)
            }

            Button {
                let markdown = "[\(bookmark.title)](\(bookmark.url.absoluteString))"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(markdown, forType: .string)
            } label: {
                Label("Copy URL as Markdown", systemImage: ContextMenuIcon.copyURL.systemName)
            }

            Button {
                sharingCoordinator.shareURL(bookmark.url, title: bookmark.title)
            } label: {
                Label("Share...", systemImage: ContextMenuIcon.share.systemName)
            }

            Divider()

            Button {
                bookmarksManager.removeFromFavorites(bookmark)
            } label: {
                Label("Remove from Favorites", systemImage: ContextMenuIcon.removeFromFavorites.systemName)
            }

            Button(role: .destructive) {
                bookmarksManager.deleteBookmark(bookmark)
            } label: {
                Label("Delete Bookmark", systemImage: ContextMenuIcon.delete.systemName)
            }
        }

        @ViewBuilder
        private func liveTabMenu(_ bookmark: Bookmark, tab: Refrax.Tab) -> some View {
            // Get Info (live favorites have an associated tab)
            Button {
                onGetInfo?()
            } label: {
                Label("Get Info", systemImage: ContextMenuIcon.info.systemName)
            }

            if let onPreview {
                Button(action: onPreview) {
                    Label("Preview", systemImage: "eye")
                }
            }

            Divider()

            // Navigation containment options
            if tab.hasNavigatedFromHome, let homeURL = tab.homeURL {
                Button {
                    if let webPage = pagePool.existingPage(for: tab.activePage) {
                        webPage.load(homeURL)
                    }
                } label: {
                    Label("Go to Home", systemImage: "house")
                }
            }

            Button {
                // Update the bookmark URL to the current page URL
                bookmark.url = tab.activePage.url
            } label: {
                Label("Set Current Page as Home", systemImage: "house")
            }

            Divider()

            Button {
                bookmarksManager.changeFavoriteMode(bookmark, to: .shortcut)
            } label: {
                Label("Convert to Shortcut", systemImage: ContextMenuIcon.convertToShortcut.systemName)
            }

            Divider()

            // Copy/Share
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(bookmark.url.absoluteString, forType: .string)
            } label: {
                Label("Copy URL", systemImage: ContextMenuIcon.copyURL.systemName)
            }

            Button {
                let markdown = "[\(bookmark.title)](\(bookmark.url.absoluteString))"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(markdown, forType: .string)
            } label: {
                Label("Copy URL as Markdown", systemImage: ContextMenuIcon.copyURL.systemName)
            }

            Button {
                sharingCoordinator.shareURL(bookmark.url, title: bookmark.title)
            } label: {
                Label("Share...", systemImage: ContextMenuIcon.share.systemName)
            }

            Divider()

            Button {
                bookmarksManager.removeFromFavorites(bookmark)
            } label: {
                Label("Remove from Favorites", systemImage: ContextMenuIcon.removeFromFavorites.systemName)
            }

            Button(role: .destructive) {
                bookmarksManager.deleteBookmark(bookmark)
            } label: {
                Label("Delete Bookmark", systemImage: ContextMenuIcon.delete.systemName)
            }
        }
    }

    /// Context menu for a folder in the favorites grid.
    struct FolderFavorite: View {
        @SwiftUI.Environment(BookmarksManager.self) private var bookmarksManager
        @SwiftUI.Environment(SharingCoordinator.self) private var sharingCoordinator

        let folder: BookmarkFolder

        /// Bookmarks in this folder for copy/share operations.
        private var bookmarksInFolder: [Bookmark] {
            bookmarksManager.bookmarks(in: folder)
        }

        /// Folder name with emoji prefix if the custom icon is an emoji.
        private var displayNameWithIcon: String {
            if let icon = folder.customIcon, case let .emoji(emoji) = icon {
                return "\(emoji) \(folder.name)"
            }
            return folder.name
        }

        var body: some View {
            if !bookmarksInFolder.isEmpty {
                // Copy/Share
                Button {
                    let urls = bookmarksInFolder.map(\.url.absoluteString)
                    let joined = urls.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(joined, forType: .string)
                } label: {
                    Label("Copy URLs", systemImage: ContextMenuIcon.copyURL.systemName)
                }

                Button {
                    var lines: [String] = []
                    lines.append("## \(displayNameWithIcon)")
                    for bookmark in bookmarksInFolder {
                        lines.append("- [\(bookmark.title)](\(bookmark.url.absoluteString))")
                    }
                    let markdown = lines.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                } label: {
                    Label("Copy URLs as Markdown", systemImage: ContextMenuIcon.copyURL.systemName)
                }

                Button {
                    // Share all URLs as a list
                    let urls = bookmarksInFolder.compactMap(\.url)
                    if let firstURL = urls.first {
                        sharingCoordinator.shareURL(firstURL, title: folder.name)
                    }
                } label: {
                    Label("Share...", systemImage: ContextMenuIcon.share.systemName)
                }

                Divider()
            }

            Button {
                bookmarksManager.removeFolderFromFavorites(folder)
            } label: {
                Label("Remove from Favorites", systemImage: ContextMenuIcon.removeFromFavorites.systemName)
            }
        }
    }
}
