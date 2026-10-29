import AppKit

// MARK: - View ▸ Islands

extension MenuBarManager {
    private struct IslandItem {
        let title: String
        let symbol: String
        let action: Selector
        let key: String
        let modifiers: NSEvent.ModifierFlags
    }

    private static func arrow(_ key: Int) -> String {
        String(UnicodeScalar(UInt32(key))!)
    }

    /// View ▸ Islands: step to a neighboring chip with ⌃⌘ arrows, and make a new island
    /// from the current chip with ⌃⌘I.
    func createTableMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Islands")
        let focus: NSEvent.ModifierFlags = [.control, .command]
        let groups: [[IslandItem]] = [
            [
                IslandItem(title: "Tab Left", symbol: "arrow.left", action: #selector(tableFocusLeft(_:)), key: Self.arrow(NSLeftArrowFunctionKey), modifiers: focus),
                IslandItem(title: "Tab Right", symbol: "arrow.right", action: #selector(tableFocusRight(_:)), key: Self.arrow(NSRightArrowFunctionKey), modifiers: focus),
                IslandItem(title: "Tab Above", symbol: "arrow.up", action: #selector(tableFocusUp(_:)), key: Self.arrow(NSUpArrowFunctionKey), modifiers: focus),
                IslandItem(title: "Tab Below", symbol: "arrow.down", action: #selector(tableFocusDown(_:)), key: Self.arrow(NSDownArrowFunctionKey), modifiers: focus),
            ],
            [
                IslandItem(title: "New Island from Here", symbol: "plus.rectangle.on.rectangle", action: #selector(tableNewIsland(_:)), key: "i", modifiers: focus),
                IslandItem(title: "Arrange Islands Along Left Edge", symbol: "rectangle.leadinghalf.inset.filled", action: #selector(arrangeIslands(_:)), key: "", modifiers: []),
                IslandItem(title: "Use Free Island Placement", symbol: "rectangle.3.group", action: #selector(freeIslandPlacement(_:)), key: "", modifiers: []),
            ],
        ]
        for (index, group) in groups.enumerated() {
            if index > 0 {
                menu.addItem(.separator())
            }
            for entry in group {
                let item = NSMenuItem(title: entry.title, action: entry.action, keyEquivalent: entry.key)
                item.keyEquivalentModifierMask = entry.modifiers
                item.image = NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil)
                item.target = self
                menu.addItem(item)
            }
        }
        let item = NSMenuItem(title: "Islands", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: nil)
        item.submenu = menu
        return item
    }

    private var activeIslands: IslandController? {
        activeWindowController?.islandController
    }

    @objc
    private func arrangeIslands(_: Any?) {
        activeIslands?.arrangeAutomatically()
    }
    @objc
    private func freeIslandPlacement(_: Any?) {
        activeIslands?.useFreePlacement()
    }

    @objc
    func tableFocusLeft(_: Any?) {
        activeIslands?.step(.left)
    }

    @objc
    func tableFocusRight(_: Any?) {
        activeIslands?.step(.right)
    }

    @objc
    func tableFocusUp(_: Any?) {
        activeIslands?.step(.up)
    }

    @objc
    func tableFocusDown(_: Any?) {
        activeIslands?.step(.down)
    }

    @objc
    func tableNewIsland(_: Any?) {
        activeIslands?.perform(.newIsland)
    }
}
