import Foundation

// MARK: - Research Notes

//
// ## Safari's Approach to Quirks Database
//
// Safari uses "snapshots" of the password-rules.json database:
// - Fetched once on launch, then periodically (every 24 hours)
// - Cached persistently to avoid network dependency
// - Database is small (~200KB) so disk storage is reasonable
//
// ## Apple password-manager-resources Repository
//
// Source: https://github.com/apple/password-manager-resources
//
// Key points from README:
// - Rules apply to a domain and all subdomains (e.g., example.com covers *.example.com)
// - Subdomains can have their own specific rules
// - `exact-domain-match-only` property restricts rules to specific domains
// - Password managers should contribute discovered quirks back
//
// ## Security Best Practices
//
// Use ATS-default HTTPS validation for fetching the public quirks database.
//
// ## Database Format (password-rules.json)
//
// ```json
// {
//   "example.com": {
//     "password-rules": "minlength: 8; maxlength: 20; required: upper, lower, digit"
//   }
// }
// ```

/// Manages website-specific password requirements from Apple's quirks database.
///
/// Apple maintains a public database of password rules for websites that have
/// non-standard requirements. This manager fetches and caches that database
/// to generate compatible passwords.
///
/// ## Caching Strategy (Safari-style "Snapshots")
///
/// - **Disk persistence**: Database cached to disk for offline access
/// - **Memory cache**: Parsed rules kept in RAM for fast lookups
/// - **Background refresh**: Updates every 24 hours when app is active
/// - **Fallback chain**: Memory → Disk → Network
///
/// ## Security Considerations
///
/// - **System TLS trust**: Uses ATS-default validation for HTTPS
/// - **HTTPS only**: Database fetched over secure connection
/// - **Size limit**: Rejects responses larger than 1MB
/// - **Validated JSON**: Strict parsing rejects malformed data
/// - **Minimum entropy**: PasswordGenerator enforces minimum length regardless of quirks
///
/// ## Usage
/// ```swift
/// // Prefetch on app launch
/// await PasswordQuirksManager.shared.prefetch()
///
/// // Look up rules for password generation
/// let rules = await PasswordQuirksManager.shared.rules(for: "bankofamerica.com")
/// let password = PasswordGenerator.generateStrongPassword(rules: rules)
/// ```
actor PasswordQuirksManager {
    // MARK: - Singleton

    /// Shared instance for app-wide access.
    static let shared = PasswordQuirksManager()

    // MARK: - Configuration

    /// URL to Apple's password rules database.
    private static let quirksURL = URL(
        string: "https://raw.githubusercontent.com/apple/password-manager-resources/main/quirks/password-rules.json",
    )!

    /// How long to cache the database before refreshing (24 hours).
    private static let cacheExpiration: TimeInterval = 24 * 60 * 60

    /// Maximum size of the quirks database to accept (1 MB).
    /// Current database is ~200KB, so 1MB provides headroom for growth.
    private static let maxDatabaseSize = 1_000_000

    /// Filename for disk cache.
    private static let cacheFilename = "password-rules-cache.json"

    // MARK: - State

    private var rulesByDomain: [String: PasswordRules] = [:]
    private var lastFetchDate: Date?
    private var isFetching = false

    // MARK: - Public API

    /// Prefetches the quirks database for faster password generation.
    ///
    /// Call this on app launch to ensure the database is ready when needed.
    /// Uses cached data if available and not expired.
    func prefetch() async {
        await ensureDatabaseLoaded()
    }

    /// Gets password rules for a specific domain.
    ///
    /// Returns cached rules if available, otherwise fetches from Apple's database.
    /// Falls back to `nil` if the domain has no special requirements.
    ///
    /// - Parameter domain: The domain to look up (e.g., "bankofamerica.com").
    /// - Returns: Password rules for the domain, or `nil` for default behavior.
    func rules(for domain: String) async -> PasswordRules? {
        let normalizedDomain = normalizeDomain(domain)

        await ensureDatabaseLoaded()

        // Try exact match first
        if let rules = rulesByDomain[normalizedDomain] {
            return rules
        }

        // Try registrable domain (eTLD+1) for subdomain matches
        if let registrable = await PublicSuffixList.shared.registrableDomain(for: normalizedDomain),
           registrable != normalizedDomain {
            return rulesByDomain[registrable]
        }

        return nil
    }

    /// Forces a refresh of the quirks database.
    func refresh() async {
        await fetchFromNetwork()
    }

    /// Returns the number of cached rules (for diagnostics).
    var ruleCount: Int {
        rulesByDomain.count
    }

    // MARK: - Private Helpers

    private func normalizeDomain(_ domain: String) -> String {
        var normalized = domain.lowercased()
        if normalized.hasPrefix("www.") {
            normalized = String(normalized.dropFirst(4))
        }
        return normalized
    }

    private func ensureDatabaseLoaded() async {
        // Check memory cache first
        if let lastFetch = lastFetchDate,
           Date().timeIntervalSince(lastFetch) < Self.cacheExpiration,
           !rulesByDomain.isEmpty {
            return
        }

        // Try loading from disk cache
        if await loadFromDiskCache() {
            // If disk cache is fresh enough, don't fetch from network
            if let lastFetch = lastFetchDate,
               Date().timeIntervalSince(lastFetch) < Self.cacheExpiration {
                return
            }
        }

        // Fetch from network
        await fetchFromNetwork()
    }

    // MARK: - Disk Cache

    private var cacheFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Self.cacheFilename)
    }

    /// Loads the database from disk cache.
    ///
    /// - Returns: `true` if cache was loaded successfully.
    private func loadFromDiskCache() async -> Bool {
        guard let cacheURL = cacheFileURL else { return false }

        do {
            // Move file I/O and JSON decoding to background thread
            let cache = try await Task.detached(priority: .userInitiated) {
                let data = try Data(contentsOf: cacheURL)
                return try JSONDecoder().decode(QuirksCache.self, from: data)
            }.value

            // Parse rules from cached data
            var newRules: [String: PasswordRules] = [:]
            for (domain, rulesString) in cache.rules {
                if let rules = PasswordRules.parse(rulesString) {
                    newRules[domain] = rules
                }
            }

            rulesByDomain = newRules
            lastFetchDate = cache.fetchDate

            Logger.debug("Loaded \(rulesByDomain.count) password quirks from disk cache", category: Logger.autoFill)
            return true
        } catch {
            Logger.debug("No disk cache available: \(error.localizedDescription)", category: Logger.autoFill)
            return false
        }
    }

    /// Saves the database to disk cache.
    private func saveToDiskCache(_ rawRules: [String: String]) {
        guard let cacheURL = cacheFileURL else { return }

        let cache = QuirksCache(
            fetchDate: Date(),
            rules: rawRules,
        )

        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: cacheURL, options: .atomic)
            Logger.debug("Saved \(rawRules.count) password quirks to disk cache", category: Logger.autoFill)
        } catch {
            Logger.error("Failed to save quirks cache: \(error)", category: Logger.autoFill)
        }
    }

    // MARK: - Network Fetch

    private func fetchFromNetwork() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: Self.quirksURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                Logger.error("Failed to fetch quirks database: invalid response", category: Logger.autoFill)
                return
            }

            guard data.count <= Self.maxDatabaseSize else {
                Logger.error("Quirks database too large: \(data.count) bytes", category: Logger.autoFill)
                return
            }

            let rawRules = try parseDatabase(data)
            lastFetchDate = Date()

            // Save to disk for offline access
            saveToDiskCache(rawRules)

            Logger.debug("Loaded \(rulesByDomain.count) password quirks from network", category: Logger.autoFill)

        } catch {
            Logger.error("Failed to fetch quirks database: \(error)", category: Logger.autoFill)
        }
    }

    /// Parses the database and returns raw rules for caching.
    @discardableResult
    private func parseDatabase(_ data: Data) throws -> [String: String] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            throw QuirksError.invalidFormat
        }

        var newRules: [String: PasswordRules] = [:]
        var rawRules: [String: String] = [:]

        for (domain, info) in json {
            guard let rulesString = info["password-rules"] as? String else {
                continue
            }

            let normalizedDomain = domain.lowercased()
            rawRules[normalizedDomain] = rulesString

            if let rules = PasswordRules.parse(rulesString) {
                newRules[normalizedDomain] = rules
            }
        }

        rulesByDomain = newRules
        return rawRules
    }

    // MARK: - Types

    private enum QuirksError: Error {
        case invalidFormat
    }

    /// Cached quirks data for disk persistence.
    private struct QuirksCache: Codable {
        let fetchDate: Date
        let rules: [String: String]
    }
}
