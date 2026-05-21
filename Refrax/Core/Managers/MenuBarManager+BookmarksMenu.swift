import AppKit

// MARK: - Bookmarks Menu

extension MenuBarManager {
    func createBookmarksMenu() -> NSMenuItem {
        let bookmarksMenuItem = NSMenuItem()
        let bookmarksMenu = NSMenu(title: "Bookmarks")

        let addBookmarkItem = NSMenuItem(
            title: "Add Bookmark…",
            action: #selector(addBookmark(_:)),
            keyEquivalent: "d",
        )
        addBookmarkItem.image = NSImage(systemSymbolName: "bookmark", accessibilityDescription: nil)
        addBookmarkItem.target = self
        bookmarksMenu.addItem(addBookmarkItem)

        bookmarksMenu.addItem(.separator())

        let showBookmarksItem = NSMenuItem(
            title: "Show Bookmarks",
            action: #selector(showBookmarks(_:)),
            keyEquivalent: "b",
        )
        showBookmarksItem.keyEquivalentModifierMask = [.command, .option]
        showBookmarksItem.image = NSImage(systemSymbolName: "book", accessibilityDescription: nil)
        showBookmarksItem.target = self
        bookmarksMenu.addItem(showBookmarksItem)

        bookmarksMenu.addItem(.separator())

        let importItem = NSMenuItem(
            title: "Import from Other Browsers…",
            action: #selector(importBookmarks(_:)),
            keyEquivalent: "",
        )
        importItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
        importItem.target = self
        bookmarksMenu.addItem(importItem)

        let importFileItem = NSMenuItem(
            title: "Import Bookmarks File…",
            action: #selector(importBookmarksFile(_:)),
            keyEquivalent: "",
        )
        importFileItem.target = self
        bookmarksMenu.addItem(importFileItem)

        // Export submenu with HTML and JSON options
        let exportItem = NSMenuItem(title: "Export Bookmarks", action: nil, keyEquivalent: "")
        exportItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        let exportSubmenu = NSMenu(title: "Export Bookmarks")

        let exportHTMLItem = NSMenuItem(
            title: "HTML…",
            action: #selector(exportBookmarksHTML(_:)),
            keyEquivalent: "",
        )
        exportHTMLItem.target = self
        exportSubmenu.addItem(exportHTMLItem)

        let exportJSONItem = NSMenuItem(
            title: "JSON…",
            action: #selector(exportBookmarksJSON(_:)),
            keyEquivalent: "",
        )
        exportJSONItem.target = self
        exportSubmenu.addItem(exportJSONItem)

        exportItem.submenu = exportSubmenu
        bookmarksMenu.addItem(exportItem)

        bookmarksMenuItem.submenu = bookmarksMenu
        return bookmarksMenuItem
    }

    @objc
    func addBookmark(_: Any?) {
        // TODO: Implement add bookmark
    }

    @objc
    func showBookmarks(_: Any?) {
        activeWindowController?.windowState.toggleDetailTray(.bookmarks)
    }

    @objc
    func importBookmarks(_: Any?) {
        windowManager.showBookmarkImport()
    }

    @objc
    func importBookmarksFile(_: Any?) {
        windowManager.importBookmarksFromFile()
    }

    @objc
    func exportBookmarksHTML(_: Any?) {
        windowManager.exportBookmarksHTML()
    }

    @objc
    func exportBookmarksJSON(_: Any?) {
        windowManager.exportBookmarksJSON()
    }
}
