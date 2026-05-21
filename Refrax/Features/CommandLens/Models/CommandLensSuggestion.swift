import Foundation

/// A single suggestion item displayed in the CommandLens dropdown.
///
/// Suggestions are organized by type (open tabs, history, search engines, etc.)
/// and can be grouped with headers for visual separation. Each suggestion
/// has an action associated with its type that executes when selected.
///
/// ## Suggestion Types
///
/// | Type | Source | Action |
/// |------|--------|--------|
/// | `openTab` | Open tabs | Switch to tab |
/// | `url` | History/bookmarks | Navigate to URL |
/// | `search` | Search engine | Perform search |
/// | `searchProvider` | Built-in engines | Switch provider |
/// | `richEntity` | Knowledge graph | Navigate to entity |
///
/// ## Example
///
/// ```swift
/// let suggestion = CommandLensSuggestion(
///     type: .openTab(tabID: tabID),
///     text: "GitHub - Repository",
///     description: "github.com/user/repo",
///     iconName: "rectangle.on.rectangle",
///     groupHeader: "Open Tabs",
///     isRemovable: false,
///     keywordAction: nil,
///     url: nil
/// )
/// ```
struct CommandLensSuggestion: Identifiable, Hashable, Sendable {
    /// Unique identifier for this suggestion.
    let id = UUID()

    /// The type of suggestion, determining its action when selected.
    let type: SuggestionType

    /// Primary display text (title, search query, etc.).
    let text: String

    /// Secondary display text (URL, search engine name, etc.).
    let description: String

    /// SF Symbol name for the suggestion icon.
    let iconName: String

    /// Optional group header to display above this suggestion.
    let groupHeader: String?

    /// Whether this suggestion can be removed by the user.
    let isRemovable: Bool

    /// Optional keyword to insert when keyword action is triggered.
    let keywordAction: String?

    /// The URL to navigate to for URL-type suggestions.
    let url: URL?
    
    static func == (lhs: CommandLensSuggestion, rhs: CommandLensSuggestion) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    /// Creates a copy of this suggestion with a new group header.
    ///
    /// - Parameter title: The group header title to assign.
    /// - Returns: A new suggestion with the specified group header.
    func withGroupHeader(_ title: String) -> CommandLensSuggestion {
        CommandLensSuggestion(
            type: type,
            text: text,
            description: description,
            iconName: iconName,
            groupHeader: title,
            isRemovable: isRemovable,
            keywordAction: keywordAction,
            url: url,
        )
    }
}
