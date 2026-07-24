import Foundation

/// A newer version of Refrax available for download.
///
/// Produced by ``AppUpdateChecker`` from the self-hosted releases endpoint
/// and consumed by ``AppUpdateManager`` to drive the update lifecycle.
nonisolated struct AppUpdate: Sendable, Equatable {
    /// Semantic version string (e.g., "1.2.0").
    let version: String

    /// Optional build number from the release tag.
    let buildNumber: String?

    /// Markdown-formatted release notes.
    let releaseNotes: String

    /// Direct URL to the DMG download.
    let downloadURL: URL

    /// When the release was published.
    let publishedDate: Date

    /// Whether this is a pre-release (alpha/beta).
    let isPrerelease: Bool

    /// Size of the DMG in bytes, if provided by the server.
    let downloadSize: Int64?
}
