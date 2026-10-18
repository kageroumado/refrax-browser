import Foundation

extension ActionsProvider {
    /// The islands' moves for the current page.
    func tableSuggestions(
        for _: String,
        matching matches: ([String]) -> Bool,
        suggestion: (AppAction, String, String, String) -> CommandLensSuggestion,
    ) -> [CommandLensSuggestion] {
        guard let islands = windowState?.islandController, islands.currentTab != nil else { return [] }
        var results: [CommandLensSuggestion] = []
        let moves: [([String], TableCommand, String, String, String)] = [
            (["tab left", "previous tab", "focus tab left", "chip left"], .focus(.left), "Tab Left", "Islands  ⌃⌘←", "arrow.left"),
            (["tab right", "next tab", "focus tab right", "chip right"], .focus(.right), "Tab Right", "Islands  ⌃⌘→", "arrow.right"),
            (["tab above", "tab up", "parent tab"], .focus(.up), "Tab Above", "Islands  ⌃⌘↑", "arrow.up"),
            (["tab below", "tab down", "child tab"], .focus(.down), "Tab Below", "Islands  ⌃⌘↓", "arrow.down"),
            (["new island", "island", "move to new island", "split island"], .newIsland, "New Island from Here", "Islands  ⌃⌘I", "plus.rectangle.on.rectangle"),
        ]
        for (terms, command, title, description, symbol) in moves where matches(terms) {
            results.append(suggestion(.table(command), title, description, symbol))
        }
        return results
    }
}
