import Foundation

/// Where a tab lives: in one space, or in every space as a favorite.
///
/// - **Regular**: a tab in exactly one space. It can join a group and is subject to
///   automatic cleanup.
///
/// - **Favorite**: a tab that belongs to no space. It has a home address (its linked
///   ``Bookmark``'s URL), sits in the island's favorites column in every space, keeps its
///   place on the floating layer in every space, and returns home when closed. Favorites
///   use global website data storage and are never cleaned up.
///
/// ## Storage
///
/// Favorites are held in ``BrowserState/favoriteTabs`` rather than a space's
/// ``Space/tabs``.
nonisolated enum TabStatus: Codable, Sendable, Hashable, CaseIterable, RawRepresentable {
    /// A tab in exactly one space.
    case regular

    /// A tab in every space, linked to a favorited ``Bookmark`` through ``Tab/linkedBookmark``.
    case favorite

    /// Reads a stored status.
    ///
    /// The store also holds `liveFavorite` and `pinned` rows written before favorites became
    /// one model. Both read as `.favorite`; ``FavoriteMigration`` then turns the pinned ones,
    /// which still sit in a space, into favorites at the first launch.
    init?(rawValue: String) {
        switch rawValue {
        case "regular": self = .regular
        case "favorite", "liveFavorite", "pinned": self = .favorite
        default: return nil
        }
    }

    var rawValue: String {
        switch self {
        case .regular: "regular"
        case .favorite: "favorite"
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let stored = try container.decode(String.self)
        guard let status = Self(rawValue: stored) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown tab status \(stored)")
        }
        self = status
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Whether this status makes the tab exempt from automatic cleanup.
    var isExemptFromCleanup: Bool {
        self == .favorite
    }

    /// Whether this tab uses global website data storage regardless of any space's settings.
    var usesGlobalDataStore: Bool {
        self == .favorite
    }
}
