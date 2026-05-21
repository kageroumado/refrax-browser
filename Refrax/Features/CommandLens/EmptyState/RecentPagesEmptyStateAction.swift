import Foundation

/// Shows a hybrid list of recently viewed and recently closed tabs when left arrow is pressed.
///
/// This action provides quick access to recent browsing context by combining:
/// - Open tabs sorted by `lastAccessed` (most recent first)
/// - Recently closed tabs from `UndoRedoManager`
///
/// Users can switch to an open tab or reopen a closed one, making this
/// the fastest way to return to recently viewed content.
struct RecentPagesEmptyStateAction: CommandLensEmptyStateAction {
    let direction = EmptyStateDirection.left
    let icon = "clock.arrow.circlepath"
    let label = "Recent Pages"

    func isAvailable(context: EmptyStateContext) -> Bool {
        // Available if there are any tabs or recently closed tabs
        let hasTabs = context.windowState.activeSpace?.tabs.isEmpty == false
        let hasRecentlyClosed = !context.undoRedoManager.recentlyClosedTabs.isEmpty
        return hasTabs || hasRecentlyClosed
    }

    func execute(context: EmptyStateContext) async -> EmptyStateResult {
        var suggestions: [CommandLensSuggestion] = []

        // Get open tabs sorted by lastAccessed (most recent first, never-accessed last)
        if let tabs = context.windowState.activeSpace?.tabs {
            let sortedTabs = tabs.sorted { lhs, rhs in
                switch (lhs.lastAccessed, rhs.lastAccessed) {
                case (nil, nil): false
                case (nil, _): false // never-accessed sorts last
                case (_, nil): true
                case let (l?, r?): l > r
                }
            }

            let openTabSuggestions = sortedTabs.enumerated().map { index, tab -> CommandLensSuggestion in
                let timeLabel = tab.lastAccessed.map(relativeTimeString) ?? ""
                let type: SuggestionType = tab.isReferenceTab
                    ? .referenceTab(tabID: tab.id)
                    : .openTab(tabID: tab.id)
                let iconName = if tab.isReferenceTab {
                    "sidebar.squares.right"
                } else if tab.status == .pinned {
                    "pin.fill"
                } else {
                    "rectangle.on.rectangle"
                }
                return CommandLensSuggestion(
                    type: type,
                    text: tab.customName ?? tab.pages.map(\.title).joined(separator: " | "),
                    description: tab.displayURL + (timeLabel.isEmpty ? "" : " • \(timeLabel)"),
                    iconName: iconName,
                    groupHeader: index == 0 ? "Recently Viewed" : nil,
                    isRemovable: false,
                    keywordAction: nil,
                    url: nil,
                )
            }
            suggestions.append(contentsOf: openTabSuggestions)
        }

        // Get recently closed tabs
        let recentlyClosed = context.undoRedoManager.recentlyClosedTabs
        if !recentlyClosed.isEmpty {
            let closedSuggestions = recentlyClosed.enumerated().map { index, tabInfo -> CommandLensSuggestion in
                let timeLabel = relativeTimeString(from: tabInfo.closedAt)
                return CommandLensSuggestion(
                    type: .recentlyClosed(index: index),
                    text: tabInfo.customName ?? tabInfo.title,
                    description: tabInfo.url.absoluteString + (timeLabel.isEmpty ? "" : " • \(timeLabel)"),
                    iconName: tabInfo.isReferenceTab ? "sidebar.squares.right" : "arrow.uturn.backward",
                    groupHeader: index == 0 ? "Recently Closed" : nil,
                    isRemovable: false,
                    keywordAction: nil,
                    url: tabInfo.url,
                )
            }
            suggestions.append(contentsOf: closedSuggestions)
        }

        return suggestions.isEmpty ? .none : .showSuggestions(suggestions)
    }

    // MARK: - Private Helpers

    /// Creates a human-readable relative time string.
    ///
    /// - Parameter date: The date to format.
    /// - Returns: A string like "NOW", "2m", "1h", or "3d" for recent times.
    private func relativeTimeString(from date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)

        if elapsed < 60 {
            return "NOW"
        } else if elapsed < 3_600 {
            let minutes = Int(elapsed / 60)
            return "\(minutes)m"
        } else if elapsed < 86_400 {
            let hours = Int(elapsed / 3_600)
            return "\(hours)h"
        } else {
            let days = Int(elapsed / 86_400)
            return "\(days)d"
        }
    }
}
