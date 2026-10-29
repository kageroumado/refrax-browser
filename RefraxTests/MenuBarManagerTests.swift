import AppKit
import Foundation
import Testing
@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for MenuBarManager operations.
    @Tag static var menuBarManager: Self
}

// MARK: - MenuBarManager Initialization Tests

@Suite("MenuBarManager Initialization", .tags(.menuBarManager))
@MainActor
struct MenuBarManagerInitializationTests {
    @Test
    func `Edit menu is initially nil`() throws {
        let env = try TabManagerTestEnvironment()

        let menuBarManager = MenuBarManager(
            windowManager: env.windowManager,
            undoRedoManager: UndoRedoManager(),
        )

        #expect(menuBarManager.editMenu == nil)
    }

    @Test
    func `Recently closed menu is initially nil`() throws {
        let env = try TabManagerTestEnvironment()

        let menuBarManager = MenuBarManager(
            windowManager: env.windowManager,
            undoRedoManager: UndoRedoManager(),
        )

        #expect(menuBarManager.recentlyClosedMenu == nil)
    }

    @Test
    func `Active window controller is nil when no windows`() throws {
        let env = try TabManagerTestEnvironment()

        let menuBarManager = MenuBarManager(
            windowManager: env.windowManager,
            undoRedoManager: UndoRedoManager(),
            focusedWindow: { nil },
        )

        // Without any browser windows open. The test host is Refrax itself, so its real
        // key window must not leak in.
        let controller = menuBarManager.activeWindowController

        #expect(controller == nil)
    }
}

// MARK: - MenuBarManager Setup Tests

@Suite("MenuBarManager Setup", .tags(.menuBarManager), .serialized)
@MainActor
struct MenuBarManagerSetupTests {
    @Test
    func `Setup menu bar creates main menu`() throws {
        let env = try TabManagerTestEnvironment()

        let menuBarManager = MenuBarManager(
            windowManager: env.windowManager,
            undoRedoManager: UndoRedoManager(),
        )

        // Store original menu
        let originalMenu = NSApplication.shared.mainMenu

        menuBarManager.setupMenuBar()

        #expect(NSApplication.shared.mainMenu != nil)
        #expect(NSApplication.shared.mainMenu !== originalMenu)

        // Restore original menu
        NSApplication.shared.mainMenu = originalMenu
    }

    @Test
    func `Setup menu bar creates expected menus`() throws {
        let env = try TabManagerTestEnvironment()

        let menuBarManager = MenuBarManager(
            windowManager: env.windowManager,
            undoRedoManager: UndoRedoManager(),
        )

        let originalMenu = NSApplication.shared.mainMenu

        menuBarManager.setupMenuBar()

        let mainMenu = try #require(NSApplication.shared.mainMenu)

        // Should have standard menu items
        // App, File, Edit, View, History, Bookmarks, Develop, Window, Help = 9
        #expect(mainMenu.numberOfItems >= 9)

        // Restore original menu
        NSApplication.shared.mainMenu = originalMenu
    }
}

@MainActor
private final class UndoEditor: NSView {
    let history = UndoManager()
    override var acceptsFirstResponder: Bool {
        true
    }
    override var undoManager: UndoManager? {
        history
    }
}

@Suite("Menu undo routing", .tags(.menuBarManager), .serialized)
@MainActor
struct MenuUndoRoutingTests {
    @Test
    func `The focused editor takes precedence then browser history supplies undo`() throws {
        let env = try TabManagerTestEnvironment()
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 300), styleMask: .titled, backing: .buffered, defer: false)
        let editor = UndoEditor()
        window.contentView = editor
        window.makeFirstResponder(editor)
        let menuManager = MenuBarManager(windowManager: env.windowManager, undoRedoManager: env.undoRedoManager, focusedWindow: { window })
        let browser = env.undoRedoManager.undoManager
        for (manager, name) in [(editor.history, "Typing"), (browser, "Float Tab")] {
            manager.groupsByEvent = false
            manager.beginUndoGrouping()
            manager.registerUndo(withTarget: editor) { _ in }
            manager.setActionName(name)
            manager.endUndoGrouping()
        }
        let menu = try #require(menuManager.createEditMenu().submenu)
        menuManager.updateEditMenu(menu)
        #expect(menu.items.first?.title == "Undo Typing")
        #expect(menu.items.filter { $0.keyEquivalent == "z" }.count == 2)
        #expect(menuManager.editingUndoManager(redo: false) === editor.history)
        menuManager.browserUndo(nil)
        #expect(editor.history.canUndo == false)
        #expect(browser.canUndo)
        menuManager.updateEditMenu(menu)
        #expect(menu.items.first?.title == "Undo Float Tab")
        #expect(menuManager.editingUndoManager(redo: false) === browser)
        menuManager.browserUndo(nil)
        #expect(browser.canUndo == false)
        #expect(menuManager.validateMenuItem(menu.items[0]) == false)
    }
}
