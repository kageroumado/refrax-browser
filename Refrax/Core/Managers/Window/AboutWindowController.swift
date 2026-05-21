import AppKit
import SwiftUI

/// Manages the custom About Refrax window.
final class AboutWindowController {
    private var window: NSWindow?

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
        let view = AboutView()
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)

        window.title = "About Refrax"
        window.styleMask = [.titled, .closable]
        window.titlebarSeparatorStyle = .none
        window.titleVisibility = .hidden
        window.isRestorable = false
        window.isMovableByWindowBackground = true

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
