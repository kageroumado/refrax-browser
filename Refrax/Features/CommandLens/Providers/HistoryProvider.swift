import Foundation

/// Provides suggestions from the user's browsing history.
///
/// This provider searches through history entries matching the user's
/// query by title or URL. History suggestions are removable, allowing
/// users to delete entries they don't want suggested.
struct HistoryProvider: CommandLensSuggestionProvider {
    let id = "history"
    let priority = 150
    let groupHeader: String? = "History"
    let maxSuggestions = 10

    private let historyManager: HistoryManager

    init(historyManager: HistoryManager) {
        self.historyManager = historyManager
    }

    func shouldProvide(for context: SuggestionContext) -> Bool {
        !context.isEmptyInput
    }

    func suggestions(for context: SuggestionContext) async -> [CommandLensSuggestion] {
        let entries = await historyManager.search(query: context.input, limit: maxSuggestions)

        return entries.map { entry in
            CommandLensSuggestion(
                type: .url,
                text: entry.title ?? entry.url.absoluteString,
                description: entry.url.absoluteString,
                iconName: "clock",
                groupHeader: groupHeader,
                isRemovable: true,
                keywordAction: nil,
                url: entry.url,
            )
        }
    }
}
