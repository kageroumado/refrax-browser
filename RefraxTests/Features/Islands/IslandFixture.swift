import AppKit
import SwiftData
import Testing
@testable import Refrax

/// A window with its islands over a fresh store, for the island suites.
@MainActor
final class IslandFixture {
    let env: TabManagerTestEnvironment
    let space: Space
    let window: WindowState
    let canvas: TabCanvasManager
    let islands: IslandController
    /// The controller's own defaults, apart from the app's: what the hint keeps goes here.
    let defaults: UserDefaults
    let bounds = CGRect(x: 0, y: 0, width: 1_440, height: 1_080)
    let sharing = SharingCoordinator()
    private let suite = "IslandControllerTests.\(UUID().uuidString)"

    init(defaults: UserDefaults? = nil) throws {
        self.env = try TabManagerTestEnvironment()
        self.space = env.makeSpace()
        self.window = env.makeActiveWindowState(with: space)
        self.canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool)
        self.defaults = try defaults ?? #require(UserDefaults(suiteName: suite))
        self.islands = IslandController(
            windowState: window, tabManager: env.tabManager, groupManager: env.groupManager, canvas: canvas, pagePool: env.pagePool,
            defaults: self.defaults,
        )
        window.islandController = islands
        islands.start()
        islands.updateArea(bounds.insetBy(dx: 16, dy: 16), in: bounds)
        env.undoRedoManager.undoManager.groupsByEvent = false
    }

    isolated deinit { islands.stop() }

    /// A row's menu, as a person reads its top level: titles only, no dividers or submenu rows.
    func rowMenu(_ tab: Refrax.Tab) throws -> [String] {
        let island = try #require(islands.island(holding: tab.id))
        let tree = IslandRowMenu(
            tab: tab, island: island, islands: islands, windowState: window, tabs: env.tabManager, bookmarks: env.bookmarksManager,
            canvas: canvas, sharing: sharing, area: bounds,
        ).tree()
        return tree.outline.filter { !$0.hasPrefix(" ") && $0 != "——" }
    }

    func tab(_ title: String, group: TabGroup? = nil) -> Refrax.Tab {
        let address = URL(string: "https://\(UUID().uuidString.lowercased()).test/")!
        let tab = env.tabManager.createTab(url: address, in: space, groupID: group?.id, makeActive: false, loadImmediately: false)
        tab.activePage.title = title
        islands.refresh()
        return tab
    }

    func edit(_ action: () -> Void) {
        let undo = env.undoRedoManager.undoManager
        undo.beginUndoGrouping()
        action()
        undo.endUndoGrouping()
    }
}
