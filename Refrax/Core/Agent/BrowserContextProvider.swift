import Foundation

/// Provides browser context for agent messages.
///
/// Extracts current page URL, title, selection, and space information
/// from WindowState for contextual AI interactions.
nonisolated enum BrowserContextProvider {
    /// Trigger phrases that indicate the user wants page context.
    private static let contextTriggers = [
        "this page",
        "this site",
        "this article",
        "current page",
        "current site",
        "current tab",
        "this tab",
        "here",
        "this url",
        "this link",
    ]

    /// Extracts browser context from window state.
    ///
    /// - Parameter windowState: The current window state.
    /// - Returns: Browser context if available.
    @MainActor
    static func extractContext(from windowState: WindowState) -> BrowserContext? {
        let url = windowState.activeWebPage?.url?.absoluteString
        let title = windowState.activeTab?.displayTitle
        let spaceName = windowState.activeSpace?.name

        // Return nil if no meaningful context
        guard url != nil || title != nil else {
            return nil
        }

        return BrowserContext(
            url: url,
            title: title,
            selectedText: nil, // Selected text requires async JS evaluation
            spaceName: spaceName,
        )
    }

    /// Determines if a message should include browser context.
    ///
    /// Checks if the message contains phrases that suggest the user
    /// is asking about the current page.
    ///
    /// - Parameter message: The user's message text.
    /// - Returns: `true` if context should be included.
    static func shouldIncludeContext(for message: String) -> Bool {
        let lowercased = message.lowercased()
        return contextTriggers.contains { lowercased.contains($0) }
    }

    /// Creates a context summary for display in the UI.
    ///
    /// - Parameter context: The browser context.
    /// - Returns: A short summary string (e.g., "example.com/article...").
    static func contextSummary(for context: BrowserContext) -> String? {
        guard let urlString = context.url,
              let url = URL(string: urlString) else {
            return nil
        }

        var summary = url.host ?? urlString

        // Add path if not just root
        let path = url.path
        if !path.isEmpty, path != "/" {
            let truncatedPath = path.count > 20
                ? String(path.prefix(17)) + "..."
                : path
            summary += truncatedPath
        }

        return summary
    }
}
