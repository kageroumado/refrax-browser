import Foundation

/// Tracks the redirect chain for a navigation.
struct RedirectChain: Sendable, Equatable {
    private(set) var urls: [URL] = []
    private(set) var startTime: Date = .now

    /// Whether any URL in the chain appears to be OAuth-related.
    var containsOAuthURL: Bool {
        urls.contains { OAuthDomainRegistry.isOAuthFlow($0) }
    }

    /// Whether the chain began on an OAuth provider domain.
    var startsWithOAuthDomain: Bool {
        guard let first = urls.first else { return false }
        return OAuthDomainRegistry.isOAuthDomain(first.host)
    }

    mutating func append(_ url: URL) {
        urls.append(url)
    }

    mutating func reset() {
        urls.removeAll()
        startTime = .now
    }
}
