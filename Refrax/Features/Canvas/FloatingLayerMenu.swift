import AppKit

/// The floating layer's right-click menus: a card's own actions on the card, and the layer's
/// Arrange ▸ and Select All on its empty area while it is revealed.
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

    /// Shows a card's own menu, the same actions as its ⋯, for a right-click on the card's
    /// handle: all of an icon or a tab, the header of a live page or a docked column. A
    /// right-click on a live page's content stays the page's. Returns whether the click was a card's.
    func showFloatingCardMenu(
        at point: CGPoint,
        for event: NSEvent,
        in view: NSView,
        bookmarks: BookmarksManager,
        sharing: SharingCoordinator,
    ) -> Bool {
        guard let tab = floatingCardHandle(at: point, in: view.bounds) else { return false }
        let tree = PageActionsMenu.tree(
            for: tab, surface: .floatingCard, area: view.bounds, windowState: windowState, tabs: tabManager,
            bookmarks: bookmarks, canvas: self, sharing: sharing,
        )
        let info = windowState.controlIsland.tabInfo
        beginFloatingManipulation()
        menuTabID = tab.id
        info.isMenuPresented = true
        MenuPresenter().present(tree, at: view.convert(event.locationInWindow, from: nil), in: view)
        info.isMenuPresented = false
        menuTabID = nil
        endFloatingManipulation()
        return true
    }

    /// The card whose handle is under `point`: the topmost card drawn there, then a docked column's header.
    private func floatingCardHandle(at point: CGPoint, in bounds: CGRect) -> Tab? {
        if let tab = visibleFloatingTabs.last(where: { floatingFrame(for: $0, in: bounds).contains(point) }) {
            let frame = floatingFrame(for: tab, in: bounds)
            let showsPage = floatingPlacement(for: tab).shape == .live && tab.id != windowState.activeTabID
            return !showsPage || point.y <= frame.minY + FloatingTabPlacement.headerHeight ? tab : nil
        }
        let columns = dockColumns(in: bounds)
        for edge in FloatingDockEdge.allCases {
            if let column = columns[edge], column.contains(point), point.y <= column.minY + FloatingTabPlacement.headerHeight {
                return dockedTab(on: edge)
            }
        }
        return nil
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
