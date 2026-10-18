import AppKit
import Foundation

extension TabActions {
    /// New Island from Here, for a tab on one of this window's islands.
    func tableActions() -> [MenuAction] {
        guard let islands = windowState.islandController, islands.holds(tab) else { return [] }
        return [
            MenuAction("tab.island.new", "New Island from Here", symbol: "plus.rectangle.on.rectangle", group: .table) {
                islands.makeIsland(from: tab.id)
            },
        ]
    }
}
