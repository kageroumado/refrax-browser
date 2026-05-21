import Foundation
import Observation

/// Tracks and enforces Focus Mode domain restrictions.
///
/// `RestrictionEnforcer` is a singleton that holds the current state of domain restrictions
/// based on the active Focus Mode. It's updated by `FocusModeManager` when Focus changes
/// and queried by navigation handlers to determine if URLs should be blocked or blurred.
///
/// ## Domain Matching
///
/// Supports two pattern formats:
/// - Exact match: `reddit.com` matches `reddit.com` and subdomains like `www.reddit.com`
/// - Wildcard: `*.google.com` explicitly matches any subdomain including `google.com`
///
/// ## Thread Safety
///
/// All state is isolated to `@MainActor` since it's updated by UI/Focus events
/// and read during navigation decisions which dispatch to main actor.
@Observable
final class RestrictionEnforcer {
    // MARK: - Singleton

    static let shared = RestrictionEnforcer()

    // MARK: - State

    /// Domains that should show a blocking interstitial.
    private(set) var blockedDomains: Set<String> = []

    /// Domains that should show blurred content until revealed.
    private(set) var blurredDomains: Set<String> = []

    /// Whether browser notifications should be suppressed.
    private(set) var suppressNotifications: Bool = false

    /// Domains that the user has bypassed for the current session.
    ///
    /// When a user clicks "Proceed Anyway" on an interstitial, the domain is added here.
    /// This set is cleared when Focus Mode changes.
    private(set) var sessionBypassedDomains: Set<String> = []

    /// Domains where the user clicked to reveal blurred content.
    ///
    /// Tracks which pages the user has explicitly revealed so blur isn't re-applied
    /// on same-site navigation or Focus Mode re-activation during the same session.
    private(set) var revealedBlurDomains: Set<String> = []

    /// The identifier of the Focus Mode that set the current restrictions.
    ///
    /// Used to clear session bypasses when Focus Mode changes.
    private(set) var activeFocusIdentifier: String?

    // MARK: - Computed Properties

    /// Whether any restrictions are currently active.
    var isActive: Bool {
        !blockedDomains.isEmpty || !blurredDomains.isEmpty || suppressNotifications
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Updates

    /// Updates the restriction state based on a Focus Mode mapping.
    ///
    /// Called by `FocusModeManager` when Focus Mode activates or changes.
    /// Clears session bypasses if the Focus identifier changed.
    ///
    /// - Parameters:
    ///   - blockedDomains: Domains to block with interstitial.
    ///   - blurredDomains: Domains to blur until revealed.
    ///   - suppressNotifications: Whether to suppress notifications.
    ///   - focusIdentifier: The identifier of the Focus Mode, or nil if Focus is off.
    func updateFocusRestrictions(
        blockedDomains: [String],
        blurredDomains: [String],
        suppressNotifications: Bool,
        focusIdentifier: String?,
    ) {
        // Clear session bypasses if Focus changed
        if focusIdentifier != activeFocusIdentifier {
            sessionBypassedDomains.removeAll()
            revealedBlurDomains.removeAll()
        }

        self.blockedDomains = Set(blockedDomains.map { $0.lowercased() })
        self.blurredDomains = Set(blurredDomains.map { $0.lowercased() })
        self.suppressNotifications = suppressNotifications
        activeFocusIdentifier = focusIdentifier

        if isActive {
            Logger.info(
                "Focus restrictions active: \(blockedDomains.count) blocked, \(blurredDomains.count) blurred",
                category: Logger.ui,
            )
        }
    }

    /// Clears all restrictions (called when Focus Mode is disabled).
    func clearRestrictions() {
        blockedDomains.removeAll()
        blurredDomains.removeAll()
        suppressNotifications = false
        sessionBypassedDomains.removeAll()
        revealedBlurDomains.removeAll()
        activeFocusIdentifier = nil
    }

    // MARK: - Domain Checks

    /// Checks if a domain should be blocked with an interstitial.
    ///
    /// Returns `false` if the user has bypassed this domain for the current session.
    ///
    /// - Parameter domain: The domain to check (e.g., "www.reddit.com").
    /// - Returns: `true` if the domain matches a blocked pattern and hasn't been bypassed.
    func shouldBlock(domain: String) -> Bool {
        let normalizedDomain = domain.lowercased()

        // Check session bypass first
        if isDomainBypassed(normalizedDomain) {
            return false
        }

        return matchesDomainSet(normalizedDomain, in: blockedDomains)
    }

    /// Checks if a domain should show blurred content.
    ///
    /// Returns `false` if the user has revealed this domain for the current session.
    ///
    /// - Parameter domain: The domain to check.
    /// - Returns: `true` if the domain matches a blurred pattern and hasn't been revealed.
    func shouldBlur(domain: String) -> Bool {
        let normalizedDomain = domain.lowercased()

        // Check if user has revealed this domain
        if isDomainRevealed(normalizedDomain) {
            return false
        }

        return matchesDomainSet(normalizedDomain, in: blurredDomains)
    }

    // MARK: - Session Bypass

    /// Adds a domain to the session bypass list.
    ///
    /// Called when the user clicks "Proceed Anyway" on a Focus interstitial.
    /// The bypass applies to the root domain, so bypassing `www.reddit.com`
    /// also allows `old.reddit.com`.
    ///
    /// - Parameter domain: The domain to bypass.
    func addBypassForSession(domain: String) {
        let rootDomain = extractRootDomain(from: domain.lowercased())
        sessionBypassedDomains.insert(rootDomain)
        Logger.info("Focus bypass added for session: \(rootDomain)", category: Logger.ui)
    }

    /// Marks a domain as revealed (blur removed).
    ///
    /// Called when the user clicks to reveal blurred content.
    ///
    /// - Parameter domain: The domain that was revealed.
    func markDomainRevealed(domain: String) {
        let rootDomain = extractRootDomain(from: domain.lowercased())
        revealedBlurDomains.insert(rootDomain)
        Logger.info("Focus blur revealed for: \(rootDomain)", category: Logger.ui)
    }

    // MARK: - Private Helpers

    /// Checks if a domain has been bypassed for this session.
    private func isDomainBypassed(_ domain: String) -> Bool {
        let rootDomain = extractRootDomain(from: domain)
        return sessionBypassedDomains.contains(rootDomain)
    }

    /// Checks if a domain's blur has been revealed for this session.
    private func isDomainRevealed(_ domain: String) -> Bool {
        let rootDomain = extractRootDomain(from: domain)
        return revealedBlurDomains.contains(rootDomain)
    }

    /// Checks if a domain matches any pattern in the given set.
    ///
    /// Matching rules:
    /// - Exact match: `reddit.com` matches `reddit.com`
    /// - Subdomain match: `reddit.com` matches `www.reddit.com`, `old.reddit.com`
    /// - Wildcard: `*.google.com` matches `google.com` and any subdomain
    private func matchesDomainSet(_ domain: String, in patterns: Set<String>) -> Bool {
        patterns.contains { matchesDomain(domain, pattern: $0) }
    }

    /// Checks if a domain matches a single pattern.
    private func matchesDomain(_ domain: String, pattern: String) -> Bool {
        // Skip malformed patterns
        guard !pattern.isEmpty,
              !pattern.hasPrefix("http"),
              !pattern.contains("/"),
              !pattern.contains("@")
        else {
            return false
        }

        if pattern.hasPrefix("*.") {
            // Wildcard subdomain match: *.google.com
            let suffix = String(pattern.dropFirst(2))
            guard !suffix.isEmpty else { return false }

            // Match exact domain or any subdomain
            return domain == suffix || domain.hasSuffix("." + suffix)
        } else {
            // Exact match or subdomain match
            // "reddit.com" should match "reddit.com", "www.reddit.com", "old.reddit.com"
            return domain == pattern || domain.hasSuffix("." + pattern)
        }
    }

    /// Extracts the root domain from a potentially subdomain-qualified hostname.
    ///
    /// Simple heuristic: takes the last two components for standard TLDs,
    /// or last three for known two-part TLDs (co.uk, com.au, etc.).
    private func extractRootDomain(from domain: String) -> String {
        let components = domain.split(separator: ".")

        guard components.count > 1 else {
            return domain
        }

        // Check for two-part TLDs
        let twoPartTLDs = ["co.uk", "com.au", "co.nz", "co.jp", "com.br", "org.uk"]
        let lastTwo = components.suffix(2).joined(separator: ".")

        if twoPartTLDs.contains(lastTwo), components.count > 2 {
            // Return last 3 components (e.g., "example.co.uk")
            return components.suffix(3).joined(separator: ".")
        }

        // Return last 2 components (e.g., "example.com")
        return components.suffix(2).joined(separator: ".")
    }
}
