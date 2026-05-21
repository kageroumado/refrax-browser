import AppKit
import SwiftUI

/// Manages the application settings window.
///
/// Provides a single, shared settings panel window following standard macOS behavior
/// where Cmd+, always shows the same settings interface. The window is recreated each
/// time it's opened to minimize memory usage when not visible.
///
/// ## Window Style
///
/// The settings window uses a panel-style appearance similar to Safari's preferences:
/// - Fixed size (500x400)
/// - Utility window style for lighter visual weight
/// - Auto-centers on first appearance
/// - Not restorable (settings state doesn't need persistence)
///
/// ## Environment Integration
///
/// The hosted ``SettingsView`` receives environment objects through ``SettingsEnvironment``,
/// which aggregates all managers needed by settings views. Changes made in settings are
/// immediately visible across all browser windows through SwiftUI's observable system.
final class SettingsWindowController: NSObject, NSToolbarDelegate {
    // MARK: - Properties

    private var window: NSWindow?
    private let environment: SettingsEnvironment

    // MARK: - Initialization

    init(environment: SettingsEnvironment) {
        self.environment = environment
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
    
    // MARK: - Window Management
    
    /// Show the settings window, creating it if needed or bringing it to front if already open.
    func showWindow() {
        if let existingWindow = window {
            // Window exists, just bring it to front
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create new window
        let window = createSettingsWindow()
        self.window = window
        
        // Show and center
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - Private Methods
    
    private func createSettingsWindow() -> NSWindow {
        // Create SwiftUI content view with environment
        let settingsView = SettingsView()
            .settingsEnvironment(environment)

        let hostingController = NSHostingController(rootView: settingsView)
        
        // Create window with panel styling
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified

        // Add toolbar with sidebar tracking separator for proper unified appearance
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        // Size matching SettingsView requirements
        window.setContentSize(NSSize(width: 800, height: 550))
        window.minSize = NSSize(width: 750, height: 500)
        window.maxSize = NSSize(width: 1_000, height: 800)
        
        // Panel behavior
        window.isMovableByWindowBackground = true
        
        // No restoration
        window.isRestorable = false
        
        // Observe close to cleanup
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWindowClosed()
            }
        }
        
        return window
    }
    
    private func handleWindowClosed() {
        // Release window to free memory
        window = nil
    }
}
