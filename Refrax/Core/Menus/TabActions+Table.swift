import AppKit
import Foundation

extension TabActions {
    /// New Island with This Tab, for a tab on one of this window's islands. In its own group,
    /// ``MenuGroupID/island``, so every tab menu shows it near the top, under the page's
    /// essentials, where a person who never opens the View menu still finds islands.
    func tableActions() -> [MenuAction] {
        guard let islands = windowState.islandController, islands.holds(tab) else { return [] }
        return [
            MenuAction("tab.island.new", "New Island with This Tab", symbol: "plus.rectangle.on.rectangle", group: .island) {
                islands.makeIsland(from: tab.id)
            },
        ]
    }
}
