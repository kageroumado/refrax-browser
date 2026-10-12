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
