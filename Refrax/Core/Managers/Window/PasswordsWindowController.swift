import AppKit
import SwiftUI

/// Manages the dedicated Passwords window.
///
/// Entry points: View menu (Passwords), Cmd+Shift+P shortcut.
///
/// The window requires TouchID or password authentication before showing credentials.
/// This mirrors Apple's Passwords app behavior.
final class PasswordsWindowController: NSObject, NSToolbarDelegate {
    private var window: NSWindow?
    private let passwordsManager: PasswordsManager

    init(passwordsManager: PasswordsManager) {
        self.passwordsManager = passwordsManager
    }

    // MARK: - NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.sidebarTrackingSeparator]
    }

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier _: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool,
    ) -> NSToolbarItem? {
        nil
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
        let passwordsView = PasswordsView()
            .environment(passwordsManager)

        let hostingController = NSHostingController(rootView: passwordsView)
        let window = NSWindow(contentViewController: hostingController)

        window.title = "Passwords"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified

        // Add toolbar with sidebar tracking separator for proper unified appearance
        let toolbar = NSToolbar(identifier: "PasswordsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        window.setContentSize(NSSize(width: 800, height: 550))
        window.minSize = NSSize(width: 600, height: 400)
        window.setFrameAutosaveName("PasswordsWindow")
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
