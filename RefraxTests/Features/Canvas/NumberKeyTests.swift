import AppKit
import Foundation
import Testing
@testable import Refrax

/// ⌃1…9 show a space and ⌘1…9 open a favorite, from View ▸ Go to Space and View ▸ Go to Favorite.
@Suite("Number keys", .serialized)
@MainActor
struct NumberKeyTests {
    private func submenu(_ title: String, in menus: MenuBarManager) throws -> NSMenu {
        let view = try #require(menus.createViewMenu().submenu)
        return try #require(view.items.first { $0.title == title }?.submenu)
    }

    @Test
    func `Labels name the first nine places`() {
        #expect(NumberKey.space(at: 0) == "⌃1")
        #expect(NumberKey.space(at: 8) == "⌃9")
        #expect(NumberKey.space(at: 9) == nil)
        #expect(NumberKey.favorite(at: 2) == "⌘3")
        #expect(NumberKey.favorite(at: 9) == nil)
    }

    @Test(arguments: [("Go to Space", NSEvent.ModifierFlags.control.rawValue), ("Go to Favorite", NSEvent.ModifierFlags.command.rawValue)])
    func `Each menu holds nine items on the digits with its modifier`(title: String, modifiers: UInt) throws {
        let env = try TabManagerTestEnvironment()
        let menus = MenuBarManager(windowManager: env.windowManager, undoRedoManager: UndoRedoManager())

        let items = try submenu(title, in: menus).items

        #expect(items.map(\.keyEquivalent) == (1 ... 9).map(String.init))
        #expect(items.allSatisfy { $0.keyEquivalentModifierMask.rawValue == modifiers })
        #expect(items.compactMap { $0.representedObject as? Int } == Array(0 ..< 9))
    }

    @Test
    func `Places past the end of the list are hidden, so their keys reach the page`() throws {
        let env = try TabManagerTestEnvironment()
        let menus = MenuBarManager(windowManager: env.windowManager, undoRedoManager: UndoRedoManager())
        let spaces = try submenu("Go to Space", in: menus)

        // No browser window is open, so the list of spaces the menu reads is empty.
        menus.updateNumberKeyMenus(spaces)

        #expect(spaces.items.allSatisfy { $0.isHidden })
    }

    @Test
    func `A space shown by request becomes the window's space`() async throws {
        let env = try TabManagerTestEnvironment()
        let home = env.makeSpace(name: "Home")
        let work = env.makeSpace(name: "Work")
        let window = env.makeActiveWindowState(with: home)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool)
        var switcher: TabSwitcherManager? = TabSwitcherManager(
            tabManager: env.tabManager, windowState: window,
            previewProvider: TabPreviewProvider(tabManager: env.tabManager, windowState: window),
        )

        if let switcher {
            await env.spaceManager.show(work, in: window, canvas: canvas, tabSwitcher: switcher)
        }

        #expect(window.activeSpaceID == work.id)
        // The switcher's observation ends before the window state it watches goes away.
        switcher = nil
    }
}
