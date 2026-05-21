import AppKit

// MARK: - History Menu

extension MenuBarManager {
    func createHistoryMenu() -> NSMenuItem {
        let historyMenuItem = NSMenuItem()
        let historyMenu = NSMenu(title: "History")
        historyMenu.delegate = self

        let backItem = NSMenuItem(
            title: "Back",
            action: #selector(goBack(_:)),
            keyEquivalent: "[",
        )
        backItem.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
        backItem.target = self
        historyMenu.addItem(backItem)

        let forwardItem = NSMenuItem(
            title: "Forward",
            action: #selector(goForward(_:)),
            keyEquivalent: "]",
        )
        forwardItem.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        forwardItem.target = self
        historyMenu.addItem(forwardItem)

        historyMenu.addItem(.separator())

        // Reopen Last Closed Tab (Cmd+Shift+T)
        let reopenItem = NSMenuItem(
            title: "Reopen Last Closed Tab",
            action: #selector(reopenLastClosedTab(_:)),
            keyEquivalent: "t",
        )
        reopenItem.keyEquivalentModifierMask = [.command, .shift]
        reopenItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        reopenItem.target = self
        reopenItem.tag = MenuItemTag.reopenLastClosedTab.rawValue
        historyMenu.addItem(reopenItem)

        // Recently Closed submenu
        let recentlyClosedItem = NSMenuItem(
            title: "Recently Closed",
            action: nil,
            keyEquivalent: "",
        )
        recentlyClosedItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: nil)
        let recentlyClosedSubmenu = NSMenu(title: "Recently Closed")
        recentlyClosedSubmenu.delegate = self
        recentlyClosedItem.submenu = recentlyClosedSubmenu
        recentlyClosedMenu = recentlyClosedSubmenu
        historyMenu.addItem(recentlyClosedItem)

        // Save Snapshot Now (Cmd+Shift+S)
        let saveSnapshotItem = NSMenuItem(
            title: "Save Snapshot Now",
            action: #selector(saveSnapshotNow(_:)),
            keyEquivalent: "s",
        )
        saveSnapshotItem.keyEquivalentModifierMask = [.command, .shift]
        saveSnapshotItem.image = NSImage(systemSymbolName: "camera", accessibilityDescription: nil)
        saveSnapshotItem.target = self
        historyMenu.addItem(saveSnapshotItem)

        historyMenu.addItem(.separator())

        let showHistoryItem = NSMenuItem(
            title: "Show All History",
            action: #selector(showAllHistory(_:)),
            keyEquivalent: "y",
        )
        showHistoryItem.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
        showHistoryItem.target = self
        historyMenu.addItem(showHistoryItem)

        historyMenuItem.submenu = historyMenu
        return historyMenuItem
    }

    @objc
    func goBack(_: Any?) {
        activeWindowController?.windowState.activeWebPage?.goBack()
    }

    @objc
    func goForward(_: Any?) {
        activeWindowController?.windowState.activeWebPage?.goForward()
    }

    @objc
    func showAllHistory(_: Any?) {
        activeWindowController?.windowState.toggleDetailTray(.history)
    }

    @objc
    func saveSnapshotNow(_: Any?) {
        guard let windowState = activeWindowController?.windowState,
              let space = windowState.activeSpace else { return }

        let tabs = space.tabs
        let activeTab = windowState.activeTab

        let created = windowManager.historyManager.createManualSnapshot(tabs: tabs, activeTab: activeTab)
        if created {
            windowState.showToast("Snapshot saved")
        }
    }

    @objc
    func reopenLastClosedTab(_: Any?) {
        undoRedoManager.reopenLastClosedTab()
    }

    @objc
    func reopenClosedTab(_ sender: Any?) {
        guard let menuItem = sender as? NSMenuItem else { return }
        let index = menuItem.tag
        undoRedoManager.reopenClosedTab(at: index)
    }

    func updateHistoryMenu(_ menu: NSMenu) {
        guard menu.title == "History" else { return }

        for item in menu.items {
            switch item.tag {
            case MenuItemTag.reopenLastClosedTab.rawValue:
                item.isEnabled = !undoRedoManager.recentlyClosedTabs.isEmpty

            default:
                break
            }
        }
    }

    func updateRecentlyClosedMenu(_ menu: NSMenu) {
        guard menu.title == "Recently Closed" else { return }

        menu.removeAllItems()

        let recentlyClosedTabs = undoRedoManager.recentlyClosedTabs
        if recentlyClosedTabs.isEmpty {
            let emptyItem = NSMenuItem(
                title: "No Recently Closed Tabs",
                action: nil,
                keyEquivalent: "",
            )
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for (index, tabInfo) in recentlyClosedTabs.enumerated() {
                let tabItem = NSMenuItem(
                    title: tabInfo.title,
                    action: #selector(reopenClosedTab(_:)),
                    keyEquivalent: "",
                )
                tabItem.target = self
                tabItem.tag = index
                tabItem.toolTip = tabInfo.url.absoluteString

                if tabInfo.isReferenceTab {
                    tabItem.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil)
                }

                menu.addItem(tabItem)
            }
        }
    }
}
