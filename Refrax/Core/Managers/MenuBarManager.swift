import AppKit

/// Manager for menu bar setup and actions.
///
/// Delegates actual operations to WindowManager and coordinates with
/// UndoRedoManager for undo/redo menu items.
///
/// ## File layout
/// - `MenuBarManager+AppMenu.swift`: App menu + preferences action.
/// - `MenuBarManager+FileMenu.swift`: File menu + save/export/print actions.
/// - `MenuBarManager+EditMenu.swift`: Edit menu + browser undo/redo + find.
/// - `MenuBarManager+ViewMenu.swift`: View menu + tab/zoom/sidebar actions.
/// - `MenuBarManager+HistoryMenu.swift`: History menu + recently closed actions.
/// - `MenuBarManager+BookmarksMenu.swift`: Bookmarks menu actions.
/// - `MenuBarManager+DevelopMenu.swift`: Develop menu actions + dynamic titles.
/// - `MenuBarManager+WindowMenu.swift`: Window menu setup.
/// - `MenuBarManager+HelpMenu.swift`: Help menu actions.
/// - `MenuBarManager+DockMenu.swift`: Dock menu setup.
/// - `MenuBarManager+MenuDelegate.swift`: NSMenuDelegate hooks.
/// - `MenuBarManager+Tags.swift`: Menu item tag constants.
final class MenuBarManager: NSObject, NSMenuDelegate {
    // MARK: - Dependencies

    let windowManager: WindowManager
    let undoRedoManager: UndoRedoManager

    // MARK: - Menu References

    /// Edit menu reference for dynamic undo/redo updates.
    var editMenu: NSMenu?

    /// Recently closed submenu reference for dynamic updates.
    var recentlyClosedMenu: NSMenu?

    /// Window menu reference for dynamic pin/unpin title updates.
    var windowMenu: NSMenu?

    // MARK: - Computed Properties

    /// Gets the active window controller for menu actions.
    ///
    /// First tries the current key/main window if it's a browser window,
    /// then falls back to the last active browser window. This ensures menu
    /// actions work even when non-browser windows (Web Inspector, Settings) are focused.
    var activeWindowController: RefraxWindowController? {
        // First, check if the key or main window is a browser window
        if let keyWindow = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow,
           let windowController = keyWindow.windowController as? RefraxWindowController {
            return windowController
        }
        // Fall back to the last active browser window (e.g., when Web Inspector is focused)
        return windowManager.lastActiveBrowserWindowController
    }

    // MARK: - Initialization

    init(
        windowManager: WindowManager,
        undoRedoManager: UndoRedoManager,
    ) {
        self.windowManager = windowManager
        self.undoRedoManager = undoRedoManager
        super.init()
    }

    // MARK: - Menu Bar Setup

    func setupMenuBar() {
        let mainMenu = NSMenu()

        mainMenu.addItem(createAppMenu())
        mainMenu.addItem(createFileMenu())
        mainMenu.addItem(createEditMenu())
        mainMenu.addItem(createViewMenu())
        mainMenu.addItem(createHistoryMenu())
        mainMenu.addItem(createBookmarksMenu())
        mainMenu.addItem(createDevelopMenu())
        mainMenu.addItem(createWindowMenu())
        mainMenu.addItem(createHelpMenu())

        NSApplication.shared.mainMenu = mainMenu
    }
}
