import CryptoKit
import Foundation
import SwiftData

/// A user-installed JavaScript script that runs on matching web pages.
///
/// User scripts enable Greasemonkey/Tampermonkey-compatible customization of websites.
/// Scripts can be:
/// - Installed from `.user.js` URLs with one click
/// - Created manually via Settings
/// - Auto-updated from @updateURL
///
/// ## URL Matching
///
/// Scripts support three pattern types:
/// - Chrome @match patterns: `*://*.example.com/*`
/// - Greasemonkey @include wildcards: `*example.com*`
/// - Regex patterns: `/^https?:\/\/example\.com\/api\/.*/`
///
/// ## GM_* API Access
///
/// Scripts can request GM_* API functions via @grant. APIs require explicit
/// grants and are provided through a JavaScript shim injected before the script.
///
/// ## Usage
///
/// ```swift
/// let script = try UserScript.create(from: source, sourceURL: url)
/// modelContext.insert(script)
/// ```
@Model
final class UserScript {
    // MARK: - Identity

    /// Unique identifier for the script.
    @Attribute(.unique, .preserveValueOnDeletion)
    var id: UUID = UUID()

    /// Display name from @name metadata.
    var name: String

    /// Namespace for storage isolation (from @namespace or source host).
    ///
    /// Scripts with the same namespace share GM_* storage.
    var namespace: String

    /// Version string from @version metadata.
    var version: String?

    /// Description from @description metadata.
    ///
    /// Named with underscore suffix since `description` is reserved.
    var scriptDescription: String?

    /// Author from @author metadata.
    var author: String?

    // MARK: - Source

    /// Raw JavaScript source code including metadata block.
    var source: String

    /// URL where the script was installed from (@downloadURL).
    var sourceURL: URL?

    /// URL to check for updates (@updateURL), if different from sourceURL.
    var updateURL: URL?

    /// SHA-256 hash of source for integrity verification and update detection.
    var sourceHash: String

    // MARK: - Matching

    /// @include patterns (Greasemonkey-style wildcards or regex).
    var includePatterns: [String]

    /// @exclude patterns to skip matching URLs.
    var excludePatterns: [String]

    /// @match patterns (Chrome extension-style).
    var matchPatterns: [String]

    /// Whether to run in iframes. False when @noframes is present.
    var runAtFrames: Bool = true

    // MARK: - Execution

    /// When to inject the script relative to document loading.
    ///
    /// Stored as raw value string to satisfy SwiftData default value requirements.
    private var runAtRaw: String = ScriptRunTime.documentEnd.rawValue

    /// When to inject the script relative to document loading.
    var runAt: ScriptRunTime {
        get { ScriptRunTime(rawValue: runAtRaw) ?? .documentEnd }
        set { runAtRaw = newValue.rawValue }
    }

    /// Whether the script is currently enabled.
    var isEnabled: Bool = true

    // MARK: - Permissions

    /// Domains allowed for GM_xmlhttpRequest (@connect whitelist).
    var connectDomains: [String]

    /// GM_* functions requested via @grant.
    var grantsRequested: [String]

    // MARK: - Metadata

    /// When the script was first installed.
    var installedAt: Date

    /// When the script was last modified via edit or update.
    var lastUpdatedAt: Date?

    /// When updates were last checked (for remote scripts).
    var lastUpdateCheckAt: Date?

    // MARK: - Computed Properties

    /// Display name, falling back to "Untitled Script" if empty.
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled Script" : trimmed
    }

    /// Storage key for GM_* value storage (based on namespace).
    var storageKey: String {
        namespace
    }

    /// Whether this script was installed from a remote source.
    var isRemote: Bool {
        sourceURL != nil
    }

    /// Primary domain for UI grouping.
    ///
    /// Extracts the main domain from @match patterns, or "All Sites" for global scripts.
    var primaryDomain: String {
        // Check if this matches all URLs
        let allURLsPatterns = ["<all_urls>", "*://*/*", "http*://*/*"]
        let isGlobal = matchPatterns.contains { allURLsPatterns.contains($0) }
            || includePatterns.contains { $0 == "*" || $0 == "http*://*" }

        if isGlobal {
            return "All Sites"
        }

        // Extract domain from first @match pattern
        if let firstMatch = matchPatterns.first {
            return extractDomain(from: firstMatch) ?? "Unknown"
        }

        // Extract domain from first @include pattern
        if let firstInclude = includePatterns.first {
            return extractDomain(from: firstInclude) ?? "Unknown"
        }

        return "Unknown"
    }

    // MARK: - Initialization

    /// Creates a new user script.
    ///
    /// Use `UserScript.create(from:sourceURL:)` to create from raw source.
    init(
        name: String,
        namespace: String,
        source: String,
        matchPatterns: [String] = [],
        includePatterns: [String] = [],
        excludePatterns: [String] = [],
        connectDomains: [String] = [],
        grantsRequested: [String] = [],
    ) {
        self.name = name
        self.namespace = namespace
        self.source = source
        self.matchPatterns = matchPatterns
        self.includePatterns = includePatterns
        self.excludePatterns = excludePatterns
        self.connectDomains = connectDomains
        self.grantsRequested = grantsRequested
        self.sourceHash = Self.computeHash(source)
        self.installedAt = Date()
    }

    // MARK: - Factory Method

    /// Creates a UserScript by parsing metadata from source.
    ///
    /// - Parameters:
    ///   - source: Raw JavaScript source with ==UserScript== metadata block.
    ///   - sourceURL: URL the script was downloaded from (for updates).
    /// - Throws: `UserScriptMetadataError` if parsing fails.
    /// - Returns: A fully configured UserScript.
    static func create(from source: String, sourceURL: URL?) throws -> UserScript {
        let metadata = try UserScriptMetadataParser.parse(source: source)

        // Default namespace to source URL host if not specified
        let namespace = metadata.namespace ?? sourceURL?.host ?? "local"

        let script = UserScript(
            name: metadata.name,
            namespace: namespace,
            source: source,
            matchPatterns: metadata.matchPatterns,
            includePatterns: metadata.includePatterns,
            excludePatterns: metadata.excludePatterns,
            connectDomains: metadata.connectDomains,
            grantsRequested: metadata.grants,
        )

        script.version = metadata.version
        script.scriptDescription = metadata.description
        script.author = metadata.author
        script.runAt = metadata.runAt
        script.runAtFrames = metadata.runAtFrames
        script.sourceURL = sourceURL ?? metadata.downloadURL
        script.updateURL = metadata.updateURL

        return script
    }

    // MARK: - Hash Computation

    /// Computes SHA-256 hash of source content.
    static func computeHash(_ source: String) -> String {
        // Normalize whitespace for consistent hashing
        let normalized = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return SHA256.hash(data: Data(normalized.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Updates the script's source and recomputes the hash.
    func updateSource(_ newSource: String) {
        source = newSource
        sourceHash = Self.computeHash(newSource)
        lastUpdatedAt = Date()
    }

    // MARK: - Domain Extraction

    /// Extracts a readable domain from a pattern.
    private func extractDomain(from pattern: String) -> String? {
        // Handle Chrome @match patterns
        // Format: scheme://host/path (e.g., *://*.github.com/*)
        if pattern.contains("://") {
            let afterScheme = pattern.split(separator: "://", maxSplits: 1).dropFirst().first
            if let hostPart = afterScheme {
                let host = String(hostPart.split(separator: "/", maxSplits: 1).first ?? hostPart)
                // Remove wildcard prefix
                let cleaned = host.hasPrefix("*.") ? String(host.dropFirst(2)) : host
                if cleaned != "*" {
                    return cleaned
                }
            }
        }

        // Handle Greasemonkey @include patterns (simpler wildcards)
        // Try to extract a domain-like substring
        let domainPattern = #/([a-z0-9][-a-z0-9]*\.)+[a-z]{2,}/#
        if let match = pattern.firstMatch(of: domainPattern) {
            return String(match.0)
        }

        return nil
    }
}

// ScriptRunTime is defined in UserScriptMetadataParser.swift to avoid MainActor isolation from @Model
