import AppKit
import Foundation

extension TabActions {
    /// New Island with This Tab, for a tab on one of this window's islands.
    func tableActions() -> [MenuAction] {
        guard let islands = windowState.islandController, islands.holds(tab) else { return [] }
        return [
            MenuAction("tab.island.new", "New Island with This Tab", symbol: "plus.rectangle.on.rectangle", group: .table) {
                islands.makeIsland(from: tab.id)
            },
        ]
    }
}
