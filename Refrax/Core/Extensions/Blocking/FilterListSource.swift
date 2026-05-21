import Foundation

/// Represents a filter list source URL for content blocking.
///
/// Filter lists can come from various sources like EasyList, EasyPrivacy,
/// uBlock filters, or user-added custom lists. Each list has an update
/// frequency and category for organization.
nonisolated struct FilterListSource: Codable, Identifiable, Hashable, Sendable {
    /// Unique identifier for this filter list.
    let id: String

    /// Human-readable name (e.g., "EasyList").
    let name: String

    /// URL to fetch the filter list from.
    let url: URL

    /// Category for organization in the UI.
    var category: FilterCategory

    /// Whether this filter list is currently enabled.
    var isEnabled: Bool

    /// How often to check for updates (in seconds).
    var updateFrequency: TimeInterval

    /// Last time this list was successfully updated.
    var lastUpdated: Date?

    /// Number of rules parsed from this list.
    var ruleCount: Int?

    /// Number of WebKit rule list chunks this list compiled to.
    var chunkCount: Int?

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
    /// Default filter lists.
    ///
    /// Includes EasyList, EasyPrivacy, and uBlock's filter lists for
    /// comprehensive ad blocking and privacy protection.
    static let defaultLists: [FilterListSource] = [
        FilterListSource(
            id: "easylist",
            name: "EasyList",
            url: URL.staticRequired("https://easylist.to/easylist/easylist.txt"),
            category: .ads,
            isEnabled: true,
            updateFrequency: 86_400, // 24 hours
            lastUpdated: nil,
            ruleCount: nil,
            chunkCount: nil,
        ),
        FilterListSource(
            id: "easyprivacy",
            name: "EasyPrivacy",
            url: URL.staticRequired("https://easylist.to/easylist/easyprivacy.txt"),
            category: .privacy,
            isEnabled: true,
            updateFrequency: 86_400,
            lastUpdated: nil,
            ruleCount: nil,
            chunkCount: nil,
        ),
        FilterListSource(
            id: "ublock-filters",
            name: "uBlock filters",
            url: URL.staticRequired("https://ublockorigin.github.io/uAssets/filters/filters.txt"),
            category: .ads,
            isEnabled: true,
            updateFrequency: 86_400,
            lastUpdated: nil,
            ruleCount: nil,
            chunkCount: nil,
        ),
        FilterListSource(
            id: "ublock-privacy",
            name: "uBlock filters – Privacy",
            url: URL.staticRequired("https://ublockorigin.github.io/uAssets/filters/privacy.txt"),
            category: .privacy,
            isEnabled: true,
            updateFrequency: 86_400,
            lastUpdated: nil,
            ruleCount: nil,
            chunkCount: nil,
        ),
        FilterListSource(
            id: "ublock-badware",
            name: "uBlock filters – Badware",
            url: URL.staticRequired("https://ublockorigin.github.io/uAssets/filters/badware.txt"),
            category: .malware,
            isEnabled: true,
            updateFrequency: 86_400,
            lastUpdated: nil,
            ruleCount: nil,
            chunkCount: nil,
        ),
        FilterListSource(
            id: "ublock-annoyances",
            name: "uBlock filters – Annoyances (Cookies)",
            url: URL.staticRequired("https://ublockorigin.github.io/uAssets/filters/annoyances-cookies.txt"),
            category: .annoyances,
            isEnabled: true,
            updateFrequency: 86_400,
            lastUpdated: nil,
            ruleCount: nil,
            chunkCount: nil,
        ),
        FilterListSource(
            id: "easylist-cookie",
            name: "EasyList Cookie",
            url: URL.staticRequired("https://easylist.to/easylist/easylist-cookie.txt"),
            category: .annoyances,
            isEnabled: true,
            updateFrequency: 86_400,
            lastUpdated: nil,
            ruleCount: nil,
            chunkCount: nil,
        ),
        FilterListSource(
            id: "ublock-annoyances-other",
            name: "uBlock filters – Annoyances (Other)",
            url: URL.staticRequired("https://ublockorigin.github.io/uAssets/filters/annoyances-others.txt"),
            category: .annoyances,
            isEnabled: true,
            updateFrequency: 86_400,
            lastUpdated: nil,
            ruleCount: nil,
            chunkCount: nil,
        ),
    ]

    /// Additional filter lists that users can enable.
    static let additionalLists: [FilterListSource] = [
        // Malware protection
        FilterListSource(
            id: "malware-domains",
            name: "Malware Domain List",
            url: URL.staticRequired("https://malware-filter.gitlab.io/malware-filter/urlhaus-filter.txt"),
            category: .malware,
            isEnabled: false,
            updateFrequency: 86_400,
            lastUpdated: nil,
            ruleCount: nil,
            chunkCount: nil,
        ),

        // Social
        FilterListSource(
            id: "fanboy-social",
            name: "Fanboy's Social Blocking List",
            url: URL.staticRequired("https://easylist.to/easylist/fanboy-social.txt"),
            category: .annoyances,
            isEnabled: false,
            updateFrequency: 86_400,
            lastUpdated: nil,
            ruleCount: nil,
            chunkCount: nil,
        ),

        // Regional
        FilterListSource(
            id: "easylist-germany",
            name: "EasyList Germany",
            url: URL.staticRequired("https://easylist.to/easylistgermany/easylistgermany.txt"),
            category: .regional,
            isEnabled: false,
            updateFrequency: 86_400,
            lastUpdated: nil,
            ruleCount: nil,
            chunkCount: nil,
        ),
        FilterListSource(
            id: "liste-fr",
            name: "Liste FR",
            url: URL.staticRequired("https://easylist.to/easylist/liste_fr.txt"),
            category: .regional,
            isEnabled: false,
            updateFrequency: 86_400,
            lastUpdated: nil,
            ruleCount: nil,
            chunkCount: nil,
        ),
    ]

    /// All available filter lists.
    static let allAvailableLists: [FilterListSource] = defaultLists + additionalLists
}
