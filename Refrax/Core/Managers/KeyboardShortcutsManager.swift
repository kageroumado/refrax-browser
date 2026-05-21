import AppKit

/// Centralized keyboard shortcut handler for the application.
///
/// `KeyboardShortcutsManager` monitors keyboard events at the application level
/// and forwards them to the appropriate window controller. This avoids the problem
/// of each window adding its own event monitor, which causes duplicate handlers
/// and leaked monitors after window close.
///
/// ## Shortcuts Handled
///
/// - **Cmd+T**: Open command lens (new tab)
/// - **Cmd+L**: Open address lens
/// - **Cmd+Shift+[**: Select previous tab
/// - **Cmd+Shift+]**: Select next tab
/// - **Ctrl+Tab / Ctrl+Shift+Tab**: Tab switcher navigation
/// - **Escape**: Dismiss tab switcher, command lens, or address lens
/// - **Extension commands**: Shortcuts registered by browser extensions
///
/// ## Priority
///
/// Refrax system shortcuts take priority over extension shortcuts.
/// Extension shortcuts are only processed if no system shortcut matches.
///
/// ## Architecture
///
/// The manager is initialized once in AppDelegate and holds a single event monitor.
/// It uses weak references to WindowManager to access the active window controller.
final class KeyboardShortcutsManager: Sendable {
    // MARK: - Dependencies

    private weak var windowManager: WindowManager?
    private weak var extensionManager: ExtensionManager?

    /// Handler for extension keyboard commands.
    private nonisolated(unsafe) var extensionCommandHandler: ExtensionCommandHandler?

    // MARK: - State

    private nonisolated(unsafe) var keyDownMonitor: Any?
    private nonisolated(unsafe) var flagsChangedMonitor: Any?
    private nonisolated(unsafe) var mouseMonitor: Any?

    // MARK: - Initialization

    /// Creates a keyboard shortcuts manager.
    ///
    /// - Parameter windowManager: The window manager to use for finding the active window.
    init(windowManager: WindowManager) {
        self.windowManager = windowManager
        startMonitoring()
    }

    /// Sets the extension manager for handling extension shortcuts.
    ///
    /// - Parameter manager: The extension manager.
    func setExtensionManager(_ manager: ExtensionManager) {
        extensionManager = manager
        extensionCommandHandler = ExtensionCommandHandler(extensionManager: manager)
    }

    deinit {
        // Event monitors are automatically removed when the process exits.
        // This manager lives for the entire app lifetime, so explicit cleanup
        // is not needed in practice. The nonisolated(unsafe) annotation is safe
        // because the monitors are only accessed from MainActor context.
    }

    // MARK: - Monitoring

    private func startMonitoring() {
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }

        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            self?.handleMouseButton(event)
        }
    }

    // MARK: - Event Handling

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard let windowManager,
              let controller = activeWindowController(for: event, windowManager: windowManager)
        else {
            return event
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Cmd+T: Open command lens
        if modifiers == .command, event.charactersIgnoringModifiers == "t" {
            controller.openCommandLens()
            return nil
        }

        // Cmd+L: Open address lens
        if modifiers == .command, event.charactersIgnoringModifiers == "l" {
            controller.openAddressLens()
            return nil
        }

        // Cmd+O: Open file
        if modifiers == .command, event.charactersIgnoringModifiers == "o" {
            controller.openFilePanel()
            return nil
        }

        // Cmd+F: Find in page
        if modifiers == .command, event.charactersIgnoringModifiers == "f" {
            controller.windowState.showFindNavigator()
            return nil
        }

        // Cmd+R: Reload page
        if modifiers == .command, event.charactersIgnoringModifiers == "r" {
            controller.reloadPage()
            return nil
        }

        // Cmd+Shift+R: Reload without cache
        if modifiers == [.command, .shift],
           event.charactersIgnoringModifiers?.lowercased() == "r" {
            controller.reloadPageFromOrigin()
            return nil
        }

        // Cmd+Shift+[: Select previous tab
        if modifiers == [.command, .shift], event.charactersIgnoringModifiers == "[" {
            controller.selectPreviousTab()
            return nil
        }

        // Cmd+Shift+]: Select next tab
        if modifiers == [.command, .shift], event.charactersIgnoringModifiers == "]" {
            controller.selectNextTab()
            return nil
        }

        // Ctrl+Tab / Ctrl+Shift+Tab: Tab switcher
        if event.keyCode == KeyCode.tab, modifiers.contains(.control) {
            let tabSwitcherManager = controller.tabSwitcherManager
            if tabSwitcherManager.isActive {
                if modifiers.contains(.shift) {
                    tabSwitcherManager.selectPrevious()
                } else {
                    tabSwitcherManager.selectNext()
                }
            } else if tabSwitcherManager.canShowSwitcher {
                tabSwitcherManager.show()
            }
            return nil
        }

        // Escape: Dismiss overlays, or stop loading if no overlay is active
        if event.keyCode == KeyCode.escape {
            let tabSwitcherManager = controller.tabSwitcherManager
            if tabSwitcherManager.isActive {
                tabSwitcherManager.cancel()
                return nil
            }
            // Command Lens handles its own escape via CommandLensView.handleEscape()
            // which implements three-tiered behavior: clear text → exit mode → close
            if controller.windowState.showsAddressLens {
                controller.windowState.closeAddressLens()
                return nil
            }
            // Stop loading if the page is currently loading
            if controller.windowState.activeWebPage?.isLoading == true {
                controller.stopLoading()
                return nil
            }
        }

        // Extension shortcuts (checked after all system shortcuts)
        if let handler = extensionCommandHandler {
            let result = handler.handleKeyDown(event)
            if case .handled = result {
                return nil
            }
        }

        return event
    }

    private func handleFlagsChanged(_ event: NSEvent) -> NSEvent? {
        guard let windowManager,
              let controller = activeWindowController(for: event, windowManager: windowManager)
        else {
            return event
        }

        // Tab switcher: dismiss when Control key is released
        if controller.tabSwitcherManager.isActive, !event.modifierFlags.contains(.control) {
            controller.tabSwitcherManager.dismiss()
        }

        return event
    }

    // MARK: - Mouse Button Handling

    private func handleMouseButton(_ event: NSEvent) -> NSEvent? {
        guard let windowManager,
              let controller = activeWindowController(for: event, windowManager: windowManager)
        else { return event }

        // Button 3 = Back, Button 4 = Forward (standard multi-button mouse mapping)
        switch event.buttonNumber {
        case 3:
            controller.windowState.activeWebPage?.goBack()
            return nil
        case 4:
            controller.windowState.activeWebPage?.goForward()
            return nil
        default:
            return event
        }
    }

    // MARK: - Helpers

    /// Returns the window controller that should handle keyboard events.
    ///
    /// Only returns a controller if the event's window belongs to a browser window.
    /// This prevents handling events meant for other windows (Settings, Web Inspector, etc.).
    private func activeWindowController(
        for event: NSEvent,
        windowManager: WindowManager,
    ) -> RefraxWindowController? {
        guard let eventWindow = event.window else {
            return nil
        }

        // Check if the event's window is one of our browser windows
        if let controller = windowManager.windowControllers.first(where: { $0.window === eventWindow }) {
            return controller
        }

        // If the event window isn't a browser window, don't handle the shortcut.
        // This ensures shortcuts work correctly when focus is in other windows.
        return nil
    }
}
