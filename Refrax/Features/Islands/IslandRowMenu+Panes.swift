import Foundation

extension IslandRowMenu {
    /// A split tab's row edits or separates its panes; a lone page's row can join the current
    /// page beside it.
    func paneActions() -> [MenuAction] {
        let tab = tab
        let windowState = windowState
        let tabs = tabs
        let islands = islands
        if tab.pages.count > 1 {
            return [
                MenuAction("panes.edit", PaneCommand.edit.title, symbol: PaneCommand.edit.symbol, group: .table) {
                    if windowState.activeTabID != tab.id {
                        tabs.setActiveTab(tab, in: windowState)
                    }
                    windowState.enterLayoutMode()
                },
                MenuAction("panes.separate", PaneCommand.separate.title, symbol: PaneCommand.separate.symbol, group: .table) {
                    windowState.exitLayoutMode(animated: false)
                    tabs.separatePanes(of: tab)
                },
            ]
        }
        guard let current = islands.currentTab, islands.canJoin(tab.id, with: current.id) else { return [] }
        let sides = PaneEdge.allCases.map { edge in
            let command = PaneCommand.openBeside(edge)
            let title = switch edge {
            case .leading: "On the Left"
            case .trailing: "On the Right"
            case .top: "Above"
            case .bottom: "Below"
            }
            return MenuAction("panes.beside.\(edge.rawValue)", title, symbol: command.symbol, group: .table) {
                islands.joinPage(tab.id, at: PaneCommand.placement(beside: edge, in: windowState))
            }
        }
        return [MenuAction("panes.beside", "Show Beside This Page", symbol: "rectangle.split.2x1", group: .table, children: sides)]
    }
}
