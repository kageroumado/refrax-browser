import AppKit

/// Renders a ``MenuTree`` as an `NSMenu`: one item per row, a separator between sections, a
/// submenu per folded group or child list.
enum NSMenuRenderer {
    static func menu(_ tree: MenuTree, title: String = "") -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        for (index, section) in tree.sections.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for node in section.nodes { menu.addItem(item(node)) }
        }
        return menu
    }

    static func item(_ node: MenuTree.Node) -> NSMenuItem {
        switch node {
        case let .submenu(submenu):
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.image = submenu.symbol.flatMap(symbolImage)
            item.submenu = menu(MenuTree(sections: submenu.sections), title: submenu.title)
            item.setAccessibilityIdentifier("menu-\(submenu.id)")
            return item
        case let .action(action):
            let target = MenuActionTarget(action.execute)
            let item = NSMenuItem(title: action.title, action: #selector(MenuActionTarget.performAction(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = target
            item.image = action.symbol.flatMap(symbolImage)
            item.isEnabled = action.isEnabled
            if let key = action.keyEquivalent {
                item.keyEquivalent = String(key.character)
                item.keyEquivalentModifierMask = key.modifiers
            }
            switch action.state {
            case .plain: break
            case .on: item.state = .on
            case .off: item.state = .off
            }
            item.setAccessibilityIdentifier("menu-\(action.id)")
            return item
        }
    }

    private static func symbolImage(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    }
}

/// Runs a menu action's closure when its item is chosen.
///
/// `NSMenuItem.target` is weak, so the renderer also stores the target in the item's
/// `representedObject`; that reference is what keeps the closure alive for the menu's lifetime.
final nonisolated class MenuActionTarget: NSObject, Sendable {
    let execute: @MainActor () -> Void

    init(_ execute: @escaping @MainActor () -> Void) {
        self.execute = execute
        super.init()
    }

    @objc
    func performAction(_: Any?) {
        MainActor.assumeIsolated { execute() }
    }
}
