import Foundation

/// Registry of known call/video conferencing domains.
///
/// Used by ``MediaControlsManager`` to determine if a tab is likely in a call
/// based on the URL domain combined with active media capture state.
///
/// ## Built-in Domains
///
/// The registry includes popular video conferencing services:
/// - Zoom, Google Meet, Microsoft Teams
/// - Discord, Slack, WebEx
/// - FaceTime Web, Google Duo, Messenger
///
/// ## User Domains
///
/// Users can add custom domains for lesser-known services or internal
/// corporate video chat tools. These persist in UserDefaults.
@Observable
final class CallDomainRegistry {
    // MARK: - Built-in Domains

    /// Built-in call domains (read-only).
    ///
    /// These are well-known video conferencing services that are always
    /// recognized without user configuration.
    static let builtIn: Set<String> = [
        // Major platforms
        "zoom.us",
        "meet.google.com",
        "teams.microsoft.com",
        "teams.live.com",

        // Communication apps
        "discord.com",
        "slack.com",
        "whereby.com",

        // Enterprise
        "webex.com",

        // Apple / Google / Meta
        "facetime.apple.com",
        "duo.google.com",
        "messenger.com",

        // Other
        "gather.town",
        "around.co",
        "tuple.app",
        "pop.com",
        "loom.com",
        "cal.com",
    ]

    // MARK: - User Domains

    /// User-added domains (persisted in UserDefaults).
    var userDomains: Set<String> {
        didSet {
            persistUserDomains()
        }
    }

    // MARK: - UserDefaults Key

    private static let userDomainsKey = "CallDomainRegistry.userDomains"

    // MARK: - Initialization

    init() {
        // Load user domains from UserDefaults
        if let saved = UserDefaults.standard.array(forKey: Self.userDomainsKey) as? [String] {
            self.userDomains = Set(saved)
        } else {
            self.userDomains = []
        }
    }

    // MARK: - Domain Checking

    /// Checks if the given host is a known call domain.
    ///
    /// Matches against both built-in and user-added domains. The check is
    /// suffix-based to handle subdomains (e.g., "us02web.zoom.us" matches "zoom.us").
    ///
    /// - Parameter host: The URL host to check.
    /// - Returns: `true` if the host is a known call domain.
    func isCallDomain(_ host: String) -> Bool {
        let lowercased = host.lowercased()

        // Check exact match first (most common case)
        if Self.builtIn.contains(lowercased) || userDomains.contains(lowercased) {
            return true
        }

        // Check suffix match for subdomains
        for domain in Self.builtIn {
            if lowercased.hasSuffix(".\(domain)") {
                return true
            }
        }

        for domain in userDomains {
            if lowercased.hasSuffix(".\(domain)") {
                return true
            }
        }

        return false
    }

    // MARK: - User Domain Management

    /// Adds a user domain to the registry.
    ///
    /// - Parameter host: The domain to add (e.g., "company-video.internal").
    func addUserDomain(_ host: String) {
        let normalized = host.lowercased()
        guard !normalized.isEmpty else { return }
        userDomains.insert(normalized)
    }

    /// Removes a user domain from the registry.
    ///
    /// - Parameter host: The domain to remove.
    func removeUserDomain(_ host: String) {
        userDomains.remove(host.lowercased())
    }

    // MARK: - Persistence

    private func persistUserDomains() {
        UserDefaults.standard.set(Array(userDomains), forKey: Self.userDomainsKey)
    }
}
