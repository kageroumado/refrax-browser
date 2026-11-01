import Foundation

// MARK: - Site Engine Rule

/// Opens one site, and every subdomain of it, in a chosen engine.
nonisolated struct SiteEngineRule: Codable, Hashable, Sendable {
    /// The site's host in canonical form (``SiteEngineRules/canonicalHost(_:)``): lowercase ASCII,
    /// IDNA-encoded, without a port or a leading `www.`.
    let host: String

    /// The engine the site opens in.
    let engine: EngineID

    /// Whether this rule covers `urlHost`: the same host, or a subdomain of it.
    ///
    /// - Parameter urlHost: A host in ``SiteEngineRules/urlHost(of:)`` form.
    func covers(_ urlHost: String) -> Bool {
        urlHost == host || urlHost.hasSuffix("." + host)
    }
}

// MARK: - Site Engine Rules

/// The ordered list of sites the user opens in a particular engine.
///
/// A URL takes the rule with the longest host that covers it, so `music.youtube.com` beats
/// `youtube.com`. Each host appears at most once.
nonisolated struct SiteEngineRules: Codable, Hashable, Sendable {
    private(set) var rules: [SiteEngineRule]

    init(_ rules: [SiteEngineRule] = []) {
        var seen = Set<String>()
        self.rules = rules.filter { seen.insert($0.host).inserted }
    }

    /// The rules a settings object starts with: YouTube in Chromium, where it plays far better
    /// than in WebKit. Inert until Chromium is installed.
    static let defaults = SiteEngineRules([
        SiteEngineRule(host: "youtube.com", engine: .chromium),
        SiteEngineRule(host: "youtu.be", engine: .chromium),
        SiteEngineRule(host: "youtube-nocookie.com", engine: .chromium),
    ])

    /// The most specific rule covering `url`'s host; nil for a URL that isn't http(s).
    func rule(for url: URL?) -> SiteEngineRule? {
        guard let host = Self.urlHost(of: url) else { return nil }
        return rules
            .filter { $0.covers(host) }
            .max { $0.host.count < $1.host.count }
    }

    /// The rule for exactly `host`, given in any form ``canonicalHost(_:)`` accepts.
    func rule(forHost host: String) -> SiteEngineRule? {
        guard let host = Self.canonicalHost(host) else { return nil }
        return rules.first { $0.host == host }
    }

    // MARK: Editing

    /// Opens `host` in `engine`, replacing the rule for that host in place or appending one.
    ///
    /// - Returns: The canonical host, or nil when `host` isn't a usable host name.
    @discardableResult
    mutating func set(_ engine: EngineID, for host: String) -> String? {
        guard let host = Self.canonicalHost(host) else { return nil }
        let rule = SiteEngineRule(host: host, engine: engine)
        if let index = rules.firstIndex(where: { $0.host == host }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        return host
    }

    /// Changes a rule's host, keeping its place and engine.
    ///
    /// - Returns: Whether the rule moved: false when `newHost` is unusable or another rule
    ///   already has it.
    @discardableResult
    mutating func rename(_ host: String, to newHost: String) -> Bool {
        guard let index = rules.firstIndex(where: { $0.host == host }),
              let newHost = Self.canonicalHost(newHost) else { return false }
        if newHost == host {
            return true
        }
        guard !rules.contains(where: { $0.host == newHost }) else { return false }
        rules[index] = SiteEngineRule(host: newHost, engine: rules[index].engine)
        return true
    }

    /// Removes the rule for `host`, given in any form ``canonicalHost(_:)`` accepts.
    ///
    /// - Returns: The removed rule, if there was one.
    @discardableResult
    mutating func remove(host: String) -> SiteEngineRule? {
        guard let host = Self.canonicalHost(host),
              let index = rules.firstIndex(where: { $0.host == host }) else { return nil }
        return rules.remove(at: index)
    }

    // MARK: Hosts

    /// The canonical form of a host the user typed: lowercase, IDNA-encoded, without a scheme,
    /// path, port, trailing dot, or leading `www.`. Accepts a pasted URL too.
    ///
    /// - Returns: Nil for text that isn't a host name.
    static func canonicalHost(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let schemeEnd = text.range(of: "://") {
            text = String(text[schemeEnd.upperBound...])
        }
        if let pathStart = text.firstIndex(where: { "/?#".contains($0) }) {
            text = String(text[..<pathStart])
        }
        if let portStart = text.lastIndex(of: ":") {
            text = String(text[..<portStart])
        }
        guard let host = encodedHost(text) else { return nil }
        if host.hasPrefix(Constants.wwwPrefix), host.dropFirst(Constants.wwwPrefix.count).contains(".") {
            return String(host.dropFirst(Constants.wwwPrefix.count))
        }
        return host
    }

    /// `url`'s host in the form rules match against: lowercase and IDNA-encoded, without a
    /// trailing dot. Nil unless `url` is http or https.
    static func urlHost(of url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(percentEncoded: false) else { return nil }
        return encodedHost(host)
    }

    /// `host` lowercased and IDNA-encoded, without a trailing dot; nil when it holds anything
    /// but letters, digits, dots, hyphens, and underscores once encoded.
    private static func encodedHost(_ host: String) -> String? {
        var components = URLComponents()
        components.host = host
        guard var encoded = components.encodedHost?.lowercased() else { return nil }
        while encoded.hasSuffix(".") {
            encoded.removeLast()
        }
        guard !encoded.isEmpty, !encoded.hasPrefix("."), !encoded.contains(".."),
              encoded.unicodeScalars.allSatisfy(Constants.hostCharacters.contains) else { return nil }
        return encoded
    }

    private enum Constants {
        static let wwwPrefix = "www."
        static let hostCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-_")
    }
}

// MARK: - Rule Actions

/// A change to the site rules offered for the page on screen, in the reload menus.
nonisolated enum SiteEngineRuleAction: Hashable, Sendable {
    /// Open `host` in `engine` from now on.
    case add(host: String, engine: EngineID)
    /// Stop applying `rule`.
    case remove(SiteEngineRule)
}
