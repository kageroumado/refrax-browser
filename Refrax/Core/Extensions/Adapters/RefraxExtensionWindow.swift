import AppKit
import Foundation
import WebKit

/// Bridges a Refrax window to WebKit's extension window interface.
///
/// This adapter implements `WKWebExtensionWindow` to expose Refrax's window model
/// to browser extensions. Extensions can query window properties (state, tabs)
/// and perform actions (focus, resize, close).
///
/// ## Space Mapping
///
/// In Refrax, each window shows one space at a time. The extension sees tabs from
/// the currently active space only. When the user switches spaces, the tab list
/// changes accordingly.
///
/// ## Thread Safety
///
/// All methods are called on the main actor by WebKit's extension system.

final class RefraxExtensionWindow: NSObject, WKWebExtensionWindow {
    // MARK: - Properties

    /// The window state this adapter represents.
    weak var windowState: WindowState?

    /// The underlying AppKit window.
    weak var nsWindow: NSWindow?

    /// The browser state for tab access.
    private weak var state: BrowserState?

    /// The extension manager for tab adapter access.
    private weak var manager: ExtensionManager?

    // MARK: - Initialization

    /// Creates a window adapter.
    ///
    /// - Parameters:
    ///   - windowState: The window state to adapt.
    ///   - nsWindow: The underlying AppKit window.
    ///   - state: The browser state.
    ///   - manager: The extension manager.
    init(
        windowState: WindowState,
        nsWindow: NSWindow,
        state: BrowserState,
        manager: ExtensionManager,
    ) {
        self.windowState = windowState
        self.nsWindow = nsWindow
        self.state = state
        self.manager = manager
        super.init()
    }

    // MARK: - WKWebExtensionWindow Protocol

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        guard let windowState, let state, let manager, let pagePool = state.pagePool else {
            return []
        }

        // Get the active space's tabs
        guard let activeSpaceID = windowState.activeSpaceID,
              let space = state.space(for: activeSpaceID) else {
            return []
        }

        // Filter out tabs from private spaces if extension isn't allowed in private mode
        if space.dataStoreMode.isPrivate, !isExtensionAllowedInPrivateMode(context, manager: manager) {
            return []
        }

        return space.tabs.compactMap { tab in
            guard let page = tab.pages.first else { return nil }
            return manager.extensionTab(for: page, pagePool: pagePool)
        }
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard let windowState, let state, let manager, let pagePool = state.pagePool else {
            return nil
        }

        guard let activeSpaceID = windowState.activeSpaceID,
              let space = state.space(for: activeSpaceID) else {
            return nil
        }

        // Don't expose tabs from private spaces if extension isn't allowed
        if space.dataStoreMode.isPrivate, !isExtensionAllowedInPrivateMode(context, manager: manager) {
            return nil
        }

        // Try to get the explicitly active tab
        if let activeTabID = windowState.activeTabID(for: activeSpaceID),
           let tab = state.tab(for: activeTabID),
           let page = tab.pages.first {
            return manager.extensionTab(for: page, pagePool: pagePool)
        }

        // Fallback: return first tab as active to satisfy WebKit's expectation that
        // activeTab should be in the tabs array. This avoids log spam when Refrax
        // has no explicit active tab (which is a valid state in our UI).
        if let firstTab = space.tabs.first,
           let page = firstTab.pages.first {
            return manager.extensionTab(for: page, pagePool: pagePool)
        }

        return nil
    }

    func windowType(for _: WKWebExtensionContext) -> WKWebExtension.WindowType {
        // Refrax only has normal windows currently
        .normal
    }

    func windowState(for _: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let nsWindow else { return .normal }

        if nsWindow.isMiniaturized {
            return .minimized
        }
        if nsWindow.styleMask.contains(.fullScreen) {
            return .fullscreen
        }
        if nsWindow.isZoomed {
            return .maximized
        }
        return .normal
    }

    func isPrivate(for _: WKWebExtensionContext) -> Bool {
        guard let windowState, let state else { return false }
        guard let activeSpaceID = windowState.activeSpaceID,
              let space = state.space(for: activeSpaceID) else { return false }
        // A window is private if the space uses non-global data storage
        return !space.dataStoreMode.isGlobal
    }

    func frame(for _: WKWebExtensionContext) -> CGRect {
        nsWindow?.frame ?? .zero
    }

    func screenFrame(for _: WKWebExtensionContext) -> CGRect {
        nsWindow?.screen?.frame ?? NSScreen.main?.frame ?? .zero
    }

    // MARK: - Actions

    func focus(for _: WKWebExtensionContext) async throws {
        guard let nsWindow else { return }
        nsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close(for _: WKWebExtensionContext) async throws {
        guard let nsWindow else { return }
        nsWindow.performClose(nil)
    }

    func setWindowState(
        _ state: WKWebExtension.WindowState,
        for _: WKWebExtensionContext,
    ) async throws {
        guard let nsWindow else { return }

        switch state {
        case .normal:
            if nsWindow.isMiniaturized {
                nsWindow.deminiaturize(nil)
            }
            if nsWindow.styleMask.contains(.fullScreen) {
                nsWindow.toggleFullScreen(nil)
            }
            if nsWindow.isZoomed {
                nsWindow.zoom(nil)
            }

        case .minimized:
            nsWindow.miniaturize(nil)

        case .maximized:
            if !nsWindow.isZoomed {
                nsWindow.zoom(nil)
            }

        case .fullscreen:
            if !nsWindow.styleMask.contains(.fullScreen) {
                nsWindow.toggleFullScreen(nil)
            }

        @unknown default:
            break
        }
    }

    func setFrame(
        _ frame: CGRect,
        for _: WKWebExtensionContext,
    ) async throws {
        guard let nsWindow else { return }
        nsWindow.setFrame(frame, display: true, animate: true)
    }

    // MARK: - Private Helpers

    /// Checks if an extension is allowed in private mode.
    ///
    /// - Parameters:
    ///   - context: The extension context to check.
    ///   - manager: The extension manager.
    /// - Returns: `true` if the extension is allowed in private mode.
    private func isExtensionAllowedInPrivateMode(
        _ context: WKWebExtensionContext,
        manager: ExtensionManager,
    ) -> Bool {
        let extensionID = context.uniqueIdentifier
        return manager.installedExtensions.first { $0.uniqueIdentifier == extensionID }?.allowedInPrivateMode ?? false
    }
}
