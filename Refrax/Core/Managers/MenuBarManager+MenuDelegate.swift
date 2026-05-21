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
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateEditMenu(menu)
        updateHistoryMenu(menu)
        updateRecentlyClosedMenu(menu)
        updateDevelopMenuItems(menu)
        updateWindowMenu(menu)
        updateViewMenu(menu)
    }
}
