import CryptoKit
import Foundation
import SwiftData

/// A user-defined CSS style applied to matching web pages.
///
/// User styles enable per-site CSS customization. Styles can be:
/// - Installed from Userstyles.world with one click
/// - Created manually via the Settings panel
/// - Imported from `.user.css` files
///
/// ## Domain Matching
///
/// Styles match based on domain patterns (e.g., "github.com", "*.gitlab.com")
/// and/or URL patterns for finer control. Global styles apply to all sites.
///
/// ## CSS Processing
///
/// User CSS is automatically processed to add `!important` to all declarations,
/// ensuring styles override site CSS without manual annotation.
///
/// ## Usage
///
/// ```swift
/// let style = UserStyle(name: "GitHub Dark", css: "body { background: #0d1117; }")
/// style.domainPatterns = ["github.com", "*.github.com"]
/// modelContext.insert(style)
/// ```
@Model
final class UserStyle {
    /// Unique identifier for the style.
    @Attribute(.unique, .preserveValueOnDeletion)
    var id: UUID = UUID()

    /// Display name of the style.
    var name: String

    /// Optional description of what the style does.
    var styleDescription: String?

    /// Author of the style (from metadata or user-entered).
    var author: String?

    /// Version string (from metadata).
    var version: String?

    // MARK: - Source

    /// Raw CSS content before !important processing.
    ///
    /// This is the original CSS as written by the author. The manager
    /// processes this to add `!important` before injection.
    var css: String

    /// URL where the style was installed from, if any.
    ///
    /// Used for update checking and attribution.
    var sourceURL: URL?

    /// URL to check for updates, if different from sourceURL.
    var updateURL: URL?

    /// SHA-256 hash of the source CSS for update detection.
    ///
    /// When checking for updates, a new hash is computed and compared.
    /// Different hash indicates new version available.
    var sourceHash: String

    // MARK: - Matching

    /// Domain patterns this style applies to.
    ///
    /// Supports:
    /// - Exact domains: "github.com"
    /// - Wildcard subdomains: "*.github.com"
    ///
    /// A URL matches if it matches any pattern. Patterns are case-insensitive.
    var domainPatterns: [String]

    /// URL patterns for finer-grained matching.
    ///
    /// Supports glob-style patterns:
    /// - "https://github.com/*/issues" matches issues pages
    /// - "https://example.com/dashboard/*" matches dashboard paths
    var urlPatterns: [String]

    /// Whether this style applies to all sites.
    ///
    /// Global styles match any URL with a host (excluding about:, data:, etc.).
    /// When true, `domainPatterns` and `urlPatterns` are ignored.
    var isGlobal: Bool = false

    // MARK: - State

    /// Whether the style is currently enabled.
    ///
    /// Disabled styles are stored but not injected into pages.
    var isEnabled: Bool = true

    /// When the style was first installed.
    var installedAt: Date

    /// When the style was last modified (via edit or update).
    var lastUpdatedAt: Date?

    /// When updates were last checked (for remote styles).
    var lastUpdateCheckAt: Date?

    // MARK: - Computed Properties

    /// Display name, falling back to "Untitled Style" if empty.
    var displayName: String {
        name.isEmpty ? "Untitled Style" : name
    }

    /// Primary domain for grouping in the UI.
    ///
    /// Returns the first non-wildcard domain pattern, or "Global" for global styles.
    var primaryDomain: String {
        if isGlobal { return "Global" }
        let domain = domainPatterns.first { !$0.hasPrefix("*.") }
            ?? domainPatterns.first?.replacingOccurrences(of: "*.", with: "")
        return domain ?? "Untitled"
    }

    /// Whether this style was installed from a remote source.
    var isRemote: Bool {
        sourceURL != nil
    }

    // MARK: - Initialization

    /// Creates a new user style.
    ///
    /// - Parameters:
    ///   - name: Display name for the style.
    ///   - css: Raw CSS content.
    ///   - domainPatterns: Domain patterns to match (default empty).
    ///   - urlPatterns: URL patterns to match (default empty).
    ///   - isGlobal: Whether the style applies globally (default false).
    init(
        name: String,
        css: String,
        domainPatterns: [String] = [],
        urlPatterns: [String] = [],
        isGlobal: Bool = false,
    ) {
        self.name = name
        self.css = css
        self.domainPatterns = domainPatterns
        self.urlPatterns = urlPatterns
        self.isGlobal = isGlobal
        self.sourceHash = Self.computeHash(css)
        self.installedAt = Date()
    }

    // MARK: - Hash Computation

    /// Computes SHA-256 hash of CSS content.
    ///
    /// Used for detecting changes when checking for updates.
    static func computeHash(_ css: String) -> String {
        SHA256.hash(data: Data(css.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Updates the style's CSS and recomputes the hash.
    func updateCSS(_ newCSS: String) {
        css = newCSS
        sourceHash = Self.computeHash(newCSS)
        lastUpdatedAt = Date()
    }
}
