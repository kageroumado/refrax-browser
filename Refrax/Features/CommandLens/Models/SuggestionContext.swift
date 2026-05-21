import Foundation

/// Context passed to suggestion providers when fetching suggestions.
///
/// Contains all the information a provider needs to generate appropriate
/// suggestions for the current user input and application state.
struct SuggestionContext: Sendable {
    /// The user's current input text.
    let input: String

    /// Whether the input appears to be a direct URL (starts with http:// or https://).
    let isDirectURL: Bool

    /// Whether the input is empty (lens just opened).
    let isEmptyInput: Bool

    /// The user's browser settings for configuration.
    let settings: BrowserSettings

    /// The ID of the currently active tab, if any.
    let currentTabID: UUID?

    /// Whether a specific search engine has been selected (keyword mode).
    let selectedSearchEngine: SearchEngine?

    /// The URL of the current page, if available.
    let currentURL: URL?

    /// The domain of the current page, if available.
    var currentDomain: String? {
        currentURL?.host
    }

    /// Convenience initializer that computes derived properties.
    ///
    /// - Parameters:
    ///   - input: The user's current input text.
    ///   - settings: The user's browser settings.
    ///   - currentTabID: The ID of the currently active tab.
    ///   - selectedSearchEngine: The search engine selected via keyword, if any.
    ///   - currentURL: The URL of the current page.
    init(
        input: String,
        settings: BrowserSettings,
        currentTabID: UUID?,
        selectedSearchEngine: SearchEngine?,
        currentURL: URL? = nil,
    ) {
        self.input = input
        self.settings = settings
        self.currentTabID = currentTabID
        self.selectedSearchEngine = selectedSearchEngine
        self.currentURL = currentURL

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isEmptyInput = trimmed.isEmpty

        let lowercased = trimmed.lowercased()
        self.isDirectURL = lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://")
    }
}
