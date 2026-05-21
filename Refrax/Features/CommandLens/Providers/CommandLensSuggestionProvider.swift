import Foundation

/// A type that can provide suggestions to CommandLens.
///
/// Implement this protocol to add new suggestion sources to CommandLens.
/// Each provider is responsible for a specific type of suggestion (e.g., open tabs,
/// history, search engines) and can be enabled or disabled based on context.
///
/// ## Implementation Guidelines
///
/// - Providers should be lightweight and stateless where possible
/// - The ``suggestions(for:)`` method should return quickly for local data
/// - Network-based providers should handle cancellation gracefully
/// - Use ``shouldProvide(for:)`` to skip irrelevant contexts
///
/// ## Example
///
/// ```swift
/// struct BookmarksProvider: CommandLensSuggestionProvider {
///     let id = "bookmarks"
///     let priority = 200
///     let groupHeader = "Bookmarks"
///
///     func shouldProvide(for context: SuggestionContext) -> Bool {
///         !context.isEmptyInput
///     }
///
///     func suggestions(for context: SuggestionContext) async -> [CommandLensSuggestion] {
///         // Fetch and return bookmark suggestions
///     }
/// }
/// ```
protocol CommandLensSuggestionProvider: Sendable {
    /// Unique identifier for this provider.
    ///
    /// Used for debugging and configuration. Should be a lowercase string
    /// without spaces (e.g., "open-tabs", "history", "search-network").
    var id: String { get }

    /// Display priority for suggestions from this provider.
    ///
    /// Lower values appear first in the suggestion list. Suggested ranges:
    /// - 0-99: Primary suggestions (open tabs, direct URL)
    /// - 100-199: Local suggestions (history, bookmarks)
    /// - 200-299: Search engine suggestions
    /// - 300+: Network/async suggestions
    var priority: Int { get }

    /// The group header to display above suggestions from this provider.
    ///
    /// Return `nil` if suggestions should not have a group header.
    var groupHeader: String? { get }

    /// Maximum number of suggestions this provider should return.
    ///
    /// The provider is responsible for enforcing this limit in its
    /// ``suggestions(for:)`` implementation.
    var maxSuggestions: Int { get }

    /// Whether this provider should be queried for the given context.
    ///
    /// Return `false` to skip this provider entirely for certain inputs.
    /// For example, a search suggestion provider might skip direct URL inputs.
    ///
    /// - Parameter context: The current suggestion context.
    /// - Returns: `true` if this provider should generate suggestions.
    func shouldProvide(for context: SuggestionContext) -> Bool

    /// Generates suggestions for the given context.
    ///
    /// This method may be called concurrently with other providers.
    /// Implementations should handle task cancellation appropriately.
    ///
    /// - Parameter context: The current suggestion context.
    /// - Returns: An array of suggestions, limited to ``maxSuggestions``.
    func suggestions(for context: SuggestionContext) async -> [CommandLensSuggestion]
}

// MARK: - Default Implementations

extension CommandLensSuggestionProvider {
    /// Default maximum suggestions is 10.
    var maxSuggestions: Int { 10 }

    /// By default, providers always provide suggestions.
    func shouldProvide(for _: SuggestionContext) -> Bool { true }
}
