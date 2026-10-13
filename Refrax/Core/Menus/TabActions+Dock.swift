import AppKit
import Foundation

extension TabActions {
    /// ⌃⌥← and ⌃⌥→, the View menu's Dock Current Page Left and Right.
    static func dockKey(_ edge: FloatingDockEdge) -> MenuAction.KeyEquivalent {
        let arrow = edge == .leading ? NSLeftArrowFunctionKey : NSRightArrowFunctionKey
        return MenuAction.KeyEquivalent(Character(UnicodeScalar(UInt32(arrow))!), modifiers: [.control, .option])
    }

    /// Dock Left and Dock Right for each side the tab is not on, and Undock while it is docked.
    func dockActions(canvas: TabCanvasManager) -> [MenuAction] {
        guard windowState.usesFloatingTabs else { return [] }
        let dock = canvas.storedFloatingPlacement(for: tab)?.dock
        let isCurrentPage = tab.id == windowState.activeTabID
        var actions = FloatingDockEdge.allCases.filter { $0 != dock }.map { edge in
            MenuAction(
                "tab.dock.\(edge.rawValue)", "Dock \(edge.title)",
                symbol: edge == .leading ? "rectangle.lefthalf.inset.filled" : "rectangle.righthalf.inset.filled",
                key: isCurrentPage ? Self.dockKey(edge) : nil, group: .preview,
            ) { canvas.dock(tab, to: edge) }
        }
        if dock != nil {
            actions.append(MenuAction("tab.undock", "Undock", symbol: "arrow.uturn.backward", group: .preview) {
                canvas.undock(tab)
            })
        }
        return actions
    }
}
