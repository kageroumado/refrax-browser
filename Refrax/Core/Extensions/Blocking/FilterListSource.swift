import Foundation

/// A filter list Shields can subscribe to.
///
/// Built-in lists come from EasyList and uBlock Origin; users add their own by URL.
nonisolated struct FilterListSource: Codable, Identifiable, Hashable, Sendable {
    /// Unique identifier for this filter list.
    let id: String

    /// Human-readable name (e.g., "EasyList").
    let name: String

    /// URL to fetch the filter list from.
    var url: URL

    /// Category for organization in the UI.
    var category: FilterCategory

    /// Whether this filter list is currently enabled.
    var isEnabled: Bool

    /// How often to check for updates (in seconds).
    var updateFrequency: TimeInterval

    /// Last time this list was successfully downloaded.
    var lastUpdated: Date?

    /// Filters the last build read from this list (network and cosmetic).
    var ruleCount: Int?

    /// Why the last download failed; nil after a success.
    var lastError: String?

    /// For a custom list: whether the user trusted it to run scriptlets (`+js()`) in pages when
    /// adding it. Off unless chosen, so a list from anywhere cannot run code in every page.
    var allowsScriptlets: Bool?

    /// uBlock Origin's own lists may use the scriptlets uBO reserves for trusted lists
    /// (`trusted-click-element`, `trusted-set-cookie`, …), as uBO itself allows them.
    var isTrusted: Bool {
        Self.trustedPrefixes.contains { id.hasPrefix($0) }
    }

    /// Whether the list may contribute scriptlets: every built-in list, and a custom list the
    /// user trusted.
    var contributesScriptlets: Bool {
        category != .custom || allowsScriptlets == true
    }

    /// Lists are fetched only over HTTPS: their scriptlets and redirects become page code, so a
    /// network attacker must not be able to rewrite them.
    var isFetchable: Bool {
        url.scheme?.lowercased() == "https" && url.host() != nil
    }

    /// The URL a custom list is fetched from: `text` as an HTTPS URL, an `http://` address
    /// moved to `https://`, or nil for anything else.
    static func customListURL(from text: String) -> URL? {
        guard var components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              components.host?.isEmpty == false
        else { return nil }
        components.scheme = "https"
        if components.port == 80 {
            components.port = nil
        }
        return components.url
    }

    // MARK: - Categories

    /// Categories for filter lists.
    enum FilterCategory: String, Codable, CaseIterable, Sendable {
        case ads = "Ads"
        case privacy = "Privacy"
        case malware = "Malware"
        case annoyances = "Annoyances"
        case regional = "Regional"
        case custom = "Custom"
    }
}

// MARK: - Default Lists

nonisolated extension FilterListSource {
    /// Daily, the update interval of every list but uBO's quick fixes.
    static let dailyUpdates: TimeInterval = 86_400
    /// Quick fixes carry the day's anti-adblock and YouTube fixes; uBO refreshes it hourly.
    static let hourlyUpdates: TimeInterval = 3_600

    private static let trustedPrefixes = ["ublock-"]

    /// `saved` with each built-in list fetched from its current default URL and every
    /// built-in list it lacks appended, on or off as shipped.
    ///
    /// Saved lists keep the URL they were saved with, so a built-in list whose host moved, like
    /// EasyList Cookie leaving easylist.to, would otherwise fail every update.
    static func reconciled(_ saved: [FilterListSource]) -> [FilterListSource] {
        let builtIn = Dictionary(uniqueKeysWithValues: allAvailableLists.map { ($0.id, $0) })
        var lists = saved.map { list in
            guard let current = builtIn[list.id] else { return list }
            var list = list
            list.url = current.url
            list.updateFrequency = current.updateFrequency
            return list
        }
        let savedIDs = Set(saved.map(\.id))
        lists += allAvailableLists.filter { !savedIDs.contains($0.id) }
        return lists
    }

    private static func list(
        _ id: String,
        _ name: String,
        _ url: StaticString,
        _ category: FilterCategory,
        enabled: Bool = true,
        updateFrequency: TimeInterval = dailyUpdates,
    ) -> FilterListSource {
        FilterListSource(
            id: id,
            name: name,
            url: URL.staticRequired(url),
            category: category,
            isEnabled: enabled,
            updateFrequency: updateFrequency,
        )
    }

    /// Lists on by default: uBlock Origin's default set, with its unbreak and quick-fix lists
    /// that keep the others from breaking sites.
    static let defaultLists: [FilterListSource] = [
        list("easylist", "EasyList", "https://easylist.to/easylist/easylist.txt", .ads),
        list("easyprivacy", "EasyPrivacy", "https://easylist.to/easylist/easyprivacy.txt", .privacy),
        list("ublock-filters", "uBlock filters", "https://ublockorigin.github.io/uAssets/filters/filters.txt", .ads),
        list("ublock-privacy", "uBlock filters – Privacy", "https://ublockorigin.github.io/uAssets/filters/privacy.txt", .privacy),
        list("ublock-badware", "uBlock filters – Badware", "https://ublockorigin.github.io/uAssets/filters/badware.txt", .malware),
        list("ublock-unbreak", "uBlock filters – Unbreak", "https://ublockorigin.github.io/uAssets/filters/unbreak.txt", .ads),
        list(
            "ublock-quick-fixes", "uBlock filters – Quick fixes",
            "https://ublockorigin.github.io/uAssets/filters/quick-fixes.txt", .ads,
            updateFrequency: hourlyUpdates,
        ),
        list(
            "ublock-annoyances", "uBlock filters – Annoyances (Cookies)",
            "https://ublockorigin.github.io/uAssets/filters/annoyances-cookies.txt", .annoyances,
        ),
        // easylist.to no longer serves this list; uBlock Origin's assets mirror it.
        list("easylist-cookie", "EasyList Cookie", "https://ublockorigin.github.io/uAssets/thirdparties/easylist-cookies.txt", .annoyances),
        list(
            "ublock-annoyances-other", "uBlock filters – Annoyances (Other)",
            "https://ublockorigin.github.io/uAssets/filters/annoyances-others.txt", .annoyances,
        ),
    ]

    /// Lists users can turn on.
    static let additionalLists: [FilterListSource] = [
        list("malware-domains", "Malware Domain List", "https://malware-filter.gitlab.io/malware-filter/urlhaus-filter.txt", .malware, enabled: false),
        list("fanboy-social", "Fanboy's Social Blocking List", "https://easylist.to/easylist/fanboy-social.txt", .annoyances, enabled: false),
        list("easylist-germany", "EasyList Germany", "https://easylist.to/easylistgermany/easylistgermany.txt", .regional, enabled: false),
        list("liste-fr", "Liste FR", "https://easylist.to/easylist/liste_fr.txt", .regional, enabled: false),
    ]

    /// All available filter lists.
    static let allAvailableLists: [FilterListSource] = defaultLists + additionalLists
}
