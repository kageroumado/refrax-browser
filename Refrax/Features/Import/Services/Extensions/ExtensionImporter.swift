import Foundation

/// Protocol for importing extension metadata from external browsers.
///
/// Since Refrax doesn't yet support extensions, these importers only
/// read metadata for display purposes. The actual extension code is
/// not imported.
protocol ExtensionImporter: Sendable {
    /// The browser this importer handles.
    var browser: ThirdPartyBrowser { get }

    /// Checks if extensions can be scanned from the given profile.
    func canImport(from profile: BrowserProfile) -> Bool

    /// Scans for installed extensions in the profile.
    ///
    /// - Parameter profile: The browser profile to scan.
    /// - Returns: Array of extension metadata.
    func importExtensions(from profile: BrowserProfile) async throws -> [ImportedExtension]
}

/// Factory for creating extension metadata importers.
enum ExtensionImporterFactory {
    /// Creates an extension importer for the specified browser.
    ///
    /// - Parameter browser: The browser to scan for extensions.
    /// - Returns: An appropriate `ExtensionImporter`, or `nil` if unsupported.
    static func createImporter(for browser: ThirdPartyBrowser) -> (any ExtensionImporter)? {
        switch browser {
        case .chrome, .chromeBeta, .chromeCanary, .brave, .edge, .opera, .vivaldi, .helium:
            ChromiumExtensionImporter(browser: browser)
        case .arc:
            ChromiumExtensionImporter(browser: browser)
        case .firefox, .firefoxDeveloper, .zen, .safari, .htmlFile:
            nil
        }
    }
}
