import AppKit
import SwiftData
import SwiftUI

/// Manages the dedicated Bookmarks window.
///
/// Entry points: `refrax://bookmarks`, detail tray expand button, View menu.
final class BookmarksWindowController {
    private var window: NSWindow?
    private let bookmarksManager: BookmarksManager
    private let tabManager: TabManager
    private let windowManager: WindowManager
    private let modelContainer: ModelContainer

    init(
        bookmarksManager: BookmarksManager,
        tabManager: TabManager,
        windowManager: WindowManager,
        modelContainer: ModelContainer,
    ) {
        self.bookmarksManager = bookmarksManager
        self.tabManager = tabManager
        self.windowManager = windowManager
        self.modelContainer = modelContainer
    }

    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let newWindow = createWindow()
        window = newWindow

        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createWindow() -> NSWindow {
        let appDelegate = NSApp.typedDelegate
        let standaloneWindowState = WindowState(
            settings: appDelegate.settings,
            browserState: appDelegate.browserState,
        )

        let bookmarksView = BookmarksView()
            .environment(bookmarksManager)
            .environment(tabManager)
            .environment(windowManager)
            .environment(standaloneWindowState)
            .environment(appDelegate.offlineContentManager)
            .modelContainer(modelContainer)

        let hostingController = NSHostingController(rootView: bookmarksView)
        let window = NSWindow(contentViewController: hostingController)

        window.title = "Bookmarks"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 900, height: 600))
        window.minSize = NSSize(width: 600, height: 400)
        window.setFrameAutosaveName("BookmarksWindow")
        window.isRestorable = false

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.window = nil
            }
        }

        return window
    }
}
