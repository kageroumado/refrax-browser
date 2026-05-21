import Foundation
import WebKit

// MARK: - Script Run Time

/// When a user script should be injected relative to document loading.
enum ScriptRunTime: String, Codable, Sendable {
    /// Inject as early as possible, before document starts parsing.
    case documentStart = "document-start"

    /// Inject after DOM is ready but before resources loaded.
    case documentEnd = "document-end"

    /// Inject after page is fully loaded (window.onload fired).
    case documentIdle = "document-idle"

    /// Converts to WebKit injection time.
    ///
    /// Note: WebKit doesn't have an "idle" equivalent, so documentIdle
    /// maps to documentEnd (closest available).
    var wkInjectionTime: WKUserScriptInjectionTime {
        switch self {
        case .documentStart:
            .atDocumentStart
        case .documentEnd, .documentIdle:
            .atDocumentEnd
        }
    }
}

// MARK: - Metadata Errors

/// Errors that can occur during user script metadata parsing.
nonisolated enum UserScriptMetadataError: LocalizedError, Sendable {
    case emptySource
    case noMetadataBlock
    case unterminatedMetadataBlock
    case missingRequiredField(String)
    case noMatchPatterns

    var errorDescription: String? {
        switch self {
        case .emptySource:
            "Script source is empty"
        case .noMetadataBlock:
            "No ==UserScript== metadata block found"
        case .unterminatedMetadataBlock:
            "Metadata block is not properly terminated with ==/UserScript=="
        case let .missingRequiredField(field):
            "Missing required field: @\(field)"
        case .noMatchPatterns:
            "Script must have at least one @match or @include pattern"
        }
    }
}

/// Parsed metadata from a user script's ==UserScript== block.
nonisolated struct UserScriptMetadata: Sendable {
    // Required
    let name: String

    // Optional identity
    let namespace: String?
    let version: String?
    let description: String?
    let author: String?

    // URL patterns
    let matchPatterns: [String]
    let includePatterns: [String]
    let excludePatterns: [String]

    // Execution
    let runAt: ScriptRunTime
    let runAtFrames: Bool

    // Permissions
    let grants: [String]
    let connectDomains: [String]

    // URLs
    let downloadURL: URL?
    let updateURL: URL?
    let homepageURL: URL?

    // Resources
    let requires: [URL]
    let resources: [String: URL]
}

/// Parses Greasemonkey/Tampermonkey-style metadata from user scripts.
///
/// Extracts metadata from the ==UserScript== ... ==/UserScript== block:
///
/// ```javascript
/// // ==UserScript==
/// // @name         My Script
/// // @namespace    https://example.com
/// // @version      1.0.0
/// // @description  Does something cool
/// // @match        *://*.example.com/*
/// // @grant        GM_setValue
/// // ==/UserScript==
/// ```
///
/// ## Supported Keys
///
/// | Key | Required | Description |
/// |-----|----------|-------------|
/// | @name | Yes | Script display name |
/// | @namespace | No | Storage isolation namespace |
/// | @version | No | Semantic version string |
/// | @description | No | Human-readable description |
/// | @author | No | Author name/contact |
/// | @match | One of | Chrome-style URL patterns |
/// | @include | One of | Greasemonkey-style patterns |
/// | @exclude | No | Patterns to skip |
/// | @run-at | No | document-start/end/idle |
/// | @grant | No | GM_* functions to enable |
/// | @connect | No | Domains for GM_xmlhttpRequest |
/// | @noframes | No | Don't run in iframes |
/// | @downloadURL | No | Source URL |
/// | @updateURL | No | Update check URL |
nonisolated enum UserScriptMetadataParser {
    // MARK: - Constants

    private static let metadataStartMarker = "==UserScript=="
    private static let metadataEndMarker = "==/UserScript=="

    // Regex patterns
    private nonisolated(unsafe) static let linePattern = #/^\s*\/\/\s*(@\S+)\s*(.*)?\s*$/#

    // MARK: - Parsing

    /// Parses metadata from script source.
    ///
    /// - Parameter source: Raw JavaScript source with metadata block.
    /// - Throws: `UserScriptMetadataError` if parsing fails.
    /// - Returns: Parsed metadata.
    static func parse(source: String) throws -> UserScriptMetadata {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw UserScriptMetadataError.emptySource
        }

        // Find metadata block
        guard let startRange = source.range(of: metadataStartMarker) else {
            throw UserScriptMetadataError.noMetadataBlock
        }

        guard let endRange = source.range(of: metadataEndMarker, range: startRange.upperBound ..< source.endIndex) else {
            throw UserScriptMetadataError.unterminatedMetadataBlock
        }

        // Extract block content
        let blockContent = String(source[startRange.upperBound ..< endRange.lowerBound])

        // Parse key-value pairs
        var metadata = ParsedValues()
        let lines = blockContent.components(separatedBy: .newlines)

        for line in lines {
            parseLine(line, into: &metadata)
        }

        // Validate required fields
        guard let name = metadata.name, !name.isEmpty else {
            throw UserScriptMetadataError.missingRequiredField("name")
        }

        guard !metadata.matchPatterns.isEmpty || !metadata.includePatterns.isEmpty else {
            throw UserScriptMetadataError.noMatchPatterns
        }

        return UserScriptMetadata(
            name: truncate(name, maxLength: 256),
            namespace: metadata.namespace,
            version: metadata.version,
            description: metadata.description,
            author: metadata.author,
            matchPatterns: metadata.matchPatterns,
            includePatterns: metadata.includePatterns,
            excludePatterns: metadata.excludePatterns,
            runAt: parseRunAt(metadata.runAt),
            runAtFrames: !metadata.noframes,
            grants: metadata.grants,
            connectDomains: metadata.connectDomains,
            downloadURL: metadata.downloadURL.flatMap(URL.init(string:)),
            updateURL: metadata.updateURL.flatMap(URL.init(string:)),
            homepageURL: metadata.homepageURL.flatMap(URL.init(string:)),
            requires: metadata.requires.compactMap(URL.init(string:)),
            resources: parseResources(metadata.resources),
        )
    }

    // MARK: - Line Parsing

    private static func parseLine(_ line: String, into metadata: inout ParsedValues) {
        // Handle both Unix (\n) and Windows (\r\n) line endings
        let cleanLine = line.replacingOccurrences(of: "\r", with: "")

        guard let match = cleanLine.firstMatch(of: linePattern) else {
            return
        }

        let key = String(match.1).lowercased()
        let value = String(match.2 ?? "").trimmingCharacters(in: .whitespaces)
        // Remove null bytes for security
        let sanitizedValue = value.replacingOccurrences(of: "\0", with: "")

        switch key {
        case "@name":
            metadata.name = sanitizedValue
        case "@namespace":
            metadata.namespace = sanitizedValue
        case "@version":
            metadata.version = sanitizedValue
        case "@description":
            metadata.description = sanitizedValue
        case "@author":
            metadata.author = sanitizedValue
        case "@match":
            if !sanitizedValue.isEmpty {
                metadata.matchPatterns.append(sanitizedValue)
            }
        case "@include":
            if !sanitizedValue.isEmpty {
                metadata.includePatterns.append(sanitizedValue)
            }
        case "@exclude":
            if !sanitizedValue.isEmpty {
                metadata.excludePatterns.append(sanitizedValue)
            }
        case "@run-at":
            metadata.runAt = sanitizedValue
        case "@grant":
            if !sanitizedValue.isEmpty {
                metadata.grants.append(sanitizedValue)
            }
        case "@connect":
            if !sanitizedValue.isEmpty {
                metadata.connectDomains.append(sanitizedValue)
            }
        case "@noframes":
            metadata.noframes = true
        case "@downloadurl":
            metadata.downloadURL = sanitizedValue
        case "@updateurl":
            metadata.updateURL = sanitizedValue
        case "@homepage", "@homepageurl":
            metadata.homepageURL = sanitizedValue
        case "@require":
            if !sanitizedValue.isEmpty {
                metadata.requires.append(sanitizedValue)
            }
        case "@resource":
            if !sanitizedValue.isEmpty {
                metadata.resources.append(sanitizedValue)
            }
        default:
            // Ignore unknown keys
            break
        }
    }

    // MARK: - Helpers

    private static func parseRunAt(_ value: String?) -> ScriptRunTime {
        guard let value = value?.lowercased() else {
            return .documentEnd
        }

        switch value {
        case "document-start":
            return .documentStart
        case "document-end":
            return .documentEnd
        case "document-idle":
            return .documentIdle
        default:
            return .documentEnd
        }
    }

    private static func parseResources(_ resources: [String]) -> [String: URL] {
        var result: [String: URL] = [:]

        for resource in resources {
            // Format: "name URL" or "name\tURL"
            let parts = resource.split(whereSeparator: { $0.isWhitespace })
            if parts.count >= 2 {
                let name = String(parts[0])
                let urlString = parts.dropFirst().joined(separator: " ")
                if let url = URL(string: urlString) {
                    result[name] = url
                }
            }
        }

        return result
    }

    private static func truncate(_ string: String, maxLength: Int) -> String {
        if string.count <= maxLength {
            return string
        }
        return String(string.prefix(maxLength))
    }
}

// MARK: - Intermediate Parsed Values

private extension UserScriptMetadataParser {
    struct ParsedValues {
        var name: String?
        var namespace: String?
        var version: String?
        var description: String?
        var author: String?

        var matchPatterns: [String] = []
        var includePatterns: [String] = []
        var excludePatterns: [String] = []

        var runAt: String?
        var noframes: Bool = false

        var grants: [String] = []
        var connectDomains: [String] = []

        var downloadURL: String?
        var updateURL: String?
        var homepageURL: String?

        var requires: [String] = []
        var resources: [String] = []
    }
}
