import AppKit
import SwiftData
import SwiftUI

/// Manages the dedicated Downloads window.
///
/// Entry points: `refrax://downloads`, detail tray expand button, View menu.
final class DownloadsWindowController {
    private var window: NSWindow?
    private let downloadManager: DownloadManager
    private let modelContainer: ModelContainer

    init(
        downloadManager: DownloadManager,
        modelContainer: ModelContainer,
    ) {
        self.downloadManager = downloadManager
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
        let downloadsView = DownloadsView()
            .environment(downloadManager)
            .modelContainer(modelContainer)

        let hostingController = NSHostingController(rootView: downloadsView)
        let window = NSWindow(contentViewController: hostingController)

        window.title = "Downloads"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 700, height: 500))
        window.minSize = NSSize(width: 500, height: 300)
        window.setFrameAutosaveName("DownloadsWindow")
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
