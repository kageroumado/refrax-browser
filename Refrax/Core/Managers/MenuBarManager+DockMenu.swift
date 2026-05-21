import AppKit

// MARK: - Dock Menu

extension MenuBarManager {
    func createDockMenu() -> NSMenu? {
        let dockMenu = NSMenu()

        // New Window
        let newWindowItem = NSMenuItem(
            title: "New Window",
            action: #selector(openNewWindow(_:)),
            keyEquivalent: "",
        )
        newWindowItem.target = self
        dockMenu.addItem(newWindowItem)

        // New Tab (in frontmost window)
        let newTabItem = NSMenuItem(
            title: "Open Command Lens",
            action: #selector(openCommandLens(_:)),
            keyEquivalent: "",
        )
        newTabItem.target = self
        dockMenu.addItem(newTabItem)

        // Recently Closed section
        let recentlyClosedTabs = undoRedoManager.recentlyClosedTabs
        if !recentlyClosedTabs.isEmpty {
            dockMenu.addItem(.separator())

            let recentlyClosedHeader = NSMenuItem(
                title: "Recently Closed",
                action: nil,
                keyEquivalent: "",
            )
            recentlyClosedHeader.isEnabled = false
            dockMenu.addItem(recentlyClosedHeader)

            // Add recently closed tabs
            for (index, tab) in recentlyClosedTabs.enumerated() {
                let tabItem = NSMenuItem(
                    title: tab.title,
                    action: #selector(reopenClosedTab(_:)),
                    keyEquivalent: "",
                )
                tabItem.target = self
                tabItem.tag = index
                tabItem.toolTip = tab.url.absoluteString
                dockMenu.addItem(tabItem)
            }
        }

        return dockMenu
    }
}
