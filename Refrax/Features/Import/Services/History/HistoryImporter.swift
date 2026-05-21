import Foundation

/// Protocol for importing browsing history from external browsers.
///
/// Implementers parse browser-specific history storage formats and convert
/// them to `ImportedHistoryEntry` structures that can be imported into Refrax.
protocol HistoryImporter: Sendable {
    /// The browser this importer handles.
    var browser: ThirdPartyBrowser { get }

    /// Checks if history can be imported from the given profile.
    ///
    /// - Parameter profile: The browser profile to check.
    /// - Returns: `true` if the history database exists and is readable.
    func canImport(from profile: BrowserProfile) -> Bool

    /// Returns the date range of history available in the profile.
    ///
    /// Used to configure the time range slider in the import wizard.
    ///
    /// - Parameter profile: The browser profile to analyze.
    /// - Returns: A tuple of (earliest date, latest date), or `nil` if unavailable.
    func getHistoryDateRange(from profile: BrowserProfile) async throws -> (min: Date, max: Date)?

    /// Imports history entries from the given profile within the specified date range.
    ///
    /// - Parameters:
    ///   - profile: The browser profile to import from.
    ///   - dateRange: Optional date range filter. If `nil`, imports all history.
    /// - Returns: Array of imported history entries.
    func importHistory(
        from profile: BrowserProfile,
        dateRange: ClosedRange<Date>?,
    ) async throws -> [ImportedHistoryEntry]
}

/// Factory for creating the appropriate history importer for a browser.
enum HistoryImporterFactory {
    /// Creates a history importer for the specified browser.
    ///
    /// - Parameter browser: The browser to create an importer for.
    /// - Returns: An appropriate `HistoryImporter`, or `nil` if unsupported.
    static func createImporter(for browser: ThirdPartyBrowser) -> (any HistoryImporter)? {
        switch browser {
        case .chrome, .chromeBeta, .chromeCanary, .brave, .edge, .opera, .vivaldi, .helium:
            ChromiumHistoryImporter(browser: browser)
        case .arc:
            ChromiumHistoryImporter(browser: browser)
        case .safari:
            SafariHistoryImporter()
        case .firefox, .firefoxDeveloper, .zen:
            nil
        case .htmlFile:
            nil
        }
    }
}
