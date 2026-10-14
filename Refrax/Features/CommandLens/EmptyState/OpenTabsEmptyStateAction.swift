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

        return .showSuggestions(Self.suggestions(for: tabs))
    }

    /// One row per tab, under a header that counts them: "3 Open Tabs".
    static func suggestions(for tabs: [Tab]) -> [CommandLensSuggestion] {
        let header = "\(tabs.count) Open \(tabs.count == 1 ? "Tab" : "Tabs")"
        return tabs.map { tab in
            CommandLensSuggestion(
                type: .openTab(tabID: tab.id),
                text: tab.customName ?? tab.pages.map(\.title).joined(separator: " | "),
                description: tab.displayURL,
                iconName: "rectangle.on.rectangle",
                groupHeader: header,
                isRemovable: false,
                keywordAction: nil,
                url: nil,
            )
        }
    }
}
