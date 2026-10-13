import Foundation

/// Shows all currently open tabs when down arrow is pressed with empty input.
///
/// This action allows users to quickly browse and switch between their
/// open tabs without typing a search query.
struct OpenTabsEmptyStateAction: CommandLensEmptyStateAction {
    let direction = EmptyStateDirection.down
    let icon = "rectangle.on.rectangle"
    let label = "Open Tabs"

    func isAvailable(context: EmptyStateContext) -> Bool {
        guard let tabs = context.windowState.activeSpace?.tabs else {
            return false
        }
        return !tabs.isEmpty
    }

    func execute(context: EmptyStateContext) async -> EmptyStateResult {
        guard let tabs = context.windowState.activeSpace?.tabs, !tabs.isEmpty else {
            return .none
        }

        let suggestions: [CommandLensSuggestion] = tabs.map { tab in
            CommandLensSuggestion(
                type: .openTab(tabID: tab.id),
                text: tab.customName ?? tab.pages.map(\.title).joined(separator: " | "),
                description: tab.displayURL,
                iconName: "rectangle.on.rectangle",
                groupHeader: "Open Tabs",
                isRemovable: false,
                keywordAction: nil,
                url: nil,
            )
        }

        return .showSuggestions(suggestions)
    }
}
