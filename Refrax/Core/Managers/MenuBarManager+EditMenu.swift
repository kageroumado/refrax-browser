import AppKit

// MARK: - Edit Menu

extension MenuBarManager {
    func createEditMenu() -> NSMenuItem {
        let editMenuItem = NSMenuItem()
        let menu = NSMenu(title: "Edit")
        menu.delegate = self
        editMenu = menu

        // Standard Undo - uses responder chain so WebKit text fields respond
        let undoItem = NSMenuItem(
            title: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z",
        )
        undoItem.target = nil // Use responder chain
        undoItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        menu.addItem(undoItem)

        // Standard Redo - uses responder chain so WebKit text fields respond
        let redoItem = NSMenuItem(
            title: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "z",
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        redoItem.target = nil // Use responder chain
        redoItem.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: nil)
        menu.addItem(redoItem)

        menu.addItem(.separator())

        // Browser-level Undo (Close Tab, Delete Group, etc.)
        // These are separate from WebKit's text editing undo because WKWebView
        // claims ownership of undo:/redo: selectors even when it has nothing to undo.
        let browserUndoItem = NSMenuItem(
            title: "Undo",
            action: #selector(browserUndo(_:)),
            keyEquivalent: "",
        )
        browserUndoItem.target = self
        browserUndoItem.tag = MenuItemTag.browserUndo.rawValue
        browserUndoItem.image = NSImage(systemSymbolName: "arrow.uturn.backward.circle", accessibilityDescription: nil)
        menu.addItem(browserUndoItem)

        // Browser-level Redo
        let browserRedoItem = NSMenuItem(
            title: "Redo",
            action: #selector(browserRedo(_:)),
            keyEquivalent: "",
        )
        browserRedoItem.target = self
        browserRedoItem.tag = MenuItemTag.browserRedo.rawValue
        browserRedoItem.image = NSImage(systemSymbolName: "arrow.uturn.forward.circle", accessibilityDescription: nil)
        menu.addItem(browserRedoItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x",
        ))

        menu.addItem(NSMenuItem(
            title: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c",
        ))

        menu.addItem(NSMenuItem(
            title: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v",
        ))

        menu.addItem(NSMenuItem(
            title: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a",
        ))

        menu.addItem(.separator())

        // Find
        let findItem = NSMenuItem(
            title: "Find…",
            action: #selector(performFind(_:)),
            keyEquivalent: "f",
        )
        findItem.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        findItem.target = self
        menu.addItem(findItem)

        editMenuItem.submenu = menu
        return editMenuItem
    }

    @objc
    func browserUndo(_: Any?) {
        if undoRedoManager.undoManager.canUndo {
            undoRedoManager.undoManager.undo()
        }
    }

    @objc
    func browserRedo(_: Any?) {
        if undoRedoManager.undoManager.canRedo {
            undoRedoManager.undoManager.redo()
        }
    }

    @objc
    func performFind(_: Any?) {
        windowManager.showPageSearch()
    }

    func updateEditMenu(_ menu: NSMenu) {
        guard menu.title == "Edit" else { return }

        for item in menu.items {
            switch item.tag {
            case MenuItemTag.browserUndo.rawValue:
                // Update title with action name (e.g., "Undo Close Tab \"GitHub\"")
                item.title = undoRedoManager.undoMenuTitle
                item.isEnabled = undoRedoManager.undoManager.canUndo
                // Hide if nothing to undo to reduce clutter
                item.isHidden = !undoRedoManager.undoManager.canUndo

            case MenuItemTag.browserRedo.rawValue:
                // Update title with action name
                item.title = undoRedoManager.redoMenuTitle
                item.isEnabled = undoRedoManager.undoManager.canRedo
                // Hide if nothing to redo to reduce clutter
                item.isHidden = !undoRedoManager.undoManager.canRedo

            default:
                break
            }
        }
    }
}
