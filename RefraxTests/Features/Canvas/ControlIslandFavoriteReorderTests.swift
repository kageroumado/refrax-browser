import Foundation
import SwiftData
import Testing
@testable import Refrax

@Suite(.serialized)
@MainActor
struct ControlIslandFavoriteReorderTests {
    @Test
    func `moving live tabs preserves hidden destination slots and persists their shared order`() throws {
        let environment = try TabManagerTestEnvironment()
        let manager = environment.bookmarksManager
        let a = try favorite("A", manager: manager)
        let shortcut = try favorite("Shortcut", manager: manager, live: false)
        let b = try favorite("B", manager: manager)
        let folder = try manager.createFolder(name: "Folder")
        manager.addFolderToFavorites(folder)
        let c = try favorite("C", manager: manager)
        manager.refreshFavoritesCache()
        let shortcutPosition = shortcut.favoritePosition
        let folderPosition = folder.favoritePosition
        let movedOrder: [UUID] = [c.id, shortcut.id, a.id, folder.id, b.id]
        let originalOrder: [UUID] = [a.id, shortcut.id, b.id, folder.id, c.id]

        #expect(manager.moveLiveFavorite(c.id, before: a.id))
        #expect(manager.favorites.map(\.id) == movedOrder)
        #expect(shortcut.favoritePosition == shortcutPosition)
        #expect(folder.favoritePosition == folderPosition)
        try environment.modelContext.save()
        manager.refreshFavoritesCache()
        #expect(manager.favorites.filter { $0.tab != nil }.map(\.id) == [c.id, a.id, b.id])

        #expect(manager.moveLiveFavorite(c.id, before: nil))
        #expect(manager.favorites.map(\.id) == originalOrder)
    }

    @Test
    func `dropping on the same slot or a missing destination preserves favorites`() throws {
        let environment = try TabManagerTestEnvironment()
        let manager = environment.bookmarksManager
        let a = try favorite("A", manager: manager)
        let b = try favorite("B", manager: manager)
        let shortcut = try favorite("Shortcut", manager: manager, live: false)
        manager.refreshFavoritesCache()
        let original = manager.favorites.map(\.id)
        #expect(!manager.moveLiveFavorite(a.id, before: a.id))
        #expect(!manager.moveLiveFavorite(a.id, before: b.id))
        #expect(!manager.moveLiveFavorite(b.id, before: nil))
        #expect(!manager.moveLiveFavorite(a.id, before: UUID()))
        #expect(!manager.moveLiveFavorite(UUID(), before: a.id))
        #expect(!manager.moveLiveFavorite(shortcut.id, before: a.id))
        #expect(!manager.moveLiveFavorite(a.id, before: shortcut.id))
        #expect(manager.favorites.map(\.id) == original)
    }

    @Test
    func `moving across grid rows keeps normalized positions and stable tab identities`() throws {
        let environment = try TabManagerTestEnvironment()
        let manager = environment.bookmarksManager
        let bookmarks = try (0..<7).map { try favorite("Favorite \($0)", manager: manager) }
        manager.refreshFavoritesCache()
        let tabIDs = Dictionary(uniqueKeysWithValues: manager.favorites.map { ($0.id, $0.tab?.id) })
        #expect(manager.moveLiveFavorite(bookmarks[1].id, before: bookmarks[6].id))
        let expected = [0, 2, 3, 4, 5, 1, 6].map { bookmarks[$0].id }
        #expect(manager.favorites.map(\.id) == expected)
        for (index, favorite) in manager.favorites.enumerated() {
            #expect(favorite.position.row == index / 4)
            #expect(favorite.position.column == index % 4)
            #expect(favorite.tab?.id == tabIDs[favorite.id])
        }
    }

    private func favorite(_ title: String, manager: BookmarksManager, live: Bool = true) throws -> Bookmark {
        manager.createBookmark(url: try #require(URL(string: "about:blank#\(UUID())")), title: title,
                               isFavorite: true, favoriteMode: live ? .liveFavorite : .shortcut)
    }
}
