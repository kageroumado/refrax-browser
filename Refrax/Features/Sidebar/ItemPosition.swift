import Foundation

/// Type-safe representation of an item's position in the sidebar.
///
/// The sidebar has three collections in order: favorites, pinned, normal.
/// Each item has both a local index (within its collection) and a global index
/// (across all collections). This enum ensures we always know which collection
/// an index refers to, preventing bugs from index misinterpretation.
enum ItemPosition: Equatable, Hashable {
    case favorites(localIndex: Int)
    case pinned(localIndex: Int)
    case normal(localIndex: Int)

    /// The collection this position belongs to.
    var collection: SidebarCollection {
        switch self {
        case .favorites: .favorites
        case .pinned: .pinned
        case .normal: .normal
        }
    }

    /// The index within the item's collection (0-based).
    var localIndex: Int {
        switch self {
        case let .favorites(idx), let .pinned(idx), let .normal(idx):
            idx
        }
    }

    /// Calculates the global index using the provided collection bounds.
    ///
    /// Global index is the position across ALL collections:
    /// - favorites: 0..<favoritesCount
    /// - pinned: favoritesCount..<(favoritesCount + pinnedCount)
    /// - normal: (favoritesCount + pinnedCount)..<total
    func globalIndex(bounds: Sidebar.LayoutManager.CollectionBounds) -> Int {
        switch self {
        case let .favorites(idx):
            idx
        case let .pinned(idx):
            bounds.pinned.lowerBound + idx
        case let .normal(idx):
            bounds.normal.lowerBound + idx
        }
    }

    /// Creates an ItemPosition from a global index.
    ///
    /// Returns nil if the global index is out of bounds.
    static func from(globalIndex: Int, bounds: Sidebar.LayoutManager.CollectionBounds) -> ItemPosition? {
        if bounds.favorites.contains(globalIndex) {
            return .favorites(localIndex: globalIndex - bounds.favorites.lowerBound)
        } else if bounds.pinned.contains(globalIndex) {
            return .pinned(localIndex: globalIndex - bounds.pinned.lowerBound)
        } else if bounds.normal.contains(globalIndex) {
            return .normal(localIndex: globalIndex - bounds.normal.lowerBound)
        }
        return nil
    }

    /// Creates an ItemPosition from metadata.
    ///
    /// Convenience initializer when you have item metadata available.
    static func from(metadata: Sidebar.LayoutManager.ItemMetadata) -> ItemPosition {
        switch metadata.collection {
        case .favorites:
            .favorites(localIndex: metadata.indexInCollection)
        case .pinned:
            .pinned(localIndex: metadata.indexInCollection)
        case .normal:
            .normal(localIndex: metadata.indexInCollection)
        }
    }

    /// Creates a position at the start of a collection.
    static func start(of collection: SidebarCollection) -> ItemPosition {
        switch collection {
        case .favorites: .favorites(localIndex: 0)
        case .pinned: .pinned(localIndex: 0)
        case .normal: .normal(localIndex: 0)
        }
    }

    /// Creates a position at the end of a collection.
    static func end(of collection: SidebarCollection, bounds: Sidebar.LayoutManager.CollectionBounds) -> ItemPosition {
        switch collection {
        case .favorites:
            .favorites(localIndex: bounds.favorites.count)
        case .pinned:
            .pinned(localIndex: bounds.pinned.count)
        case .normal:
            .normal(localIndex: bounds.normal.count)
        }
    }

    /// Returns true if this position is at the start of its collection.
    var isAtStart: Bool {
        localIndex == 0
    }

    /// Whether this position is in a tab list collection (pinned or normal).
    var isInTabList: Bool {
        switch self {
        case .favorites: false
        case .pinned, .normal: true
        }
    }
}
