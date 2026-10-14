import Foundation

extension ActionsProvider {
    /// The table's moves and slab shapes for the current page, and "Go to Row …".
    func tableSuggestions(
        for query: String,
        matching matches: ([String]) -> Bool,
        suggestion: (AppAction, String, String, String) -> CommandLensSuggestion,
    ) -> [CommandLensSuggestion] {
        guard let table = windowState?.tableController, let tab = table.currentTab else { return [] }
        var results: [CommandLensSuggestion] = []
        let moves: [([String], TableCommand, String, String, String)] = [
            (["focus slab left", "slab left", "table left", "previous slab"], .focus(.left), "Focus Slab Left", "Table  ⌃⌘←", "arrow.left"),
            (["focus slab right", "slab right", "table right", "next slab"], .focus(.right), "Focus Slab Right", "Table  ⌃⌘→", "arrow.right"),
            (["row up", "previous row", "table up"], .focus(.up), "Row Up", "Table  ⌃⌘↑", "arrow.up"),
            (["row down", "next row", "table down"], .focus(.down), "Row Down", "Table  ⌃⌘↓", "arrow.down"),
            (["move slab left", "move tab left"], .moveSlab(.left), "Move Slab Left", "Table  ⌃⌘⇧←", "arrow.left.square"),
            (["move slab right", "move tab right"], .moveSlab(.right), "Move Slab Right", "Table  ⌃⌘⇧→", "arrow.right.square"),
            (["move slab up", "move tab up"], .moveSlab(.up), "Move Slab Up", "Table  ⌃⌘⇧↑", "arrow.up.square"),
            (["move slab down", "move tab down"], .moveSlab(.down), "Move Slab Down", "Table  ⌃⌘⇧↓", "arrow.down.square"),
            (["cycle width", "slab width", "resize slab"], .cycleWidth, "Cycle Width", "Current slab  ⌃⌘R", "arrow.left.and.right"),
            (["fill width", "maximize slab", "full width"], .toggleFill, "Fill Width", "Current slab  ⌃⌘⇧F", "arrow.up.left.and.arrow.down.right"),
        ]
        for (terms, command, title, description, symbol) in moves where matches(terms) {
            results.append(suggestion(.table(command), title, description, symbol))
        }
        let widthTerms: [TableWidth: [String]] = [
            .third: ["third width", "one third", "width third"],
            .half: ["half width", "split view", "width half", "side by side"],
            .twoThirds: ["two thirds width", "width two thirds"],
            .full: ["full width", "width full"],
        ]
        for width in TableWidth.allCases where width != table.width(of: tab) && matches(widthTerms[width] ?? []) {
            results.append(suggestion(.table(.setWidth(width)), "Width \(width.title)", "Current slab", "arrow.left.and.right"))
        }
        if table.canMoveToNewRow(tab), matches(["move to new row", "new row", "own row"]) {
            results.append(suggestion(.table(.moveToNewRow), "Move to New Row", "Current slab", "rectangle.split.1x2"))
        }
        if let number = TableCommand.rowNumber(in: query), number >= 1, number <= table.rowCount {
            results.append(suggestion(.table(.goToRow(number - 1)), "Go to Row \(number)", "Table", "arrow.down.to.line"))
        }
        return results
    }
}
