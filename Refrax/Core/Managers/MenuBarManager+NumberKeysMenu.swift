import AppKit

/// The number keys: ⌃1…9 show the space at that place in the spaces' order, and ⌘1…9 open
/// the favorite at that place in the favorites' order.
nonisolated enum NumberKey {
    static let count = 9

    /// "⌃3" for the third space; `nil` past the ninth.
    static func space(at index: Int) -> String? {
        (0 ..< count).contains(index) ? "⌃\(index + 1)" : nil
    }

    /// "⌘3" for the third favorite; `nil` past the ninth.
    static func favorite(at index: Int) -> String? {
        (0 ..< count).contains(index) ? "⌘\(index + 1)" : nil
    }
}

// MARK: - View ▸ Go to Space, View ▸ Go to Favorite

extension MenuBarManager {
    private enum NumberKeyMenu {
        static let spaces = NSUserInterfaceItemIdentifier("view.goToSpace")
        static let favorites = NSUserInterfaceItemIdentifier("view.goToFavorite")
    }

    /// View ▸ Go to Space: nine items on ⌃1…9. Each item carries its place; its title is the
    /// space's name once the menu updates.
    func createGoToSpaceMenuItem() -> NSMenuItem {
        numberKeyMenuItem(
            title: "Go to Space", symbol: ControlIslandItem.spaces.symbol, identifier: NumberKeyMenu.spaces,
            placeholder: "Space", modifiers: [.control], action: #selector(goToSpace(_:)),
        )
    }

    /// View ▸ Go to Favorite: nine items on ⌘1…9, titled by the favorites once the menu updates.
    func createGoToFavoriteMenuItem() -> NSMenuItem {
        numberKeyMenuItem(
            title: "Go to Favorite", symbol: ControlIslandItem.favorites.symbol, identifier: NumberKeyMenu.favorites,
            placeholder: "Favorite", modifiers: [.command], action: #selector(goToFavorite(_:)),
        )
    }

    private func numberKeyMenuItem(
        title: String, symbol: String, identifier: NSUserInterfaceItemIdentifier, placeholder: String,
        modifiers: NSEvent.ModifierFlags, action: Selector,
    ) -> NSMenuItem {
        let menu = NSMenu(title: title)
        menu.identifier = identifier
        menu.delegate = self
        for index in 0 ..< NumberKey.count {
            let item = NSMenuItem(title: "\(placeholder) \(index + 1)", action: action, keyEquivalent: "\(index + 1)")
            item.keyEquivalentModifierMask = modifiers
            item.representedObject = index
            item.target = self
            menu.addItem(item)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.submenu = menu
        return item
    }

    /// Names each item after the space or favorite at its place, and hides the places past the
    /// end of the list, so their keys go to the page.
    func updateNumberKeyMenus(_ menu: NSMenu) {
        let titles: [String]
        switch menu.identifier {
        case NumberKeyMenu.spaces:
            titles = activeWindowController?.tabManager.spaceManager.spaces.map(\.name) ?? []
        case NumberKeyMenu.favorites:
            titles = activeWindowController?.favoritesByNumber.map(\.displayName) ?? []
        default:
            return
        }
        for (index, item) in menu.items.enumerated() {
            item.isHidden = index >= titles.count
            if index < titles.count {
                item.title = titles[index]
            }
        }
    }

    @objc
    private func goToSpace(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        activeWindowController?.showSpace(at: index)
    }

    @objc
    private func goToFavorite(_ sender: NSMenuItem) {
        guard let index = sender.representedObject as? Int else { return }
        activeWindowController?.openFavorite(at: index)
    }
}
