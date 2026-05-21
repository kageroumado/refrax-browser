import AppKit
import SwiftData
import SwiftUI

/// Manages the dedicated History window.
///
/// Entry points: `refrax://history`, detail tray expand button, View menu.
final class HistoryWindowController {
    private var window: NSWindow?
    private let historyManager: HistoryManager
    private let tabManager: TabManager
    private let windowManager: WindowManager
    private let modelContainer: ModelContainer

    init(
        historyManager: HistoryManager,
        tabManager: TabManager,
        windowManager: WindowManager,
        modelContainer: ModelContainer,
    ) {
        self.historyManager = historyManager
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

        let historyView = HistoryView()
            .environment(historyManager)
            .environment(tabManager)
            .environment(windowManager)
            .environment(standaloneWindowState)
            .modelContainer(modelContainer)

        let hostingController = NSHostingController(rootView: historyView)
        let window = NSWindow(contentViewController: hostingController)

        window.title = "History"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 900, height: 600))
        window.minSize = NSSize(width: 600, height: 400)
        window.setFrameAutosaveName("HistoryWindow")
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
