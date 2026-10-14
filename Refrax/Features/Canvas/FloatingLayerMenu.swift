import AppKit

/// The floating layer's own menu, on a right-click of its empty area while it is revealed:
/// Arrange ▸ and Select All.
extension TabCanvasManager {
    /// Shows the layer's menu for a right-click at `point` on empty layer area, keeping the layer
    /// up while it is open. Returns whether the click was the layer's.
    func showFloatingLayerMenu(at point: CGPoint, for event: NSEvent, in view: NSView) -> Bool {
        guard floatingVisibility.isRevealed,
              !floatingHitRegions(in: view.bounds).contains(where: { $0.contains(point) }) else { return false }
        beginFloatingManipulation()
        NSMenu.popUpContextMenu(floatingLayerMenu(), with: event, for: view)
        endFloatingManipulation()
        return true
    }

    private func floatingLayerMenu() -> NSMenu {
        let arrangeMenu = NSMenu(title: "Arrange")
        for arrangement in FloatingArrangement.allCases {
            let item = floatingLayerMenuItem(arrangement.title, symbol: arrangement.symbol) { [weak self] in
                guard let self else { return }
                if arrangement == .stacksBySite, stacksBySite {
                    stopStackingBySite()
                } else {
                    arrange(arrangement)
                }
            }
            item.state = arrangement == .stacksBySite && stacksBySite ? .on : .off
            arrangeMenu.addItem(item)
        }
        let menu = NSMenu()
        let arrangeItem = NSMenuItem(title: "Arrange", action: nil, keyEquivalent: "")
        arrangeItem.image = NSImage(systemSymbolName: "square.grid.3x2", accessibilityDescription: nil)
        arrangeItem.submenu = arrangeMenu
        menu.addItem(arrangeItem)
        menu.addItem(floatingLayerMenuItem("Select All", symbol: "checklist") { [weak self] in
            self?.selectAllFloatingTabs()
        })
        return menu
    }
}

/// A menu item that runs a closure, through an action object the item keeps.
private func floatingLayerMenuItem(_ title: String, symbol: String, handler: @escaping () -> Void) -> NSMenuItem {
    let action = FloatingLayerMenuAction(handler)
    let item = NSMenuItem(title: title, action: #selector(FloatingLayerMenuAction.run), keyEquivalent: "")
    item.target = action
    item.representedObject = action
    item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    return item
}

private final class FloatingLayerMenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc
    func run() {
        handler()
    }
}
