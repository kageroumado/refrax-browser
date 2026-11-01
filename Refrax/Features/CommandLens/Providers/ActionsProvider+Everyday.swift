import Foundation

/// The actions people ask for in their own words: copy the address, download or save the
/// page, change the accent color, group tabs, and see how many tabs are open.
extension ActionsProvider {
    /// One action and the everyday words that find it.
    private struct EverydayAction {
        let action: AppAction
        let title: String
        let description: String
        let icon: String
        let terms: [String]
    }

    /// The everyday actions whose words match `query`, the closest match first.
    func everydaySuggestions(for query: String) -> [CommandLensSuggestion] {
        let scored = everydayActions().compactMap { entry -> (score: Double, entry: EverydayAction)? in
            let score = FuzzyMatcher.match(query: query, against: entry.terms)
            return score >= FuzzyMatcher.minimumMatchScore ? (score, entry) : nil
        }
        // A stable sort keeps the listed order among equal scores.
        return scored.enumerated()
            .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
            .map { suggestion(for: $0.element.entry) }
    }

    private func suggestion(for entry: EverydayAction) -> CommandLensSuggestion {
        CommandLensSuggestion(
            type: .appAction(entry.action),
            text: entry.title,
            description: entry.description,
            iconName: entry.icon,
            groupHeader: groupHeader,
            isRemovable: false,
            keywordAction: nil,
            url: nil,
        )
    }

    private func everydayActions() -> [EverydayAction] {
        var actions: [EverydayAction] = []
        let page = windowState?.focusedPage?.tab ?? windowState?.activeTab
        if page != nil {
            actions.append(EverydayAction(
                action: .copyCurrentAddress(asMarkdown: false),
                title: "Copy Address",
                description: "Current page",
                icon: "link",
                terms: ["copy", "copy link", "copy url", "copy address", "copy page address", "address", "link", "url"],
            ))
            actions.append(EverydayAction(
                action: .copyCurrentAddress(asMarkdown: true),
                title: "Copy as Markdown Link",
                description: "Current page",
                icon: "text.quote",
                terms: ["copy markdown", "copy as markdown", "markdown link", "copy markdown link"],
            ))
        }
        if let webPage = windowState?.focusedWebPage {
            if webPage.showsDownloadableFile {
                actions.append(EverydayAction(
                    action: .downloadCurrentPage,
                    title: "Download",
                    description: "Save this file to the download folder",
                    icon: "arrow.down.circle",
                    terms: ["download", "download file", "download pdf", "download image", "save", "save file", "save pdf"],
                ))
            }
            actions.append(EverydayAction(
                action: .saveCurrentPageAs,
                title: "Save Page As…",
                description: "Current page  ⌥⌘S",
                icon: "arrow.up.document",
                terms: ["save", "save as", "save page", "save page as", "download", "download page", "export page", "keep a copy"],
            ))
        }
        actions.append(EverydayAction(
            action: .openSettings(nil),
            title: "Settings",
            description: "Refrax's settings  ⌘,",
            icon: "gearshape",
            terms: ["settings", "preferences", "prefs", "options", "configure", "config", "setup"],
        ))
        actions.append(EverydayAction(
            action: .openSettings(.appearance),
            title: "Appearance Settings",
            description: "Accent color and theme",
            icon: "paintpalette",
            terms: [
                "appearance", "accent", "accent color", "accent colour", "color", "colour", "theme",
                "change color", "change colour", "dark mode", "light mode", "tint",
            ],
        ))
        actions.append(EverydayAction(
            action: .showOpenTabs,
            title: "Show Open Tabs",
            description: openTabsDescription,
            icon: "rectangle.on.rectangle",
            terms: ["tabs", "open tabs", "how many tabs", "how many", "list tabs", "all open tabs", "count tabs", "pages"],
        ))
        // After Show Open Tabs, so a bare "tabs" still lists the open tabs first.
        for (category, terms) in Self.settingsCategoryTerms {
            actions.append(EverydayAction(
                action: .openSettings(category),
                title: "\(category.title) Settings",
                description: "Settings › \(category.title)",
                icon: category.icon,
                terms: terms.map { "\($0) settings" } + terms,
            ))
        }
        return actions
    }

    /// The settings panes a person asks for by name, with the words that find each.
    private static let settingsCategoryTerms: [(SettingsCategory, [String])] = [
        (.general, ["general"]),
        (.tabs, ["tabs", "tab"]),
        (.privacy, ["privacy", "shields", "ad blocker", "adblock", "content blocking", "trackers"]),
        (.search, ["search", "search engine"]),
        (.extensions, ["extensions", "extension", "add-ons", "addons"]),
        (.engines, ["engines", "engine", "chromium"]),
        (.storage, ["storage", "data", "website data"]),
        (.sync, ["sync", "icloud"]),
        (.advanced, ["advanced"]),
    ]

    /// "12 tabs in this space"
    private var openTabsDescription: String {
        let count = windowState?.activeSpace?.tabs.filter { !$0.isArchived }.count ?? 0
        return "\(count) \(count == 1 ? "tab" : "tabs") in this space"
    }
}
