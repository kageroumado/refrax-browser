import CoreGraphics
import Foundation
import SwiftData
import Testing
@testable import Refrax

/// The favorites drawer's drag-to-reorder: the slots stay put, the held tile floats, the order
/// follows the floating tile's centre, and the landing writes the shared favorites order.
struct FavoritesGridReorderTests {
    private static let tile: CGFloat = 100
    private static let spacing: CGFloat = 8

    /// Six tiles in a four-column grid, as the drawer lays them out.
    private static func grid(count: Int = 6, columns: Int = 4) -> (ids: [UUID], frames: [UUID: CGRect]) {
        let ids = (0 ..< count).map { _ in UUID() }
        var frames: [UUID: CGRect] = [:]
        for (index, id) in ids.enumerated() {
            let row = index / columns
            let column = index % columns
            frames[id] = CGRect(
                x: CGFloat(column) * (tile + spacing),
                y: CGFloat(row) * (tile + spacing),
                width: tile,
                height: tile,
            )
        }
        return (ids, frames)
    }

    private static func center(of index: Int, columns: Int = 4) -> CGPoint {
        let row = index / columns
        let column = index % columns
        return CGPoint(x: CGFloat(column) * (tile + spacing) + tile / 2, y: CGFloat(row) * (tile + spacing) + tile / 2)
    }

    @Test
    func `a tile carried over a later slot lands there and the tiles between close up`() throws {
        let (ids, frames) = Self.grid()
        var drag = try #require(FavoritesGridReorder(order: ids, frames: frames, draggedID: ids[1], start: Self.center(of: 1)))
        #expect(drag.order == ids)
        #expect(!drag.changesOrder)

        let moved1 = drag.move(to: Self.center(of: 4))

        #expect(moved1)
        #expect(drag.order == [ids[0], ids[2], ids[3], ids[4], ids[1], ids[5]])
        #expect(drag.targetIndex == 4)
        #expect(drag.changesOrder)
        #expect(drag.insertionNextID == ids[5])

        // A move within the same slot changes nothing.
        let moved2 = drag.move(to: CGPoint(x: Self.center(of: 4).x + 10, y: Self.center(of: 4).y + 10))
        #expect(!moved2)
        #expect(drag.targetIndex == 4)
    }

    @Test
    func `a tile carried over an earlier slot lands there`() throws {
        let (ids, frames) = Self.grid()
        var drag = try #require(FavoritesGridReorder(order: ids, frames: frames, draggedID: ids[5], start: Self.center(of: 5)))
        let moved3 = drag.move(to: Self.center(of: 0))
        #expect(moved3)
        #expect(drag.order == [ids[5], ids[0], ids[1], ids[2], ids[3], ids[4]])
        #expect(drag.insertionNextID == ids[0])
    }

    @Test
    func `carried to the last slot it lands last`() throws {
        let (ids, frames) = Self.grid()
        var drag = try #require(FavoritesGridReorder(order: ids, frames: frames, draggedID: ids[0], start: Self.center(of: 0)))
        let moved4 = drag.move(to: Self.center(of: 5))
        #expect(moved4)
        #expect(drag.order == [ids[1], ids[2], ids[3], ids[4], ids[5], ids[0]])
        #expect(drag.insertionNextID == nil)
    }

    @Test
    func `brought back to its own slot it changes nothing`() throws {
        let (ids, frames) = Self.grid()
        var drag = try #require(FavoritesGridReorder(order: ids, frames: frames, draggedID: ids[2], start: Self.center(of: 2)))
        let moved5 = drag.move(to: Self.center(of: 3))
        #expect(moved5)
        let moved6 = drag.move(to: Self.center(of: 2))
        #expect(moved6)
        #expect(drag.order == ids)
        #expect(!drag.changesOrder)
        #expect(drag.insertionNextID == ids[3])
    }

    @Test
    func `the floating tile follows the pointer from where it was grabbed`() throws {
        let (ids, frames) = Self.grid()
        let grab = CGPoint(x: 130, y: 20) // tile 1 spans x 108...208, y 0...100
        var drag = try #require(FavoritesGridReorder(order: ids, frames: frames, draggedID: ids[1], start: grab))
        #expect(drag.grabOffset == CGSize(width: 22, height: 20))
        #expect(drag.floatingOrigin == CGPoint(x: 108, y: 0))
        #expect(drag.floatingSize == CGSize(width: 100, height: 100))

        drag.move(to: CGPoint(x: 230, y: 70))
        #expect(drag.floatingOrigin == CGPoint(x: 208, y: 50))
        #expect(drag.floatingCenter == CGPoint(x: 258, y: 100))
    }

    @Test
    func `the slot follows the floating tile's centre, not the pointer`() throws {
        let (ids, frames) = Self.grid()
        // Grabbed by its right edge: the pointer is 45 pt right of the tile's centre.
        let grab = CGPoint(x: Self.center(of: 0).x + 45, y: Self.center(of: 0).y)
        var drag = try #require(FavoritesGridReorder(order: ids, frames: frames, draggedID: ids[0], start: grab))
        // The pointer sits over slot 1, but the tile's centre is still nearer slot 0.
        drag.move(to: CGPoint(x: Self.center(of: 1).x - 30, y: grab.y))
        #expect(drag.targetIndex == 0)
        drag.move(to: CGPoint(x: Self.center(of: 1).x + 45, y: grab.y))
        #expect(drag.targetIndex == 1)
    }

    @Test
    func `past the grid's edges the nearest slot holds`() throws {
        let (ids, frames) = Self.grid()
        var drag = try #require(FavoritesGridReorder(order: ids, frames: frames, draggedID: ids[2], start: Self.center(of: 2)))
        drag.move(to: CGPoint(x: -300, y: -300))
        #expect(drag.targetIndex == 0)
        drag.move(to: CGPoint(x: 2000, y: 2000))
        #expect(drag.targetIndex == 5)
        drag.move(to: CGPoint(x: 2000, y: -300))
        #expect(drag.targetIndex == 3)
        // Right of the short last row: the end of the list, not the end of the row above.
        drag.move(to: CGPoint(x: Self.center(of: 3).x, y: Self.center(of: 5).y))
        #expect(drag.targetIndex == 5)
    }

    @Test
    func `settling puts the floating tile on its slot and freezes it`() throws {
        let (ids, frames) = Self.grid()
        var drag = try #require(FavoritesGridReorder(order: ids, frames: frames, draggedID: ids[0], start: CGPoint(x: 10, y: 10)))
        drag.move(to: CGPoint(x: Self.center(of: 5).x, y: Self.center(of: 5).y + 30))
        #expect(drag.targetIndex == 5)
        drag.settle()
        #expect(drag.isSettling)
        #expect(drag.floatingOrigin == frames[ids[5]]?.origin)
        let moved7 = drag.move(to: .zero)
        #expect(!moved7)
        #expect(drag.targetIndex == 5)
        #expect(drag.floatingOrigin == frames[ids[5]]?.origin)
    }

    @Test
    func `without every tile's frame there is no drag`() {
        let (ids, frames) = Self.grid()
        var missing = frames
        missing[ids[3]] = nil
        #expect(FavoritesGridReorder(order: ids, frames: missing, draggedID: ids[0], start: .zero) == nil)
        #expect(FavoritesGridReorder(order: ids, frames: frames, draggedID: UUID(), start: .zero) == nil)
    }

    @Test
    func `the nearest slot by centre`() {
        let slots = [CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 20, y: 0, width: 10, height: 10)]
        #expect(FavoritesGridReorder.slotIndex(nearest: CGPoint(x: 14, y: 5), in: slots) == 0)
        #expect(FavoritesGridReorder.slotIndex(nearest: CGPoint(x: 16, y: 5), in: slots) == 1)
        #expect(FavoritesGridReorder.slotIndex(nearest: .zero, in: []) == 0)
    }

    @Test
    @MainActor
    func `the landing writes the shared favorites order the rail reads`() throws {
        let environment = try TabManagerTestEnvironment()
        let manager = environment.bookmarksManager
        let a = try favorite("A", manager: manager)
        let shortcut = try favorite("Shortcut", manager: manager, live: false)
        let b = try favorite("B", manager: manager)
        let c = try favorite("C", manager: manager)
        let d = try favorite("D", manager: manager)
        manager.refreshFavoritesCache()
        let ids = manager.favorites.map(\.id)
        #expect(ids == [a.id, shortcut.id, b.id, c.id, d.id])
        let framed = Dictionary(uniqueKeysWithValues: ids.indices.map { (ids[$0], Self.frame(of: $0)) })

        // D carried to the front.
        var drag = try #require(FavoritesGridReorder(order: ids, frames: framed, draggedID: d.id, start: Self.center(of: 4)))
        drag.move(to: Self.center(of: 0))
        drag.settle()
        #expect(manager.moveFavorite(drag.draggedID, before: drag.insertionNextID))
        #expect(manager.favorites.map(\.id) == drag.order)
        let movedToFront: [UUID] = [d.id, a.id, shortcut.id, b.id, c.id]
        let liveOnly: [UUID] = [d.id, a.id, b.id, c.id]
        #expect(manager.favorites.map(\.id) == movedToFront)
        #expect(manager.favorites.filter { $0.tab != nil }.map(\.id) == liveOnly)

        // A carried to the end, past the shortcut.
        let order = manager.favorites.map(\.id)
        let framedAgain = Dictionary(uniqueKeysWithValues: order.indices.map { (order[$0], Self.frame(of: $0)) })
        var second = try #require(FavoritesGridReorder(order: order, frames: framedAgain, draggedID: a.id, start: Self.center(of: 1)))
        second.move(to: Self.center(of: 4))
        #expect(second.insertionNextID == nil)
        #expect(manager.moveFavorite(second.draggedID, before: second.insertionNextID))
        let movedToEnd: [UUID] = [d.id, shortcut.id, b.id, c.id, a.id]
        #expect(manager.favorites.map(\.id) == movedToEnd)
        for (index, item) in manager.favorites.enumerated() {
            #expect(item.position.row == index / 4)
            #expect(item.position.column == index % 4)
        }

        try environment.modelContext.save()
        manager.refreshFavoritesCache()
        #expect(manager.favorites.map(\.id) == movedToEnd)
    }

    private static func frame(of index: Int, columns: Int = 4) -> CGRect {
        let row = index / columns
        let column = index % columns
        return CGRect(x: CGFloat(column) * (tile + spacing), y: CGFloat(row) * (tile + spacing), width: tile, height: tile)
    }

    @MainActor
    private func favorite(_ title: String, manager: BookmarksManager, live: Bool = true) throws -> Bookmark {
        manager.createBookmark(url: try #require(URL(string: "about:blank#\(UUID())")), title: title,
                               isFavorite: true, favoriteMode: live ? .liveFavorite : .shortcut)
    }
}
