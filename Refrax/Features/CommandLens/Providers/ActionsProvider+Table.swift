import Foundation

extension ActionsProvider {
    /// The tab layout's moves and widths for the current page, and "Go to Row …".
    func tableSuggestions(
        for query: String,
        matching matches: ([String]) -> Bool,
        suggestion: (AppAction, String, String, String) -> CommandLensSuggestion,
    ) -> [CommandLensSuggestion] {
        guard let table = windowState?.tableController, let tab = table.currentTab else { return [] }
        var results: [CommandLensSuggestion] = []
        let moves: [([String], TableCommand, String, String, String)] = [
            (["focus tab left", "tab left", "previous tab", "slab left", "table left"], .focus(.left), "Focus Tab Left", "Tab layout  ⌃⌘←", "arrow.left"),
            (["focus tab right", "tab right", "next tab", "slab right", "table right"], .focus(.right), "Focus Tab Right", "Tab layout  ⌃⌘→", "arrow.right"),
            (["tab above", "focus tab above", "row up", "previous row"], .focus(.up), "Tab Above", "Tab layout  ⌃⌘↑", "arrow.up"),
            (["tab below", "focus tab below", "row down", "next row"], .focus(.down), "Tab Below", "Tab layout  ⌃⌘↓", "arrow.down"),
            (["move tab left", "move slab left"], .moveSlab(.left), "Move Tab Left", "Tab layout  ⌃⌘⇧←", "arrow.left.square"),
            (["move tab right", "move slab right"], .moveSlab(.right), "Move Tab Right", "Tab layout  ⌃⌘⇧→", "arrow.right.square"),
            (["move tab up", "move slab up"], .moveSlab(.up), "Move Tab Up", "Tab layout  ⌃⌘⇧↑", "arrow.up.square"),
            (["move tab down", "move slab down"], .moveSlab(.down), "Move Tab Down", "Tab layout  ⌃⌘⇧↓", "arrow.down.square"),
            (["cycle width", "tab width", "resize tab", "slab width"], .cycleWidth, "Cycle Tab Width", "Current tab  ⌃⌘R", "arrow.left.and.right"),
            (["fill width", "maximize tab", "full width"], .toggleFill, "Fill Width", "Current tab  ⌃⌘⇧F", "arrow.up.left.and.arrow.down.right"),
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
            results.append(suggestion(.table(.setWidth(width)), "Tab Width \(width.title)", "Current tab", "arrow.left.and.right"))
        }
        if table.canMoveToNewRow(tab), matches(["start a row below", "new row", "own row", "move to new row"]) {
            results.append(suggestion(.table(.moveToNewRow), "Start a Row Below", "Current tab", "rectangle.split.1x2"))
        }
        if let number = TableCommand.rowNumber(in: query), number >= 1, number <= table.rowCount {
            results.append(suggestion(.table(.goToRow(number - 1)), "Go to Row \(number)", "Tab layout", "arrow.down.to.line"))
        }
        return results
    }
}
