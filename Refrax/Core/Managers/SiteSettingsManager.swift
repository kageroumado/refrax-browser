import Foundation
import Observation
import SwiftData

/// Manages per-site settings with efficient caching and domain lookup.
///
/// `SiteSettingsManager` provides fast access to ``SiteSettings`` for domains,
/// caching frequently accessed settings in memory to minimize database queries.
///
/// ## Domain Resolution
///
/// When looking up settings, the manager tries:
/// 1. Exact domain match (e.g., "app.example.com")
/// 2. Parent domain match (e.g., "example.com")
///
/// ## Caching
///
/// Settings are cached in memory after first access. The cache is invalidated
/// when settings are updated or deleted.
///
/// ## Usage
///
/// ```swift
/// // Get existing settings (may return nil)
/// if let settings = siteSettingsManager.settings(for: "example.com") {
///     print("Zoom: \(settings.pageZoom)%")
/// }
///
/// // Get or create settings
/// let settings = siteSettingsManager.settingsOrCreate(for: "example.com")
/// settings.pageZoom = 125
/// siteSettingsManager.save(settings)
/// ```
@Observable
final class SiteSettingsManager {
    // MARK: - Dependencies

    private let modelContext: ModelContext

    // MARK: - Cache

    /// In-memory cache for fast lookups.
    ///
    /// Key is the exact domain string from the query (may be subdomain).
    /// Value is the settings and the actual domain the settings belong to.
    ///
    /// - Note: Marked `@ObservationIgnored` because cache mutations are internal
    ///   implementation details that should not trigger view updates.
    @ObservationIgnored
    private var cache: [String: CachedSettings] = [:]

    /// Cache entry containing settings and the domain they actually belong to.
    private struct CachedSettings {
        let settings: SiteSettings
        /// The actual domain the settings are stored under (may differ from lookup key).
        let storedDomain: String
    }

    /// Domains known to have no settings (negative cache).
    ///
    /// Prevents repeated database queries for domains without settings.
    ///
    /// - Note: Marked `@ObservationIgnored` because negative cache mutations are
    ///   internal implementation details that should not trigger view updates.
    @ObservationIgnored
    private var noSettingsDomains: Set<String> = []

    // MARK: - Save Debouncing

    private let saver: DebouncedModelContextSaver

    // MARK: - Initialization

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.saver = DebouncedModelContextSaver(
            modelContext: modelContext,
            debounceDelay: 2.1,
            logCategory: Logger.data,
        )
    }

    // MARK: - Lookup

    /// Gets settings for a domain, if they exist.
    ///
    /// Checks cache first, then queries database. Returns nil if no settings
    /// exist for the domain or any parent domain.
    ///
    /// - Parameter domain: The domain to look up (e.g., "example.com").
    /// - Returns: Settings if found, nil otherwise.
    func settings(for domain: String) -> SiteSettings? {
        let normalized = domain.lowercased()

        // Check cache
        if let cached = cache[normalized] {
            return cached.settings
        }

        // Check negative cache
        if noSettingsDomains.contains(normalized) {
            return nil
        }

        // Query database for exact match
        if let settings = fetchSettings(for: normalized) {
            cache[normalized] = CachedSettings(settings: settings, storedDomain: normalized)
            return settings
        }

        // Try parent domain
        if let parentDomain = parentDomain(of: normalized),
           let settings = fetchSettings(for: parentDomain) {
            // Cache under the original domain, but track the actual stored domain
            cache[normalized] = CachedSettings(settings: settings, storedDomain: parentDomain)
            return settings
        }

        // Mark as having no settings
        noSettingsDomains.insert(normalized)
        return nil
    }

    /// Gets or creates settings for a domain.
    ///
    /// If no settings exist, creates a new ``SiteSettings`` with defaults.
    /// The new settings are inserted into the database.
    ///
    /// - Parameter domain: The domain to get/create settings for.
    /// - Returns: Existing or newly created settings.
    func settingsOrCreate(for domain: String) -> SiteSettings {
        let normalized = domain.lowercased()

        // Return existing
        if let existing = settings(for: normalized) {
            return existing
        }

        // Create new
        let settings = SiteSettings(domain: normalized)
        modelContext.insert(settings)
        cache[normalized] = CachedSettings(settings: settings, storedDomain: normalized)
        noSettingsDomains.remove(normalized)

        scheduleSave()
        Logger.debug("Created site settings for: \(normalized)", category: Logger.data)

        return settings
    }

    /// Gets settings for a URL.
    ///
    /// Extracts the registrable domain from the URL and looks up settings.
    ///
    /// - Parameter url: The URL to look up settings for.
    /// - Returns: Settings if found, nil otherwise.
    func settings(for url: URL) -> SiteSettings? {
        guard let domain = extractDomain(from: url) else { return nil }
        return settings(for: domain)
    }

    /// Gets or creates settings for a URL.
    ///
    /// - Parameter url: The URL to get/create settings for.
    /// - Returns: Existing or newly created settings.
    func settingsOrCreate(for url: URL) -> SiteSettings? {
        guard let domain = extractDomain(from: url) else { return nil }
        return settingsOrCreate(for: domain)
    }

    /// Fetches all site settings with explicit GPC header overrides.
    ///
    /// This is used by Settings to query SwiftData directly instead of relying
    /// on bundled JSON lists, keeping GPC allow/block rules editable and
    /// persistent for users.
    func fetchSitesWithGPCHeaderOverrides() -> [SiteSettings] {
        let defaultOverride = GPCHeaderOverride.useAllowlist.rawValue
        let descriptor = FetchDescriptor<SiteSettings>(
            predicate: #Predicate {
                $0.gpcHeaderOverrideRaw != defaultOverride
            },
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Modification

    /// Marks settings as modified and schedules a save.
    ///
    /// Call this after modifying any properties on the settings object.
    ///
    /// - Parameter settings: The modified settings.
    func save(_ settings: SiteSettings) {
        settings.markModified()
        scheduleSave()
    }

    /// Deletes settings for a domain.
    ///
    /// Also invalidates any cache entries that reference this domain's settings
    /// (e.g., subdomain lookups that inherited from this domain).
    ///
    /// - Parameter domain: The domain to delete settings for.
    func delete(for domain: String) {
        let normalized = domain.lowercased()

        // Get settings from cache or database
        let settingsToDelete: SiteSettings? = if let cached = cache[normalized] {
            cached.settings
        } else {
            fetchSettings(for: normalized)
        }

        guard let settings = settingsToDelete else {
            return
        }

        modelContext.delete(settings)

        // Invalidate all cache entries that reference this domain
        // (including subdomains that inherited from it)
        invalidateCacheEntries(referencing: normalized)
        noSettingsDomains.insert(normalized)

        scheduleSave()
        Logger.debug("Deleted site settings for: \(normalized)", category: Logger.data)
    }

    /// Deletes settings for multiple domains.
    ///
    /// More efficient than calling `delete(for:)` repeatedly as it batches
    /// the database operations and performs a single save.
    ///
    /// - Parameter domains: The domains to delete settings for.
    func delete(for domains: [String]) {
        guard !domains.isEmpty else { return }

        for domain in domains {
            let normalized = domain.lowercased()

            let settingsToDelete: SiteSettings? = if let cached = cache[normalized] {
                cached.settings
            } else {
                fetchSettings(for: normalized)
            }

            guard let settings = settingsToDelete else {
                continue
            }

            modelContext.delete(settings)
            invalidateCacheEntries(referencing: normalized)
            noSettingsDomains.insert(normalized)
        }

        scheduleSave()
        Logger.debug("Deleted site settings for \(domains.count) domains", category: Logger.data)
    }

    /// Resets a site's settings to defaults without deleting the entry.
    ///
    /// This keeps the domain in the database but clears all customizations.
    ///
    /// - Parameter domain: The domain to reset settings for.
    func resetToDefaults(for domain: String) {
        let normalized = domain.lowercased()
        guard let settings = settings(for: normalized) else { return }

        // Reset content settings
        settings.pageZoom = 100
        settings.useReaderWhenAvailable = false
        settings.enableContentBlockers = true
        settings.allowJavaScript = true

        // Reset media/window settings
        settings.autoPlayPolicy = .stopMediaWithSound
        settings.popUpPolicy = .blockAndNotify
        settings.gpcHeaderOverride = .useAllowlist
        settings.disableAutoConsent = false

        // Reset permissions
        settings.cameraPermission = .ask
        settings.microphonePermission = .ask
        settings.screenSharingPermission = .ask
        settings.locationPermission = .ask
        settings.deviceSensorPermission = .ask
        settings.websiteColoringPolicy = .useDefault
        settings.neverSavePasswords = false

        save(settings)
        Logger.debug("Reset site settings to defaults for: \(normalized)", category: Logger.data)
    }

    /// Resets settings for multiple domains to defaults.
    ///
    /// - Parameter domains: The domains to reset settings for.
    func resetToDefaults(for domains: [String]) {
        guard !domains.isEmpty else { return }

        for domain in domains {
            let normalized = domain.lowercased()
            guard let settings = settings(for: normalized) else { continue }

            settings.pageZoom = 100
            settings.useReaderWhenAvailable = false
            settings.enableContentBlockers = true
            settings.allowJavaScript = true
            settings.autoPlayPolicy = .stopMediaWithSound
            settings.popUpPolicy = .blockAndNotify
            settings.gpcHeaderOverride = .useAllowlist
            settings.disableAutoConsent = false
            settings.cameraPermission = .ask
            settings.microphonePermission = .ask
            settings.screenSharingPermission = .ask
            settings.locationPermission = .ask
            settings.deviceSensorPermission = .ask
            settings.websiteColoringPolicy = .useDefault
            settings.neverSavePasswords = false
            settings.markModified()
        }

        scheduleSave()
        Logger.debug("Reset site settings for \(domains.count) domains", category: Logger.data)
    }

    /// Invalidates all cache entries that reference a specific stored domain.
    ///
    /// Called when settings are deleted or modified to ensure subdomain lookups
    /// don't return stale data.
    private func invalidateCacheEntries(referencing storedDomain: String) {
        let keysToRemove = cache.filter { $0.value.storedDomain == storedDomain }.map(\.key)
        for key in keysToRemove {
            cache.removeValue(forKey: key)
        }
    }

    /// Clears the in-memory cache.
    ///
    /// Call this if settings may have been modified externally.
    func clearCache() {
        cache.removeAll()
        noSettingsDomains.removeAll()
    }

    // MARK: - Private

    /// Fetches settings from database.
    private func fetchSettings(for domain: String) -> SiteSettings? {
        let descriptor = FetchDescriptor<SiteSettings>(
            predicate: #Predicate { $0.domain == domain },
        )

        return try? modelContext.fetch(descriptor).first
    }

    /// Extracts parent domain (removes leftmost subdomain).
    ///
    /// Uses PublicSuffixList to ensure we don't return a public suffix as a parent.
    /// For example, `app.example.co.uk` → `example.co.uk`, but `example.co.uk` → `nil`.
    private func parentDomain(of domain: String) -> String? {
        let parts = domain.split(separator: ".")
        guard parts.count > 2 else { return nil }

        let candidate = parts.dropFirst().joined(separator: ".")

        // Verify the candidate is a registrable domain (not a public suffix)
        // If PSL returns the same domain, it's valid; if nil, it's a public suffix
        if let registrable = PublicSuffixList.shared.registrableDomain(for: candidate),
           registrable == candidate {
            return candidate
        }

        return nil
    }

    /// Extracts registrable domain from URL.
    private func extractDomain(from url: URL) -> String? {
        // Use PublicSuffixList if available for proper eTLD+1 extraction
        if let registrable = url.registrableDomain {
            return registrable.lowercased()
        }
        return url.host?.lowercased()
    }

    /// Schedules a debounced save.
    private func scheduleSave() {
        saver.scheduleSave()
    }

    // MARK: - Queries

    /// All domains with saved settings.
    var allDomains: [String] {
        let descriptor = FetchDescriptor<SiteSettings>(
            sortBy: [SortDescriptor(\.domain)],
        )
        return (try? modelContext.fetch(descriptor).map(\.domain)) ?? []
    }

    /// Number of sites with custom settings.
    var siteCount: Int {
        let descriptor = FetchDescriptor<SiteSettings>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    /// Whether there are no sites with custom settings.
    var isEmpty: Bool {
        siteCount == 0
    }

    /// Fetches site settings sorted by domain with optional limit.
    ///
    /// - Parameters:
    ///   - limit: Maximum number of results to return. Defaults to 500.
    /// - Note: This performs a database fetch. Cache the result if needed repeatedly.
    /// - Returns: Site settings sorted alphabetically by domain.
    func fetchAllSiteSettings(limit: Int = 500) -> [SiteSettings] {
        var descriptor = FetchDescriptor<SiteSettings>(
            sortBy: [SortDescriptor(\.domain)],
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Fetches sites with JavaScript explicitly enabled (for whitelist display).
    ///
    /// Returns settings where `allowJavaScript` is true, useful for showing
    /// which sites are whitelisted when global JavaScript is disabled.
    ///
    /// - Note: This performs a database fetch. Cache the result if needed repeatedly.
    /// - Returns: Sites with JavaScript enabled, sorted by domain.
    func fetchSitesWithJavaScriptEnabled() -> [SiteSettings] {
        let descriptor = FetchDescriptor<SiteSettings>(
            predicate: #Predicate { $0.allowJavaScript == true },
            sortBy: [SortDescriptor(\.domain)],
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Fetches sites with JavaScript explicitly disabled.
    ///
    /// Returns settings where `allowJavaScript` is false.
    ///
    /// - Note: This performs a database fetch. Cache the result if needed repeatedly.
    /// - Returns: Sites with JavaScript disabled, sorted by domain.
    func fetchSitesWithJavaScriptDisabled() -> [SiteSettings] {
        let descriptor = FetchDescriptor<SiteSettings>(
            predicate: #Predicate { $0.allowJavaScript == false },
            sortBy: [SortDescriptor(\.domain)],
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
