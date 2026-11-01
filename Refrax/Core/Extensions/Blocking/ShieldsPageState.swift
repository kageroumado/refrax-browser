import Foundation

/// Whether Shields filters a page, and what the page card's Shields control and its popover
/// say about it.
nonisolated enum ShieldsPageState: Hashable, Sendable {
    /// The global switch (Settings → Privacy → Shields) is off.
    case off
    /// Shields is off for the page's site: `site` is the saved site setting that turned it off,
    /// which covers the page's host.
    case offForSite(site: String)
    /// Shields filters the page; `blocked` loads were blocked or redirected since it committed.
    case on(blocked: Int)

    /// - Parameters:
    ///   - host: The page's host.
    ///   - offSites: Sites the user turned Shields off for, each covering its subdomains.
    init(isEnabled: Bool, host: String?, offSites: [String], blocked: Int) {
        if !isEnabled {
            self = .off
        } else if let host, let site = Self.offSite(covering: host, in: offSites) {
            self = .offForSite(site: site)
        } else {
            self = .on(blocked: blocked)
        }
    }

    /// The entry of `offSites` that covers `host`: the host itself or its nearest listed parent.
    static func offSite(covering host: String, in offSites: [String]) -> String? {
        let sites = Set(offSites.map { $0.lowercased() })
        var candidate = host.lowercased()
        while !candidate.isEmpty {
            if sites.contains(candidate) {
                return candidate
            }
            guard let dot = candidate.firstIndex(of: ".") else { return nil }
            candidate = String(candidate[candidate.index(after: dot)...])
        }
        return nil
    }

    var isFiltering: Bool {
        if case .on = self {
            true
        } else {
            false
        }
    }

    var symbolName: String {
        isFiltering ? "shield.lefthalf.filled" : "shield.slash.fill"
    }

    /// The count on the control; nil when Shields blocked nothing or is off.
    var badge: String? {
        guard case let .on(blocked) = self, blocked > 0 else { return nil }
        return blocked < 100 ? "\(blocked)" : "99+"
    }

    /// The control's tooltip and accessibility label.
    var title: String {
        switch self {
        case .off: "Shields is off"
        case let .offForSite(site): "Shields is off for \(site)"
        case let .on(blocked): blocked == 1 ? "Shields blocked 1 load" : "Shields blocked \(blocked) loads"
        }
    }

    /// The popover's first line while Shields is off, with what turning it on changes.
    var offExplanation: String? {
        switch self {
        case .off: "Nothing is blocked on any site. Turning Shields on applies to every site."
        case let .offForSite(site): "Ads and trackers load on \(site) and its subdomains."
        case .on: nil
        }
    }
}
