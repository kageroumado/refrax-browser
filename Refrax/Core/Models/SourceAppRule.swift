import AppKit
import Foundation
import SwiftData

/// A rule for handling external URLs based on the source application.
///
/// Source app rules allow different behavior based on which application
/// opened the URL. For example:
///
/// - Links from Mail → Open in Glimpse window
/// - Links from Slack → Open in "Work" space
/// - Links from Xcode → Open in "Development" space
///
/// ## Bundle ID Matching
///
/// Rules match by bundle identifier pattern:
/// - `com.apple.mail` — exact match
/// - `com.apple.*` — matches all Apple apps
/// - `*slack*` — matches any bundle ID containing "slack"
@Model
final class SourceAppRule {
    /// Stable identifier for sync.
    @Attribute(.preserveValueOnDeletion)
    var id: UUID = UUID()

    /// Display name for this rule.
    var name: String

    /// Bundle identifier pattern to match.
    ///
    /// Supports `*` wildcards. Examples:
    /// - `com.apple.mail` — Apple Mail
    /// - `com.tinyspeck.slackmacgap` — Slack
    /// - `com.apple.*` — any Apple app
    var bundleIDPattern: String

    /// The action to take when this rule matches.
    var actionRaw: String = ""

    /// Target space ID for space-specific actions.
    var targetSpaceID: UUID?

    /// Target group ID for group-specific actions.
    var targetGroupID: UUID?

    /// Whether this rule is active.
    var isEnabled: Bool = true

    /// Sort order within the rule list.
    var order: Int = 0

    /// Parent settings (inverse relationship).
    var settings: ExternalURLSettings?

    // MARK: - Cached Regex

    @Transient
    private var _cachedRegex: Regex<AnyRegexOutput>?

    @Transient
    private var _cachedPattern: String?

    // MARK: - Initialization

    init(
        name: String,
        bundleIDPattern: String,
        action: ExternalURLAction = .openInCurrentSpace,
        targetSpaceID: UUID? = nil,
        targetGroupID: UUID? = nil,
        isEnabled: Bool = true,
        order: Int = 0,
    ) {
        self.name = name
        self.bundleIDPattern = bundleIDPattern
        self.targetSpaceID = targetSpaceID
        self.targetGroupID = targetGroupID
        self.isEnabled = isEnabled
        self.order = order
        self.action = action
    }

    // MARK: - Action Property

    /// The action to take when this rule matches.
    var action: ExternalURLAction {
        get {
            ExternalURLAction.decode(
                from: actionRaw,
                targetSpaceID: targetSpaceID,
                targetGroupID: targetGroupID,
            )
        }
        set {
            let encoded = newValue.encode()
            actionRaw = encoded.rawValue
            targetSpaceID = encoded.targetSpaceID
            targetGroupID = encoded.targetGroupID
        }
    }

    // MARK: - Matching

    /// Checks if this rule matches a bundle identifier.
    ///
    /// - Parameter bundleID: The bundle ID to check.
    /// - Returns: True if the pattern matches.
    func matches(bundleID: String) -> Bool {
        guard isEnabled else { return false }

        // Exact match optimization
        if !bundleIDPattern.contains("*") {
            return bundleID.lowercased() == bundleIDPattern.lowercased()
        }

        // Wildcard match
        guard let regex = regex(for: bundleIDPattern.lowercased()) else {
            return false
        }

        return bundleID.lowercased().wholeMatch(of: regex) != nil
    }

    // MARK: - Regex Caching

    private func regex(for pattern: String) -> Regex<AnyRegexOutput>? {
        if pattern == _cachedPattern, let cached = _cachedRegex {
            return cached
        }

        guard let regex = compileWildcardPattern(pattern) else {
            return nil
        }

        _cachedPattern = pattern
        _cachedRegex = regex
        return regex
    }

    private func compileWildcardPattern(_ pattern: String) -> Regex<AnyRegexOutput>? {
        var regexPattern = ""
        for char in pattern {
            if char == "*" {
                regexPattern += ".*"
            } else if "\\^$.|?+()[]{}".contains(char) {
                regexPattern += "\\\(char)"
            } else {
                regexPattern += String(char)
            }
        }

        return try? Regex(regexPattern).ignoresCase()
    }
}

// MARK: - Display Helpers

extension SourceAppRule {
    /// A human-readable description of this rule's action.
    var actionDescription: String {
        action.description
    }

    /// Returns the display name for a bundle ID, if the app is installed.
    static func appName(for bundleID: String) -> String? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }

        let appName = appURL.deletingPathExtension().lastPathComponent
        return appName.isEmpty ? nil : appName
    }
}

// MARK: - Common Source Apps

extension SourceAppRule {
    /// Common application bundle identifiers for quick rule creation.
    enum CommonApps {
        static let mail = "com.apple.mail"
        static let safari = "com.apple.Safari"
        static let messages = "com.apple.MobileSMS"
        static let notes = "com.apple.Notes"
        static let slack = "com.tinyspeck.slackmacgap"
        static let discord = "com.hnc.Discord"
        static let xcode = "com.apple.dt.Xcode"
        static let vscode = "com.microsoft.VSCode"
        static let terminal = "com.apple.Terminal"
        static let finder = "com.apple.finder"
        static let teams = "com.microsoft.teams2"
        static let notion = "notion.id"

        /// All common apps with display names.
        static let all: [(name: String, bundleID: String)] = [
            ("Mail", mail),
            ("Safari", safari),
            ("Messages", messages),
            ("Notes", notes),
            ("Slack", slack),
            ("Discord", discord),
            ("Xcode", xcode),
            ("VS Code", vscode),
            ("Terminal", terminal),
            ("Finder", finder),
            ("Teams", teams),
            ("Notion", notion),
        ]
    }
}
