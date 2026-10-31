import AppKit

// MARK: - Edit Menu

extension MenuBarManager {
    func createEditMenu() -> NSMenuItem {
        let editMenuItem = NSMenuItem()
        let menu = NSMenu(title: "Edit")
        menu.delegate = self
        editMenu = menu

        let undoItem = NSMenuItem(title: "Undo", action: #selector(browserUndo(_:)), keyEquivalent: "z")
        undoItem.target = self
        undoItem.tag = MenuItemTag.browserUndo.rawValue
        undoItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
        menu.addItem(undoItem)

        let redoItem = NSMenuItem(title: "Redo", action: #selector(browserRedo(_:)), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        redoItem.target = self
        redoItem.tag = MenuItemTag.browserRedo.rawValue
        redoItem.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: nil)
        menu.addItem(redoItem)
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

    /// Text editing uses its responder's history; browser edits use the shared history.
    func editingUndoManager(redo: Bool) -> UndoManager {
        if let native = focusedUndoManager,
           redo ? native.canRedo : native.canUndo {
            return native
        }
        return undoRedoManager.undoManager
    }

    @objc
    func browserUndo(_: Any?) {
        let manager = editingUndoManager(redo: false)
        if manager.canUndo {
            manager.undo()
        }
    }

    @objc
    func browserRedo(_: Any?) {
        let manager = editingUndoManager(redo: true)
        if manager.canRedo {
            manager.redo()
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
                let manager = editingUndoManager(redo: false)
                item.title = manager.undoMenuItemTitle
                item.isEnabled = manager.canUndo

            case MenuItemTag.browserRedo.rawValue:
                let manager = editingUndoManager(redo: true)
                item.title = manager.redoMenuItemTitle
                item.isEnabled = manager.canRedo

            default:
                break
            }
        }
    }
}

extension MenuBarManager: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if let isEnabled = validatePaneMenuItem(menuItem) {
            return isEnabled
        }
        return switch menuItem.tag {
        case MenuItemTag.browserUndo.rawValue: editingUndoManager(redo: false).canUndo
        case MenuItemTag.browserRedo.rawValue: editingUndoManager(redo: true).canRedo
        default: true
        }
    }
}
