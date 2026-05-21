import Foundation
import Observation
import WebKit

/// Manages cookie inspection and editing across all data stores.
///
/// `CookieInspectorManager` provides a unified view of all cookies across:
/// - The default shared data store
/// - Per-space isolated data stores
/// - Private (non-persistent) data stores
///
/// It supports viewing, editing, adding, and deleting cookies, with filtering
/// by domain, data store, or search text.
@Observable
final class CookieInspectorManager {
    // MARK: - State

    /// All loaded cookies grouped by their source data store.
    private(set) var cookiesByStore: [DataStoreInfo: [HTTPCookie]] = [:] {
        didSet { invalidateCaches() }
    }

    // MARK: - Cached Properties

    /// Cached flattened and sorted cookies. Invalidated when `cookiesByStore` changes.
    private var _allCookiesCache: [CookieEntry]?

    /// Cached sorted data stores. Invalidated when `cookiesByStore` changes.
    private var _allStoresCache: [DataStoreInfo]?

    /// Cached unique domains. Invalidated when `cookiesByStore` changes.
    private var _allDomainsCache: [String]?

    private func invalidateCaches() {
        _allCookiesCache = nil
        _allStoresCache = nil
        _allDomainsCache = nil
    }

    /// Flattened list of all cookies for display.
    var allCookies: [CookieEntry] {
        if let cached = _allCookiesCache { return cached }
        let result = cookiesByStore.flatMap { storeInfo, cookies in
            cookies.map { CookieEntry(cookie: $0, storeInfo: storeInfo) }
        }.sorted { $0.cookie.domain < $1.cookie.domain }
        _allCookiesCache = result
        return result
    }

    /// Cookies filtered by current search and filter criteria.
    var filteredCookies: [CookieEntry] {
        var result = allCookies

        // Filter by selected store
        if let selectedStore = selectedStoreFilter {
            result = result.filter { $0.storeInfo == selectedStore }
        }

        // Filter by selected domain
        if let selectedDomain = selectedDomainFilter {
            result = result.filter { $0.cookie.matchesDomain(selectedDomain) }
        }

        // Filter by search text
        if !searchText.isEmpty {
            result = result.filter {
                $0.cookie.name.localizedCaseInsensitiveContains(searchText) ||
                    $0.cookie.value.localizedCaseInsensitiveContains(searchText) ||
                    $0.cookie.domain.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    /// All unique domains across all cookies.
    var allDomains: [String] {
        if let cached = _allDomainsCache { return cached }
        let result = Array(Set(allCookies.map(\.cookie.domain))).sorted()
        _allDomainsCache = result
        return result
    }

    /// All data stores that have been loaded.
    var allStores: [DataStoreInfo] {
        if let cached = _allStoresCache { return cached }
        let result = Array(cookiesByStore.keys).sorted { $0.displayName < $1.displayName }
        _allStoresCache = result
        return result
    }

    /// Search text for filtering.
    var searchText: String = ""

    /// Filter by specific data store (nil = all stores).
    var selectedStoreFilter: DataStoreInfo?

    /// Filter by specific domain (nil = all domains).
    var selectedDomainFilter: String?

    /// Currently selected cookie for editing.
    var selectedCookie: CookieEntry?

    /// Whether loading is in progress.
    var isLoading = false

    /// Total cookie count across all stores.
    var totalCookieCount: Int {
        cookiesByStore.values.reduce(0) { $0 + $1.count }
    }

    // MARK: - Dependencies

    private unowned let spaceDataStoreManager: SpaceDataStoreManager

    // MARK: - Initialization

    init(spaceDataStoreManager: SpaceDataStoreManager) {
        self.spaceDataStoreManager = spaceDataStoreManager
    }

    // MARK: - Loading

    /// Loads all cookies from all data stores.
    func loadAllCookies() async {
        isLoading = true
        defer { isLoading = false }

        var newCookiesByStore: [DataStoreInfo: [HTTPCookie]] = [:]

        // Load from default store
        let defaultStore = WKWebsiteDataStore.default()
        let defaultCookies = await defaultStore.httpCookieStore.allCookies()
        if !defaultCookies.isEmpty {
            newCookiesByStore[.default] = defaultCookies
        }

        // Load from all persistent space stores
        let spaceIdentifiers = await spaceDataStoreManager.fetchAllDataStoreIdentifiers()
        for identifier in spaceIdentifiers {
            let store = spaceDataStoreManager.dataStore(forSpaceID: identifier)
            let cookies = await store.httpCookieStore.allCookies()
            if !cookies.isEmpty {
                newCookiesByStore[.space(id: identifier)] = cookies
            }
        }

        // Note: Private stores are non-persistent and per-session,
        // we don't enumerate them here as they're ephemeral

        cookiesByStore = newCookiesByStore

        // Clear selection if cookie no longer exists
        if let selected = selectedCookie,
           !filteredCookies.contains(where: { $0.id == selected.id }) {
            selectedCookie = nil
        }
    }

    // MARK: - CRUD Operations

    /// Deletes a cookie.
    func deleteCookie(_ entry: CookieEntry) async {
        guard let store = dataStore(for: entry.storeInfo) else { return }

        isLoading = true
        defer { isLoading = false }

        await store.httpCookieStore.deleteCookie(entry.cookie)

        if selectedCookie?.id == entry.id {
            selectedCookie = nil
        }

        await loadAllCookies()
    }

    /// Deletes all cookies matching the current filter.
    func deleteFilteredCookies() async {
        isLoading = true
        defer { isLoading = false }

        for entry in filteredCookies {
            if let store = dataStore(for: entry.storeInfo) {
                await store.httpCookieStore.deleteCookie(entry.cookie)
            }
        }

        selectedCookie = nil
        await loadAllCookies()
    }

    /// Deletes all cookies from a specific domain.
    func deleteCookies(forDomain domain: String) async {
        isLoading = true
        defer { isLoading = false }

        for (storeInfo, cookies) in cookiesByStore {
            guard let store = dataStore(for: storeInfo) else { continue }
            for cookie in cookies where cookie.matchesDomain(domain) {
                await store.httpCookieStore.deleteCookie(cookie)
            }
        }

        await loadAllCookies()
    }

    /// Deletes all cookies from a specific data store.
    func deleteCookies(forStore storeInfo: DataStoreInfo) async {
        guard let store = dataStore(for: storeInfo),
              let cookies = cookiesByStore[storeInfo]
        else { return }

        isLoading = true
        defer { isLoading = false }

        for cookie in cookies {
            await store.httpCookieStore.deleteCookie(cookie)
        }

        await loadAllCookies()
    }

    /// Updates a cookie with new values.
    func updateCookie(_ entry: CookieEntry, with model: CookieEditModel) async {
        guard let store = dataStore(for: entry.storeInfo) else { return }

        isLoading = true
        defer { isLoading = false }

        // Delete original
        await store.httpCookieStore.deleteCookie(entry.cookie)

        // Create new cookie with updated values
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: model.name,
            .value: model.value,
            .domain: entry.cookie.domain,
            .path: model.path,
        ]

        if let expires = model.expiresDate {
            properties[.expires] = expires
        }
        if model.isSecure {
            properties[.secure] = "TRUE"
        }
        if model.isHttpOnly {
            properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        }
        properties[.sameSitePolicy] = model.sameSite.cookieValue

        if let newCookie = HTTPCookie(properties: properties) {
            await store.httpCookieStore.setCookie(newCookie)
        }

        await loadAllCookies()
    }

    /// Adds a new cookie to a specific data store.
    func addCookie(_ model: CookieEditModel, to storeInfo: DataStoreInfo) async {
        guard let store = dataStore(for: storeInfo) else { return }

        isLoading = true
        defer { isLoading = false }

        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: model.name,
            .value: model.value,
            .domain: model.domain,
            .path: model.path,
        ]

        if let expires = model.expiresDate {
            properties[.expires] = expires
        }
        if model.isSecure {
            properties[.secure] = "TRUE"
        }
        if model.isHttpOnly {
            properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
        }
        properties[.sameSitePolicy] = model.sameSite.cookieValue

        if let cookie = HTTPCookie(properties: properties) {
            await store.httpCookieStore.setCookie(cookie)
        }

        await loadAllCookies()
    }

    // MARK: - Helpers

    private func dataStore(for storeInfo: DataStoreInfo) -> WKWebsiteDataStore? {
        switch storeInfo {
        case .default:
            .default()
        case let .space(id):
            spaceDataStoreManager.dataStore(forSpaceID: id)
        }
    }
}

// MARK: - Supporting Types

/// Identifies which data store a cookie belongs to.
enum DataStoreInfo: Hashable, Identifiable {
    case `default`
    case space(id: UUID)

    var id: String {
        switch self {
        case .default: "default"
        case let .space(id): "space-\(id)"
        }
    }

    var displayName: String {
        switch self {
        case .default: "Default"
        case let .space(id): "Space \(id.uuidString.prefix(8))"
        }
    }
}

/// A cookie with its source data store information.
struct CookieEntry: Identifiable {
    let cookie: HTTPCookie
    let storeInfo: DataStoreInfo

    var id: String { "\(storeInfo.id)_\(cookie.domain)_\(cookie.name)_\(cookie.path)" }

    func matchesDomain(_ domain: String) -> Bool {
        cookie.matchesDomain(domain)
    }
}

/// Editable model for creating or modifying cookies.
struct CookieEditModel {
    /// Default expiration offset: 30 days in seconds.
    static let defaultExpirationInterval: TimeInterval = 86_400 * 30

    var name: String
    var value: String
    var domain: String
    var path: String
    var expiresDate: Date?
    var isSecure: Bool
    var isHttpOnly: Bool
    var sameSite: SameSitePolicy

    enum SameSitePolicy: String, CaseIterable, Identifiable {
        case strict = "Strict"
        case lax = "Lax"
        case none = "None"

        var id: String { rawValue }

        var cookieValue: String { rawValue.lowercased() }

        init(from policy: HTTPCookieStringPolicy?) {
            switch policy?.rawValue.lowercased() {
            case "strict": self = .strict
            case "none": self = .none
            default: self = .lax
            }
        }
    }

    init(from cookie: HTTPCookie) {
        self.name = cookie.name
        self.value = cookie.value
        self.domain = cookie.domain
        self.path = cookie.path
        self.expiresDate = cookie.expiresDate
        self.isSecure = cookie.isSecure
        self.isHttpOnly = cookie.isHTTPOnly
        self.sameSite = SameSitePolicy(from: cookie.sameSitePolicy)
    }

    init(domain: String = "") {
        self.name = ""
        self.value = ""
        self.domain = domain
        self.path = "/"
        self.expiresDate = nil
        self.isSecure = false
        self.isHttpOnly = false
        self.sameSite = .lax
    }

    var isValid: Bool { !name.isEmpty && !value.isEmpty && !domain.isEmpty }

    /// Default expiration date (30 days from now).
    static var defaultExpirationDate: Date {
        Date().addingTimeInterval(defaultExpirationInterval)
    }
}

// MARK: - HTTPCookie Extensions

extension HTTPCookie {
    /// Whether this cookie's domain matches the given domain.
    ///
    /// Handles exact matches, leading-dot prefixes, and subdomain matching.
    func matchesDomain(_ targetDomain: String) -> Bool {
        if domain == targetDomain { return true }
        if domain == ".\(targetDomain)" { return true }
        if domain.hasPrefix("."), targetDomain.hasSuffix(domain) { return true }
        if targetDomain.hasSuffix(".\(domain)") { return true }
        return false
    }

    var expirationDescription: String {
        if isSessionOnly { return "Session" }
        guard let expires = expiresDate else { return "Session" }

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: Date(), to: expires)

        if let years = components.year, years > 0 {
            return years == 1 ? "1 year" : "\(years) years"
        }
        if let months = components.month, months > 0 {
            return months == 1 ? "1 month" : "\(months) months"
        }
        if let days = components.day, days > 0 {
            return days == 1 ? "1 day" : "\(days) days"
        }
        if let hours = components.hour, hours > 0 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }
        return "< 1 hour"
    }

    var truncatedValue: String {
        value.count > 40 ? String(value.prefix(40)) + "..." : value
    }
}
