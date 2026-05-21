import Foundation
import Observation

/// Manages the Public Suffix List (PSL) for safe domain extraction.
///
/// The Public Suffix List is a catalog of domain suffixes under which Internet users can register names.
/// It's used to determine the registrable domain (eTLD+1) from a full hostname, which prevents
/// subdomain spoofing attacks (e.g., displaying "evil.com" instead of "login.paypal.evil.com").
///
/// ## Usage
/// ```swift
/// // Load the list (typically at app launch)
/// await PublicSuffixList.shared.loadIfNeeded()
///
/// // Check if a suffix is public
/// PublicSuffixList.shared.isPublicSuffix("co.uk") // true
/// PublicSuffixList.shared.isPublicSuffix("google") // false
/// ```
///
/// ## Caching Strategy
/// - On first load, attempts to read from local cache
/// - If cache is fresh (< 1 week old), uses cached data
/// - If cache is stale, uses cached data immediately but refreshes in background
/// - If no cache exists, fetches from network
/// - Falls back to hardcoded common suffixes if network is unavailable
///
/// ## Data Source
/// Uses Mozilla's Public Suffix List from [publicsuffix.org](https://publicsuffix.org).
@Observable
final class PublicSuffixList {
    static let shared = PublicSuffixList()
    
    /// The set of known public suffixes (e.g., "com", "co.uk", "github.io")
    private(set) var suffixes: Set<String> = []
    private var hasLoaded = false
    
    /// Common multi-part TLDs used as fallback when network is unavailable
    private let fallbackSuffixes: Set<String> = [
        "co.uk", "org.uk", "me.uk", "ac.uk", "gov.uk",
        "co.nz", "co.jp", "co.kr", "co.in", "co.za",
        "com.au", "net.au", "org.au", "edu.au",
        "com.br", "com.mx", "com.ar", "com.co",
        "com.sg", "com.hk", "com.tw", "com.cn",
        "org.il", "co.il", "gov.il",
        "eu.org", "ne.jp", "or.jp",
    ]
    
    private let sourceURL = URL.staticRequired("https://publicsuffix.org/list/public_suffix_list.dat")
    private let cacheFileName = "public_suffix_list.dat"
    private let cacheMaxAge: TimeInterval = 7 * 24 * 60 * 60 // 1 week
    
    private var cacheURL: URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "com.refrax.browser"
        let appCacheDir = cacheDir.appendingPathComponent(bundleID, isDirectory: true)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appCacheDir, withIntermediateDirectories: true)
        
        return appCacheDir.appendingPathComponent(cacheFileName)
    }
    
    private init() {
        self.suffixes = fallbackSuffixes
    }
    
    /// Checks whether the given string is a known public suffix.
    ///
    /// - Parameter suffix: The suffix to check (e.g., "co.uk", "com")
    /// - Returns: `true` if the suffix is in the public suffix list
    func isPublicSuffix(_ suffix: String) -> Bool {
        suffixes.contains(suffix.lowercased())
    }

    /// Extracts the registrable domain (eTLD+1) from a hostname.
    ///
    /// The registrable domain is the effective TLD plus one more label.
    /// For example:
    /// - `sub.example.com` → `example.com`
    /// - `sub.example.co.uk` → `example.co.uk`
    /// - `localhost` → `localhost`
    ///
    /// - Parameter host: The hostname to extract from (e.g., "sub.example.com")
    /// - Returns: The registrable domain, or `nil` if extraction failed.
    func registrableDomain(for host: String) -> String? {
        let lowercased = host.lowercased()
        let labels = lowercased.split(separator: ".").map(String.init)

        guard labels.count >= 2 else {
            // Single-label host (e.g., "localhost")
            return lowercased
        }

        // Try progressively longer suffixes to find the LONGEST matching public suffix
        // Start from the leftmost position and work right, returning the first match
        // This ensures we find "co.uk" before "uk" for "example.co.uk"
        for i in 0 ..< labels.count {
            let potentialSuffix = labels[i...].joined(separator: ".")

            if suffixes.contains(potentialSuffix) {
                // Found public suffix, registrable domain is suffix + one more label
                guard i > 0 else {
                    // The entire hostname is a public suffix (e.g., "co.uk")
                    return nil
                }
                return labels[(i - 1)...].joined(separator: ".")
            }
        }

        // No public suffix found, assume simple TLD (last label)
        // Return eTLD+1 as second-to-last + last label
        return labels.suffix(2).joined(separator: ".")
    }
    
    /// Loads the public suffix list if not already loaded.
    ///
    /// This method is idempotent - calling it multiple times has no effect after the first load.
    /// It prioritizes speed by using cached data when available, refreshing stale caches in the background.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true

        // Check cache off main thread to avoid blocking UI
        let cacheState = await Task.detached { [cacheURL, cacheMaxAge] in
            Self.checkCache(at: cacheURL, maxAge: cacheMaxAge)
        }.value

        switch cacheState {
        case let .fresh(content):
            // Cache is fresh, use it directly
            suffixes = Self.parse(content, fallbacks: fallbackSuffixes)

        case let .stale(content):
            // Cache is stale, use it but refresh in background
            suffixes = Self.parse(content, fallbacks: fallbackSuffixes)
            Task.detached(priority: .background) { [sourceURL, cacheURL] in
                await Self.refreshCache(from: sourceURL, to: cacheURL)
            }

        case .missing:
            // No cache - use fallbacks immediately, then fetch in background.
            // This avoids blocking app launch on network I/O.
            // Fallbacks are already set in init, so just fire off background fetch.
            Task.detached(priority: .utility) { [weak self, sourceURL, cacheURL, fallbackSuffixes] in
                guard let self else { return }
                let parsed = await Self.fetchAndParse(
                    from: sourceURL,
                    cacheTo: cacheURL,
                    fallbacks: fallbackSuffixes,
                )
                await MainActor.run {
                    self.suffixes = parsed
                }
            }
        }
    }

    // MARK: - Cache State

    private enum CacheState: Sendable {
        case fresh(String)
        case stale(String)
        case missing
    }

    /// Checks the state of the cache file.
    ///
    /// This is a nonisolated static method that can be called from a detached task.
    private nonisolated static func checkCache(at cacheURL: URL, maxAge: TimeInterval) -> CacheState {
        let fm = FileManager.default
        guard fm.fileExists(atPath: cacheURL.path),
              let content = try? String(contentsOf: cacheURL, encoding: .utf8) else {
            return .missing
        }

        // Check modification date
        if let attrs = try? fm.attributesOfItem(atPath: cacheURL.path),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) > maxAge {
            return .stale(content)
        }

        return .fresh(content)
    }
    
    // MARK: - Network

    /// Fetches the public suffix list and caches it to disk.
    ///
    /// This is a static method that can be called from a detached task.
    ///
    /// - Parameters:
    ///   - sourceURL: The URL to fetch the list from.
    ///   - cacheURL: The local file URL to cache the list to.
    ///   - fallbacks: Fallback suffixes to include in the result.
    /// - Returns: Parsed set of suffixes, or empty set on failure.
    private static func fetchAndParse(
        from sourceURL: URL,
        cacheTo cacheURL: URL,
        fallbacks: Set<String>,
    ) async -> Set<String> {
        do {
            let (data, _) = try await URLSession.shared.data(from: sourceURL)
            guard let content = String(data: data, encoding: .utf8) else {
                return []
            }

            // Cache to disk
            try? content.write(to: cacheURL, atomically: true, encoding: .utf8)

            return parse(content, fallbacks: fallbacks)
        } catch {
            Logger.warning("PublicSuffixList: Failed to fetch - \(error.localizedDescription)", category: Logger.data)
            return []
        }
    }

    private static func refreshCache(from sourceURL: URL, to cacheURL: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: sourceURL)
            guard let content = String(data: data, encoding: .utf8) else { return }
            try? content.write(to: cacheURL, atomically: true, encoding: .utf8)
        } catch {
            // Silent fail for background refresh
        }
    }

    // MARK: - Parsing

    /// Parses public suffix list content.
    ///
    /// - Parameters:
    ///   - content: Raw PSL file content.
    ///   - fallbacks: Fallback suffixes to include in the result.
    /// - Returns: Set of parsed suffixes.
    private static func parse(_ content: String, fallbacks: Set<String>) -> Set<String> {
        var result = fallbacks

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comments, empty lines, wildcards, exceptions
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("//"),
                  !trimmed.hasPrefix("*"),
                  !trimmed.hasPrefix("!") else {
                continue
            }

            result.insert(trimmed.lowercased())
        }

        return result
    }
}
