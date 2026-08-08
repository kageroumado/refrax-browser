import Foundation

/// Checks the self-hosted releases endpoint for newer versions of Refrax.
///
/// Uses conditional requests (`If-None-Match`) to avoid unnecessary downloads.
///
/// ## Version Comparison
///
/// Parses semantic version strings (major.minor.patch) and compares numerically.
/// A release is considered "newer" if its version is strictly greater than the
/// current version — unless the active ``Constants/API/UpdateChannel`` has
/// ``Constants/API/UpdateChannel/forceUpdate`` enabled, in which case any
/// valid release is returned regardless of version.
nonisolated enum AppUpdateChecker: Sendable {
    /// Cached ETag from the last successful response for conditional requests.
    private static let cachedETagKey = "AppUpdateChecker.lastETag"

    /// Checks for a newer version than the currently running app.
    ///
    /// - Parameters:
    ///   - currentVersion: The running app's version string (e.g., "1.0.0").
    ///   - currentBuild: The running app's build number.
    /// - Returns: An ``AppUpdate`` if a newer version is available, `nil` otherwise.
    static func check(
        currentVersion: String,
        currentBuild _: String,
    ) async throws -> AppUpdate? {
        guard let releasesLatest = Constants.API.releasesLatest else { return nil }
        var request = URLRequest(url: releasesLatest)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let etag = UserDefaults.standard.string(forKey: cachedETagKey) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await HTTPClient.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AppUpdateCheckerError.invalidResponse
        }

        switch http.statusCode {
        case 304:
            return nil

        case 403:
            throw AppUpdateCheckerError.httpError(statusCode: 403)

        case 200:
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                UserDefaults.standard.set(etag, forKey: cachedETagKey)
            }
            return try parseRelease(from: data, currentVersion: currentVersion)

        default:
            throw AppUpdateCheckerError.httpError(statusCode: http.statusCode)
        }
    }

    // MARK: - Parsing

    private static func parseRelease(
        from data: Data,
        currentVersion: String,
    ) throws -> AppUpdate? {
        let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)

        let tagVersion = release.tagName.hasPrefix("v")
            ? String(release.tagName.dropFirst())
            : release.tagName

        // Force-update channels skip version comparison (for testing)
        if !Constants.API.channel.forceUpdate {
            guard isNewer(tagVersion, than: currentVersion) else {
                return nil
            }
        }

        let publishedDate: Date
        if let dateString = release.publishedAt {
            let formatter = ISO8601DateFormatter()
            publishedDate = formatter.date(from: dateString) ?? .now
        } else {
            publishedDate = .now
        }

        guard let downloadURL = release.downloadURL else {
            return nil
        }

        // The release JSON is fetched over HTTPS but is not a signature —
        // don't let it redirect the download to another scheme or host
        guard isAllowedDownloadURL(downloadURL) else {
            Logger.warning(
                "Rejected update download URL: \(downloadURL.absoluteString)",
                category: Logger.updates,
            )
            return nil
        }

        return AppUpdate(
            version: tagVersion,
            buildNumber: nil,
            releaseNotes: release.body ?? "",
            downloadURL: downloadURL,
            publishedDate: publishedDate,
            isPrerelease: release.prerelease,
            downloadSize: release.size,
        )
    }

    // MARK: - Download URL Policy

    /// Whether a server-provided download URL is acceptable.
    ///
    /// Requires HTTPS and the same host as the update-check endpoint. The
    /// force-update debug channel relaxes the scheme so `http://localhost`
    /// testing keeps working, but still pins the host.
    private static func isAllowedDownloadURL(_ url: Foundation.URL) -> Bool {
        guard let checkURL = Constants.API.releasesLatest,
              let allowedHost = checkURL.host,
              url.host == allowedHost
        else { return false }

        if Constants.API.channel.forceUpdate {
            return url.scheme == "https" || url.scheme == "http"
        }
        return url.scheme == "https"
    }

    // MARK: - Version Comparison

    /// Compares two semantic version strings.
    ///
    /// Parses each component as an integer and compares major, minor, patch
    /// in order. Missing components default to 0 (e.g., "1.2" is treated as "1.2.0").
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateComponents = parseVersion(candidate)
        let currentComponents = parseVersion(current)

        for i in 0 ..< max(candidateComponents.count, currentComponents.count) {
            let candidateValue = i < candidateComponents.count ? candidateComponents[i] : 0
            let currentValue = i < currentComponents.count ? currentComponents[i] : 0

            if candidateValue > currentValue { return true }
            if candidateValue < currentValue { return false }
        }

        return false
    }

    private static func parseVersion(_ version: String) -> [Int] {
        version
            .split(separator: ".")
            .compactMap { Int($0) }
    }
}

// MARK: - Release Info JSON

/// Server response from the self-hosted releases endpoint.
private nonisolated struct ReleaseInfo: Decodable {
    let tagName: String
    let body: String?
    let downloadURL: URL?
    let publishedAt: String?
    let prerelease: Bool
    let size: Int64?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case downloadURL = "download_url"
        case publishedAt = "published_at"
        case prerelease
        case size
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt)
        prerelease = try container.decode(Bool.self, forKey: .prerelease)
        size = try container.decodeIfPresent(Int64.self, forKey: .size)

        // Server may return an empty string when no release is published yet
        if let urlString = try container.decodeIfPresent(String.self, forKey: .downloadURL),
           !urlString.isEmpty
        {
            downloadURL = URL(string: urlString)
        } else {
            downloadURL = nil
        }
    }
}

// MARK: - Errors

/// Errors produced by ``AppUpdateChecker`` operations.
nonisolated enum AppUpdateCheckerError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Server returned an invalid response"
        case let .httpError(statusCode):
            "Update server returned HTTP \(statusCode)"
        }
    }
}
