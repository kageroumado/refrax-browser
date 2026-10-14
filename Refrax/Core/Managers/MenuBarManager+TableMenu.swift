import AppKit

// MARK: - View ▸ Table

extension MenuBarManager {
    /// One of the Table submenu's keyed items.
    private struct TableItem {
        let title: String
        let symbol: String
        let action: Selector
        let key: String
        let modifiers: NSEvent.ModifierFlags
    }

    private static func arrow(_ key: Int) -> String {
        String(UnicodeScalar(UInt32(key))!)
    }

    /// View ▸ Table: move focus with ⌃⌘ arrows, move the slab with ⌃⌘⇧ arrows, cycle its
    /// width with ⌃⌘R, and fill the width with ⌃⌘⇧F (⌃⌘F is Enter Full Screen).
    func createTableMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Table")
        let focus: NSEvent.ModifierFlags = [.control, .command]
        let move: NSEvent.ModifierFlags = [.control, .command, .shift]
        let groups: [[TableItem]] = [
            [
                TableItem(title: "Focus Slab Left", symbol: "arrow.left", action: #selector(tableFocusLeft(_:)), key: Self.arrow(NSLeftArrowFunctionKey), modifiers: focus),
                TableItem(title: "Focus Slab Right", symbol: "arrow.right", action: #selector(tableFocusRight(_:)), key: Self.arrow(NSRightArrowFunctionKey), modifiers: focus),
                TableItem(title: "Row Up", symbol: "arrow.up", action: #selector(tableFocusUp(_:)), key: Self.arrow(NSUpArrowFunctionKey), modifiers: focus),
                TableItem(title: "Row Down", symbol: "arrow.down", action: #selector(tableFocusDown(_:)), key: Self.arrow(NSDownArrowFunctionKey), modifiers: focus),
            ],
            [
                TableItem(title: "Move Slab Left", symbol: "arrow.left.square", action: #selector(tableMoveLeft(_:)), key: Self.arrow(NSLeftArrowFunctionKey), modifiers: move),
                TableItem(title: "Move Slab Right", symbol: "arrow.right.square", action: #selector(tableMoveRight(_:)), key: Self.arrow(NSRightArrowFunctionKey), modifiers: move),
                TableItem(title: "Move Slab Up", symbol: "arrow.up.square", action: #selector(tableMoveUp(_:)), key: Self.arrow(NSUpArrowFunctionKey), modifiers: move),
                TableItem(title: "Move Slab Down", symbol: "arrow.down.square", action: #selector(tableMoveDown(_:)), key: Self.arrow(NSDownArrowFunctionKey), modifiers: move),
            ],
            [
                TableItem(title: "Cycle Width", symbol: "arrow.left.and.right", action: #selector(tableCycleWidth(_:)), key: "r", modifiers: focus),
                TableItem(title: "Fill Width", symbol: "arrow.up.left.and.arrow.down.right", action: #selector(tableToggleFill(_:)), key: "f", modifiers: move),
                TableItem(title: "Move to New Row", symbol: "rectangle.split.1x2", action: #selector(tableMoveToNewRow(_:)), key: "", modifiers: []),
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
        let item = NSMenuItem(title: "Table", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: nil)
        item.submenu = menu
        return item
    }

    private var activeTable: TableController? {
        activeWindowController?.tableController
    }

    @objc
    func tableFocusLeft(_: Any?) {
        activeTable?.step(.left)
    }

    @objc
    func tableFocusRight(_: Any?) {
        activeTable?.step(.right)
    }

    @objc
    func tableFocusUp(_: Any?) {
        activeTable?.step(.up)
    }

    @objc
    func tableFocusDown(_: Any?) {
        activeTable?.step(.down)
    }

    @objc
    func tableMoveLeft(_: Any?) {
        activeTable?.moveFocusedSlab(.left)
    }

    @objc
    func tableMoveRight(_: Any?) {
        activeTable?.moveFocusedSlab(.right)
    }

    @objc
    func tableMoveUp(_: Any?) {
        activeTable?.moveFocusedSlab(.up)
    }

    @objc
    func tableMoveDown(_: Any?) {
        activeTable?.moveFocusedSlab(.down)
    }

    @objc
    func tableCycleWidth(_: Any?) {
        activeTable?.cycleWidth()
    }

    @objc
    func tableToggleFill(_: Any?) {
        activeTable?.toggleFill()
    }

    @objc
    func tableMoveToNewRow(_: Any?) {
        guard let controller = activeWindowController, let tab = controller.windowState.activeTab else { return }
        controller.tableController.moveToNewRow(tab)
    }
}
