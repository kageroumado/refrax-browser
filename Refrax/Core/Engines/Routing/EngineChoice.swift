import Foundation

/// Which engine renders a page: the engine the user moved it to (its pin), else the site
/// rule for its URL, else the default engine.
///
/// A pin or rule naming an engine that isn't usable (not installed, or below its security
/// floor) is inert, and the next choice in line applies. System WebKit is always usable.
nonisolated struct EngineChoice: Sendable {
    let rules: SiteEngineRules
    let defaultEngine: EngineID
    /// The engines that may render pages now.
    let usable: Set<EngineID>

    init(rules: SiteEngineRules, defaultEngine: EngineID, usable: Set<EngineID>) {
        self.rules = rules
        self.defaultEngine = defaultEngine
        self.usable = usable.union([.systemWebKit])
    }

    /// The engine for `url` when nothing is pinned: its site rule's, else the default.
    func automaticEngine(for url: URL?) -> EngineID {
        if let rule = rules.rule(for: url), usable.contains(rule.engine) {
            return rule.engine
        }
        return usable.contains(defaultEngine) ? defaultEngine : .systemWebKit
    }

    /// The engine a page for `url` starts in.
    func startingEngine(for url: URL?, pinned: EngineID?) -> EngineID {
        if let pinned, usable.contains(pinned) {
            return pinned
        }
        return automaticEngine(for: url)
    }

    /// The pin to store when the user moves a page at `url` to `engine`: nil when `engine` is
    /// the one the page would get anyway, so the page goes back to following the rules.
    func pin(movingTo engine: EngineID, at url: URL?) -> EngineID? {
        engine == automaticEngine(for: url) ? nil : engine
    }

    /// The engine a top-level navigation continues in, or nil to let the active engine carry it.
    ///
    /// A page switches only when nothing pins it, it isn't an extension's page, the navigation
    /// leaves the page's host for an http(s) URL, and no switch has happened yet during this
    /// navigation.
    func engineSwitch(for navigation: EngineNavigation) -> EngineID? {
        guard !navigation.isPinned, !navigation.isExtensionPage, !navigation.hasSwitched,
              let target = SiteEngineRules.urlHost(of: navigation.url),
              target != SiteEngineRules.urlHost(of: navigation.pageURL) else { return nil }
        let engine = automaticEngine(for: navigation.url)
        return engine == navigation.activeEngine ? nil : engine
    }

    /// The rule changes to offer for a page at `url`: removing the rule that covers it, or,
    /// when none does, opening its host in each installed engine other than the one it gets now.
    ///
    /// - Parameter installed: Installed engines in display order.
    func ruleActions(for url: URL?, installed: [EngineID]) -> [SiteEngineRuleAction] {
        if let rule = rules.rule(for: url) {
            return [.remove(rule)]
        }
        guard let host = SiteEngineRules.urlHost(of: url).flatMap(SiteEngineRules.canonicalHost) else { return [] }
        let current = automaticEngine(for: url)
        return installed.filter { $0 != current }.map { .add(host: host, engine: $0) }
    }
}

/// A top-level navigation about to start in a page, as ``EngineChoice/engineSwitch(for:)``
/// sees it.
nonisolated struct EngineNavigation: Sendable {
    /// Where the navigation goes.
    let url: URL
    /// The page's address before the navigation.
    let pageURL: URL?
    /// The engine rendering the page.
    let activeEngine: EngineID
    /// Whether the user moved the page to its engine.
    let isPinned: Bool
    /// Whether the page is one of an extension's own, which only WebKit renders.
    let isExtensionPage: Bool
    /// Whether the page already changed engines during this navigation: a redirect or script
    /// navigation that follows a switch stays where it is.
    let hasSwitched: Bool
}
