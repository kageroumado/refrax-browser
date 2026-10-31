import Foundation

extension ActionsProvider {
    /// The current tab's panes: edit them, open a page beside the focused one, separate them.
    func paneSuggestions(
        matching matches: ([String]) -> Bool,
        suggestion: (AppAction, String, String, String) -> CommandLensSuggestion,
    ) -> [CommandLensSuggestion] {
        guard let windowState, windowState.activeTab != nil else { return [] }
        let commands: [([String], PaneCommand, String)] = [
            (["split view", "edit split view", "layout", "panes", "edit panes", "arrange panes", "grid"], .edit, "Lift the panes apart to move and resize them  ⌃⌘T"),
            (["done", "done editing", "finish split view", "leave layout mode"], .finishEditing, "Lay the panes back on the page"),
            (["split left", "open on the left", "open left", "beside left"], .openBeside(.leading), "A new page beside this one"),
            (["split right", "open on the right", "open right", "open beside", "side by side"], .openBeside(.trailing), "A new page beside this one"),
            (["split up", "open above", "split top"], .openBeside(.top), "A new page beside this one"),
            (["split down", "open below", "split bottom"], .openBeside(.bottom), "A new page beside this one"),
            (["separate panes", "unsplit", "split into tabs", "separate tabs"], .separate, "Every pane its own tab, in this island"),
        ]
        return commands
            .filter { matches($0.0) && PaneCommand.isAvailable($0.1, in: windowState) }
            .map { suggestion(.panes($0.1), $0.1.title, $0.2, $0.1.symbol) }
    }
}
