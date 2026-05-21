import Foundation

/// Protocol defining the interface for browser-specific bookmark importers.
///
/// Each supported browser has its own data format and storage location.
/// Implementations of this protocol handle the specifics of reading and
/// parsing bookmarks from that browser's data files.
///
/// ## Implementing a New Importer
///
/// To add support for a new browser:
///
/// 1. Create a class conforming to `DataImporter`
/// 2. Implement `canImport(from:)` to check if the profile has valid data
/// 3. Implement `importBookmarks(from:)` to parse and return bookmarks
///
/// ```swift
/// final class NewBrowserImporter: DataImporter {
///     let browser: ThirdPartyBrowser = .newBrowser
///
///     func canImport(from profile: BrowserProfile) -> Bool {
///         // Check if bookmarks file exists
///     }
///
///     func importBookmarks(from profile: BrowserProfile) async throws -> [ImportedFolder] {
///         // Parse bookmarks and return folder hierarchy
///     }
/// }
/// ```
///
/// ## Threading
///
/// Import operations may be time-consuming (especially for SQLite databases).
/// All import methods are async and should perform I/O on background threads.
protocol DataImporter: Sendable {
    /// The browser type this importer handles.
    var browser: ThirdPartyBrowser { get }

    /// Checks whether bookmarks can be imported from the given profile.
    ///
    /// This method should verify that the necessary data files exist and
    /// are accessible. It should not perform any actual parsing.
    ///
    /// - Parameter profile: The browser profile to check.
    /// - Returns: `true` if import is possible, `false` otherwise.
    func canImport(from profile: BrowserProfile) -> Bool

    /// Imports bookmarks from the specified browser profile.
    ///
    /// Parses the browser's bookmark data and returns it as a hierarchy of
    /// `ImportedFolder` objects. Each folder contains bookmarks and may
    /// contain nested subfolders.
    ///
    /// - Parameter profile: The browser profile to import from.
    /// - Returns: Array of root-level folders containing all bookmarks.
    /// - Throws: `ImportError` if the import fails.
    func importBookmarks(from profile: BrowserProfile) async throws -> [ImportedFolder]
}

/// Factory for creating the appropriate importer for a browser.
///
/// Use this to get an importer instance without needing to know the
/// specific implementation class.
///
/// ```swift
/// if let importer = ImporterFactory.importer(for: .chrome) {
///     let folders = try await importer.importBookmarks(from: profile)
/// }
/// ```
enum ImporterFactory {
    /// Creates an importer instance for the specified browser.
    ///
    /// - Parameter browser: The browser to create an importer for.
    /// - Returns: An importer instance, or `nil` if the browser is not supported.
    static func importer(for browser: ThirdPartyBrowser) -> (any DataImporter)? {
        switch browser {
        case .chrome, .chromeBeta, .chromeCanary, .brave, .edge, .opera, .vivaldi, .helium:
            ChromiumImporter(browser: browser)
        case .arc:
            ArcImporter()
        case .firefox, .firefoxDeveloper, .zen:
            FirefoxImporter(browser: browser)
        case .safari:
            SafariImporter()
        case .htmlFile:
            nil
        }
    }
}
