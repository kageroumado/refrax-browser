import Foundation

/// Shows recently closed tabs when up arrow is pressed with empty input.
///
/// This action allows users to quickly reopen tabs they've recently closed.
/// The recently closed list is maintained by the UndoRedoManager.
struct RecentlyClosedEmptyStateAction: CommandLensEmptyStateAction {
    let direction = EmptyStateDirection.up
    let icon = "arrow.uturn.backward"
    let label = "Recently Closed"

    func isAvailable(context: EmptyStateContext) -> Bool {
        !context.undoRedoManager.recentlyClosedTabs.isEmpty
    }

    func execute(context: EmptyStateContext) async -> EmptyStateResult {
        let recentlyClosed = context.undoRedoManager.recentlyClosedTabs

        guard !recentlyClosed.isEmpty else {
            return .none
        }

        let suggestions = recentlyClosed.enumerated().map { index, tabInfo in
            CommandLensSuggestion(
                type: .recentlyClosed(index: index),
                text: tabInfo.title,
                description: tabInfo.url.absoluteString,
                iconName: tabInfo.isReferenceTab ? "sidebar.squares.right" : "arrow.uturn.backward",
                groupHeader: "Recently Closed",
                isRemovable: false,
                keywordAction: nil,
                url: tabInfo.url,
            )
        }

        return .showSuggestions(suggestions)
    }
}
