import AppKit
import SwiftUI

/// Manages the Acknowledgements window showing third-party license information.
final class AcknowledgementsWindowController {
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
        let view = AcknowledgementsView()
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)

        window.title = "Acknowledgements"
        window.styleMask = [.titled, .closable, .resizable]
        window.titlebarSeparatorStyle = .none
        window.setContentSize(NSSize(width: 600, height: 500))
        window.minSize = NSSize(width: 400, height: 300)
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
