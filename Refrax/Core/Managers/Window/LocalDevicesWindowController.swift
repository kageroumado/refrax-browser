import AppKit
import SwiftUI

/// Manages the Local Devices window: a map of the router and the devices around it.
///
/// Entry points: View menu "Local Devices", Command Lens.
final class LocalDevicesWindowController {
    private var window: NSWindow?
    private let model: LocalDevicesModel

    init(directory: LocalNetworkDirectory, tabManager: TabManager) {
        self.model = LocalDevicesModel(directory: directory, tabManager: tabManager)
    }

    func showWindow() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            model.refresh()
            return
        }

        let newWindow = createWindow()
        window = newWindow

        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func createWindow() -> NSWindow {
        let hostingController = NSHostingController(rootView: LocalDevicesView(model: model))
        let window = NSWindow(contentViewController: hostingController)

        window.title = "Local Devices"
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 820, height: 720))
        window.minSize = NSSize(width: 560, height: 460)
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
