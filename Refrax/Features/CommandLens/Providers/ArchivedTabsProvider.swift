import Foundation

/// Provides archived tabs to restore, for input that starts with "archived".
///
/// "archived" lists the most recently archived tabs in every space; "archived:" or "archived "
/// followed by text narrows them to tabs whose title, name, or address contains it. Choosing
/// one restores it to its space and opens it.
struct ArchivedTabsProvider: CommandLensSuggestionProvider {
    let id = "archived-tabs"
    let priority = 55
    let groupHeader: String? = "Archived Tabs"
    let maxSuggestions = 8

    private let tabManager: TabManager

    /// The word that asks for archived tabs.
    nonisolated static let keyword = "archived"

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    func shouldProvide(for context: SuggestionContext) -> Bool {
        Self.query(in: context.input) != nil
    }

    func suggestions(for context: SuggestionContext) async -> [CommandLensSuggestion] {
        guard let query = Self.query(in: context.input) else { return [] }
        let archived = tabManager.state.spaces
            .flatMap { $0.tabs.filter(\.isArchived) }
            .filter { query.isEmpty || matches($0, query: query) }
            .sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }

        return archived.prefix(maxSuggestions).map { tab in
            CommandLensSuggestion(
                type: .archivedTab(tabID: tab.id),
                text: tab.customName ?? tab.displayTitle,
                description: tab.displayURL,
                iconName: "archivebox",
                groupHeader: groupHeader,
                isRemovable: false,
                keywordAction: nil,
                url: nil,
            )
        }
    }

    /// The text after the keyword, empty for the keyword alone, or `nil` when the input does not
    /// start with it.
    nonisolated static func query(in input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix(keyword) else { return nil }
        let rest = trimmed.dropFirst(keyword.count)
        guard rest.isEmpty || rest.first == ":" || rest.first == " " else { return nil }
        return rest.drop { $0 == ":" || $0 == " " }.trimmingCharacters(in: .whitespaces)
    }

    private func matches(_ tab: Tab, query: String) -> Bool {
        tab.activePage.title.localizedCaseInsensitiveContains(query)
            || tab.displayURL.localizedCaseInsensitiveContains(query)
            || (tab.customName?.localizedCaseInsensitiveContains(query) ?? false)
    }
}
