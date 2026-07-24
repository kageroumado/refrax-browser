import AppKit

// MARK: - NSMenuDelegate

extension MenuBarManager {
    func menuWillOpen(_ menu: NSMenu) {
        updateEditMenu(menu)
        updateHistoryMenu(menu)
        updateRecentlyClosedMenu(menu)
        updateDevelopMenuItems(menu)
        updateWindowMenu(menu)
        updateViewMenu(menu)
        updateAppMenu(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateEditMenu(menu)
        updateHistoryMenu(menu)
        updateRecentlyClosedMenu(menu)
        updateDevelopMenuItems(menu)
        updateWindowMenu(menu)
        updateViewMenu(menu)
        updateAppMenu(menu)
    }

    private func updateAppMenu(_ menu: NSMenu) {
        guard let updateItem = menu.item(withTag: MenuItemTag.checkForUpdates.rawValue) else { return }
        switch NSApp.typedDelegate.appUpdateManager.phase {
        case .readyToInstall(let update):
            updateItem.title = "Restart to Update — v\(update.version)…"
        case .downloading:
            updateItem.title = "Downloading Update…"
        default:
            updateItem.title = "Check for Updates…"
        }
    }
}
