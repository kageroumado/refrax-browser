import Foundation

/// A collection of rules for detecting and dismissing cookie consent banners.
///
/// The ruleset contains rules for various Consent Management Platforms (CMPs)
/// like OneTrust, CookieBot, Quantcast, etc. Each rule defines how to:
/// - Detect the CMP's presence on a page
/// - Click the "reject all" or "necessary only" button
/// - Fall back to "accept" if no reject option exists
/// - Hide the banner overlay
struct AutoConsentRuleset: Codable, Sendable, Equatable {
    /// Version string for the ruleset (e.g., "2026.01.06").
    let version: String

    /// Source of the ruleset (e.g., "refrax-bundled", "community-update").
    let source: String

    /// Individual rules for detecting and dismissing banners.
    let rules: [ConsentRule]
}

/// A rule for detecting and dismissing a specific CMP or cookie banner.
struct ConsentRule: Codable, Sendable, Identifiable, Equatable {
    var id: String { name }

    /// Human-readable name for the CMP (e.g., "OneTrust", "CookieBot").
    let name: String

    /// URL patterns this rule applies to.
    ///
    /// Use `["*"]` to apply to all sites. Patterns support wildcards:
    /// - `*` matches any characters
    /// - `*.example.com` matches subdomains
    let match: [String]

    /// CSS selectors to detect the CMP's presence.
    ///
    /// If any of these selectors match an element, the CMP is considered present.
    let detect: [String]

    /// CSS selectors for "reject all" or "necessary only" buttons.
    ///
    /// Tried in order; first visible match is clicked.
    let reject: [String]

    /// CSS selectors for "accept all" buttons (fallback).
    ///
    /// Only used if no reject button is found. Some CMPs only offer accept.
    let accept: [String]

    /// CSS selectors for overlay elements to hide.
    ///
    /// Used to hide the consent banner and any backdrop overlay after action.
    let hide: [String]

    /// Optional delay in milliseconds before attempting actions.
    ///
    /// Some CMPs render buttons asynchronously; a delay ensures they're visible.
    let delay: Int?

    /// Optional nested frame selector.
    ///
    /// Some CMPs render their UI in an iframe. If specified, actions are
    /// performed inside the matched iframe.
    let frame: String?

    init(
        name: String,
        match: [String] = ["*"],
        detect: [String],
        reject: [String],
        accept: [String] = [],
        hide: [String] = [],
        delay: Int? = nil,
        frame: String? = nil,
    ) {
        self.name = name
        self.match = match
        self.detect = detect
        self.reject = reject
        self.accept = accept
        self.hide = hide
        self.delay = delay
        self.frame = frame
    }
}

extension AutoConsentRuleset {
    /// Creates an empty ruleset.
    static var empty: AutoConsentRuleset {
        AutoConsentRuleset(version: "0.0.0", source: "empty", rules: [])
    }

    /// Loads the bundled ruleset from the app's Resources.
    ///
    /// Falls back to an empty ruleset if the bundle is missing or malformed.
    static func loadBundled() -> AutoConsentRuleset {
        guard let url = Bundle.main.url(forResource: "auto-consent-rules", withExtension: "json") else {
            Logger.error("auto-consent-rules.json not found in bundle", category: Logger.tabs)
            return .empty
        }

        do {
            let data = try Data(contentsOf: url)
            let ruleset = try JSONDecoder().decode(AutoConsentRuleset.self, from: data)
            Logger.info(
                "Loaded bundled AutoConsent ruleset v\(ruleset.version) with \(ruleset.rules.count) rules",
                category: Logger.tabs,
            )
            return ruleset
        } catch {
            Logger.error("Failed to decode auto-consent-rules.json: \(error)", category: Logger.tabs)
            return .empty
        }
    }
}
