import AppKit
import Foundation

/// Represents a third-party browser from which bookmarks can be imported.
///
/// This enum defines all supported browsers for the import feature, including their
/// bundle identifiers, data directory paths, and display information.
///
/// ## Supported Browsers
///
/// - **Chromium-based**: Chrome, Brave, Edge, Opera, Vivaldi, Arc, Helium
/// - **Firefox-based**: Firefox, Firefox Developer Edition, Zen, Tor Browser
/// - **Safari**: Apple's native browser
/// - **Manual Import**: HTML bookmarks file
///
/// ## Usage
///
/// ```swift
/// // Check if a browser is installed
/// if ThirdPartyBrowser.chrome.isInstalled {
///     let profiles = BrowserDetector().detectProfiles(for: .chrome)
/// }
///
/// // Get browser icon for display
/// let icon = ThirdPartyBrowser.brave.iconImage
/// ```
///
/// ## Data Formats
///
/// | Browser Type | Format | Reference |
/// |-------------|--------|-----------|
/// | Chromium | JSON | `Bookmarks` file |
/// | Firefox | SQLite | `places.sqlite` database |
/// | Safari | Binary plist | `Bookmarks.plist` |
/// | Arc | JSON | `StorableSidebar.json` |
/// | HTML | Netscape HTML | Standard bookmark interchange format |
enum ThirdPartyBrowser: String, CaseIterable, Identifiable, Sendable {
    case chrome
    case chromeBeta
    case chromeCanary
    case brave
    case edge
    case firefox
    case firefoxDeveloper
    case safari
    case opera
    case vivaldi
    case arc
    case helium
    case zen
    case htmlFile

    var id: String { rawValue }

    /// Human-readable display name for the browser.
    var displayName: String {
        switch self {
        case .chrome: "Google Chrome"
        case .chromeBeta: "Google Chrome Beta"
        case .chromeCanary: "Google Chrome Canary"
        case .brave: "Brave"
        case .edge: "Microsoft Edge"
        case .firefox: "Firefox"
        case .firefoxDeveloper: "Firefox Developer Edition"
        case .safari: "Safari"
        case .opera: "Opera"
        case .vivaldi: "Vivaldi"
        case .arc: "Arc"
        case .helium: "Helium"
        case .zen: "Zen"
        case .htmlFile: "HTML Bookmarks File"
        }
    }

    /// macOS bundle identifier for the browser application.
    ///
    /// Returns `nil` for `.htmlFile` since it's not an installed application.
    var bundleIdentifier: String? {
        switch self {
        case .chrome: "com.google.Chrome"
        case .chromeBeta: "com.google.Chrome.beta"
        case .chromeCanary: "com.google.Chrome.canary"
        case .brave: "com.brave.Browser"
        case .edge: "com.microsoft.edgemac"
        case .firefox: "org.mozilla.firefox"
        case .firefoxDeveloper: "org.mozilla.firefoxdeveloperedition"
        case .safari: "com.apple.Safari"
        case .opera: "com.operasoftware.Opera"
        case .vivaldi: "com.vivaldi.Vivaldi"
        case .arc: "company.thebrowser.Browser"
        case .helium: "net.imput.helium"
        case .zen: "app.zen-browser.zen"
        case .htmlFile: nil
        }
    }

    /// Base directory URL where the browser stores its user data.
    ///
    /// Returns `nil` for `.htmlFile` since the user selects the file manually.
    var dataDirectoryURL: URL? {
        let fileManager = FileManager.default
        guard
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first,
            let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first
        else {
            return nil
        }

        switch self {
        case .chrome:
            return appSupport.appendingPathComponent("Google/Chrome")
        case .chromeBeta:
            return appSupport.appendingPathComponent("Google/Chrome Beta")
        case .chromeCanary:
            return appSupport.appendingPathComponent("Google/Chrome Canary")
        case .brave:
            return appSupport.appendingPathComponent("BraveSoftware/Brave-Browser")
        case .edge:
            return appSupport.appendingPathComponent("Microsoft Edge")
        case .firefox, .firefoxDeveloper:
            return appSupport.appendingPathComponent("Firefox/Profiles")
        case .safari:
            return library.appendingPathComponent("Safari")
        case .opera:
            return appSupport.appendingPathComponent("com.operasoftware.Opera")
        case .vivaldi:
            return appSupport.appendingPathComponent("Vivaldi")
        case .arc:
            return appSupport.appendingPathComponent("Arc/User Data")
        case .helium:
            return appSupport.appendingPathComponent("net.imput.helium")
        case .zen:
            return appSupport.appendingPathComponent("zen/Profiles")
        case .htmlFile:
            return nil
        }
    }

    /// Whether this browser is currently installed on the system.
    ///
    /// Verifies the app bundle exists on disk, not just in Launch Services.
    /// For `.htmlFile`, always returns `true` since it's always available as an option.
    var isInstalled: Bool {
        guard let bundleID = bundleIdentifier else {
            return true
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        return FileManager.default.fileExists(atPath: appURL.path)
    }

    /// The browser's application icon for display in the UI.
    ///
    /// Falls back to a generic document icon for `.htmlFile` or if the app icon cannot be loaded.
    var iconImage: NSImage? {
        guard
            let bundleID = bundleIdentifier,
            let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else {
            return NSImage(systemSymbolName: "doc.text", accessibilityDescription: "HTML file")
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    /// Whether this browser uses the Chromium bookmark format (JSON).
    ///
    /// Chromium-based browsers store bookmarks in a JSON file named `Bookmarks`
    /// within each profile directory.
    var isChromiumBased: Bool {
        switch self {
        case .chrome, .chromeBeta, .chromeCanary, .brave, .edge, .opera, .vivaldi, .helium:
            true
        case .arc, .firefox, .firefoxDeveloper, .zen, .safari, .htmlFile:
            false
        }
    }

    /// Whether this browser uses the Firefox bookmark format (SQLite).
    ///
    /// Firefox stores bookmarks in the `places.sqlite` database within each profile directory.
    var isFirefoxBased: Bool {
        switch self {
        case .firefox, .firefoxDeveloper, .zen:
            true
        default:
            false
        }
    }

    /// The Keychain service name for the browser's Safe Storage encryption key.
    ///
    /// Chromium browsers store an encryption passphrase in the macOS Keychain
    /// that is used to encrypt saved passwords. This passphrase is stored under
    /// a service name specific to each browser.
    ///
    /// Returns `nil` for non-Chromium browsers or browsers that don't support
    /// direct password import.
    var safeStorageKeychainName: String? {
        switch self {
        case .chrome:
            "Chrome Safe Storage"
        case .chromeBeta:
            "Chrome Safe Storage" // Beta uses the same key
        case .chromeCanary:
            "Chrome Safe Storage" // Canary uses the same key
        case .brave:
            "Brave Safe Storage"
        case .edge:
            "Microsoft Edge Safe Storage"
        case .opera:
            "Opera Safe Storage"
        case .vivaldi:
            "Vivaldi Safe Storage"
        case .arc:
            "Arc Safe Storage"
        case .helium:
            "Helium Safe Storage"
        case .firefox, .firefoxDeveloper, .zen, .safari, .htmlFile:
            nil
        }
    }

    /// Whether this browser supports direct password import from its database.
    ///
    /// Direct import reads passwords from the browser's encrypted SQLite database
    /// and decrypts them using the Safe Storage key from the Keychain.
    ///
    /// Supported browsers:
    /// - Chromium-based: Chrome, Brave, Edge, Opera, Vivaldi, Arc
    ///
    /// Not supported:
    /// - Safari: Uses iCloud Keychain (must export to CSV)
    /// - Firefox: Uses NSS encryption (complex, not yet implemented)
    var supportsDirectPasswordImport: Bool {
        safeStorageKeychainName != nil
    }

    /// Relative path from the profile directory to the Login Data SQLite file.
    ///
    /// Chromium browsers store encrypted passwords in a SQLite database called
    /// `Login Data` within each profile directory.
    var loginDataPath: String? {
        guard safeStorageKeychainName != nil else {
            return nil
        }
        return "Login Data"
    }
}
