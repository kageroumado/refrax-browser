import AppKit
import Foundation

extension TabActions {
    /// Tab Width ▸ (⅓ ½ ⅔ Full) and Start a Row Below, for a tab on this window's table.
    func tableActions() -> [MenuAction] {
        guard let table = windowState.tableController, table.holds(tab), let current = table.width(of: tab) else { return [] }
        let widths = TableWidth.allCases.map { width in
            MenuAction("tab.table.width.\(width.rawValue)", width.title, group: .table, state: width == current ? .on : .off) {
                table.setWidth(width, of: tab)
            }
        }
        return [
            MenuAction("tab.table.width", "Tab Width", symbol: "arrow.left.and.right", group: .table, children: widths),
            MenuAction("tab.table.newRow", "Start a Row Below", symbol: "rectangle.split.1x2", group: .table, isEnabled: table.canMoveToNewRow(tab)) {
                table.moveToNewRow(tab)
            },
        ]
    }
}

extension TableWidth {
    /// The preset as menus and the lens name it.
    var title: String {
        switch self {
        case .third: "⅓"
        case .half: "½"
        case .twoThirds: "⅔"
        case .full: "Full"
        }
    }
}
