import Foundation

/// A user profile within a browser that contains its own set of bookmarks.
///
/// Many browsers support multiple user profiles, each with separate bookmarks,
/// history, and settings. This structure represents a single profile that can
/// be selected for import.
///
/// ## Examples
///
/// - **Chrome**: `Default`, `Profile 1`, `Profile 2` directories
/// - **Firefox**: `abc123.default-release`, `xyz789.dev-edition` directories
/// - **Safari**: Single profile per user (always named "Default")
///
/// ## Profile Detection
///
/// Profiles are detected by scanning the browser's data directory:
///
/// ```swift
/// let detector = BrowserDetector()
/// let profiles = detector.detectProfiles(for: .chrome)
/// // [BrowserProfile(name: "Default"), BrowserProfile(name: "Work")]
/// ```
struct BrowserProfile: Identifiable, Sendable, Equatable {
    /// Unique identifier for this profile (typically the directory name).
    let id: String

    /// Human-readable display name for the profile.
    let name: String

    /// File system path to the profile's data directory.
    let path: URL

    /// The browser this profile belongs to.
    let browser: ThirdPartyBrowser
}
