import Foundation

extension SiteEngineRuleAction {
    /// The menu item title: "Always Open youtube.com in Chromium", "Stop Opening youtube.com in Chromium".
    func title(registry: EngineRegistry) -> String {
        switch self {
        case let .add(host, engine):
            "Always Open \(host) in \(registry.displayName(for: engine))"
        case let .remove(rule):
            "Stop Opening \(rule.host) in \(registry.displayName(for: rule.engine))"
        }
    }

    /// Changes the site rules in `settings`, then unpins `page` and moves it to the engine its
    /// site gets now.
    func apply(to settings: BrowserSettings, page: WebPage?, registry: EngineRegistry) {
        var rules = settings.siteEngineRules
        switch self {
        case let .add(host, engine):
            rules.set(engine, for: host)
        case let .remove(rule):
            rules.remove(host: rule.host)
        }
        settings.siteEngineRules = rules
        page?.followSiteRules(registry: registry)
    }
}

extension EngineRegistry {
    /// An engine's name for menus and settings: its installed name, else a known engine's
    /// name, else its identifier.
    func displayName(for id: EngineID) -> String {
        if let descriptor = descriptor(for: id) {
            return descriptor.displayName
        }
        return id == .chromium ? "Chromium" : id.rawValue
    }
}

extension WebPage {
    /// The site rule changes the reload menus offer for this page's site.
    func siteRuleActions(registry: EngineRegistry) -> [SiteEngineRuleAction] {
        guard extensionBaseURL == nil else { return [] }
        return registry.choice(for: settingsApplier.settings).ruleActions(for: url ?? tabPage.url, installed: registry.descriptors.map(\.id))
    }

    /// Applies a site rule change from a reload menu, moving this page with it.
    func apply(_ action: SiteEngineRuleAction, registry: EngineRegistry) {
        action.apply(to: settingsApplier.settings, page: self, registry: registry)
    }
}
