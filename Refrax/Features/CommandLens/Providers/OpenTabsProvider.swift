import Foundation

/// Provides suggestions for switching to already-open tabs.
///
/// This provider searches through the user's open tabs (including main tabs,
/// reference tabs, and live favorites) and suggests matches based on tab title,
/// custom name, or URL.
///
/// ## Tab Categories
///
/// Tabs are categorized and displayed with different icons:
/// - **Main tabs**: Regular tabs in the sidebar (`rectangle.on.rectangle`)
/// - **Reference tabs**: Tabs in the reference pane (`sidebar.squares.right`)
/// - **Live favorites**: Persistent favorites grid tabs (`star.fill`)
struct OpenTabsProvider: CommandLensSuggestionProvider {
    let id = "open-tabs"
    let priority = 50
    let groupHeader: String? = "Open Tabs"
    let maxSuggestions = 5

    private let tabManager: TabManager

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    func shouldProvide(for context: SuggestionContext) -> Bool {
        !context.isEmptyInput
    }

    func suggestions(for context: SuggestionContext) async -> [CommandLensSuggestion] {
        var suggestions: [CommandLensSuggestion] = []
        let query = context.input.lowercased()

        // Search main tabs (non-reference) from current space
        let matchingMainTabs = tabManager.tabs(matching: context.input)
            .filter { !$0.isReferenceTab }

        for tab in matchingMainTabs.prefix(maxSuggestions) {
            suggestions.append(makeSuggestion(for: tab, category: .main))
        }

        // Search reference tabs from current space
        if let space = tabManager.activeWindowState?.activeSpace {
            let matchingRefTabs = space.referenceTabs.filter { matchesQuery($0, query: query) }

            for tab in matchingRefTabs.prefix(maxSuggestions - suggestions.count) {
                suggestions.append(makeSuggestion(for: tab, category: .reference))
            }
        }

        // Search live favorite tabs
        let matchingLiveFavorites = tabManager.state.liveFavoriteTabs
            .filter { matchesQuery($0, query: query) }

        for tab in matchingLiveFavorites.prefix(maxSuggestions - suggestions.count) {
            suggestions.append(makeSuggestion(for: tab, category: .liveFavorite))
        }

        return Array(suggestions.prefix(maxSuggestions))
    }

    // MARK: - Private Helpers

    private enum TabCategory {
        case main
        case reference
        case liveFavorite
    }

    private func matchesQuery(_ tab: Tab, query: String) -> Bool {
        tab.activePage.title.localizedCaseInsensitiveContains(query) ||
            tab.displayURL.localizedCaseInsensitiveContains(query) ||
            (tab.customName?.localizedCaseInsensitiveContains(query) ?? false)
    }

    private func makeSuggestion(for tab: Tab, category: TabCategory) -> CommandLensSuggestion {
        let (type, iconName, header): (SuggestionType, String, String?) = switch category {
        case .main:
            (.openTab(tabID: tab.id), "rectangle.on.rectangle", groupHeader)
        case .reference:
            (.referenceTab(tabID: tab.id), "sidebar.squares.right", "Reference Pane")
        case .liveFavorite:
            (.openTab(tabID: tab.id), "star.fill", "Favorites")
        }

        return CommandLensSuggestion(
            type: type,
            text: tab.customName ?? tab.pages.map(\.title).joined(separator: " | "),
            description: tab.displayURL,
            iconName: iconName,
            groupHeader: header,
            isRemovable: false,
            keywordAction: nil,
            url: nil,
        )
    }
}
