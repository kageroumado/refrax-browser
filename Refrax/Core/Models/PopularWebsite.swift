import Foundation

/// A curated popular website for Command Lens suggestions.
///
/// Provides instant URL suggestions when the user has limited browsing history.
/// Loaded from a bundled JSON resource on first access.
struct PopularWebsite: Codable, Sendable {
    /// The domain name (e.g., "amazon.com").
    let domain: String

    /// Display name (e.g., "Amazon").
    let name: String

    /// Category for grouping (e.g., "Shopping", "Social", "Dev").
    let category: String
}
