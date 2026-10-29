import Foundation

extension BookmarksManager {
    /// Moves a live favorite within the live-tab slots of the shared favorites order.
    /// Folder, shortcut, and app destinations keep their saved positions.
    @discardableResult
    func moveLiveFavorite(_ id: UUID, before nextID: UUID?) -> Bool {
        let slots = favorites.filter { $0.tab != nil }.sorted { $0.position < $1.position }
        guard let source = slots.firstIndex(where: { $0.id == id }),
              nextID != id,
              nextID == nil || slots.contains(where: { $0.id == nextID }) else { return false }
        var reordered = slots
        let moving = reordered.remove(at: source)
        let destination = nextID.flatMap { next in reordered.firstIndex { $0.id == next } } ?? reordered.count
        reordered.insert(moving, at: destination)
        guard reordered.map(\.id) != slots.map(\.id) else { return false }
        for (slot, item) in zip(slots, reordered) {
            item.bookmark?.favoritePosition = slot.position
        }
        scheduleSave()
        refreshFavoritesCache()
        return true
    }
}

extension BookmarksManager {
    /// Moves any favorite, a live tab, shortcut, folder, or app destination, within the shared
    /// favorites order, as the library drawer's grid arranges them, and renumbers every slot.
    @discardableResult
    func moveFavorite(_ id: UUID, before nextID: UUID?) -> Bool {
        let ordered = favorites.sorted { $0.position < $1.position }
        guard let source = ordered.firstIndex(where: { $0.id == id }),
              nextID != id,
              nextID == nil || ordered.contains(where: { $0.id == nextID }) else { return false }
        var reordered = ordered
        let moving = reordered.remove(at: source)
        let destination = nextID.flatMap { next in reordered.firstIndex { $0.id == next } } ?? reordered.count
        reordered.insert(moving, at: destination)
        guard reordered.map(\.id) != ordered.map(\.id) else { return false }
        for (index, item) in reordered.enumerated() {
            let position = FavoritePosition(row: index / _maxFavoritesGridColumns, col: index % _maxFavoritesGridColumns)
            switch item.type {
            case let .liveFavorite(bookmark, _), let .shortcut(bookmark):
                bookmark.favoritePosition = position
            case let .folder(folder):
                folder.favoritePosition = position
            case let .appShortcut(shortcut):
                shortcut.position = position
            }
        }
        scheduleSave()
        refreshFavoritesCache()
        return true
    }
}
