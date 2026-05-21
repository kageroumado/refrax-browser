import AppKit
import Foundation
import WebKit

/// Handles extension controller callbacks from WebKit.
///
/// This delegate implements `WKWebExtensionControllerDelegate` to respond to
/// extension requests for tabs, windows, permissions, and popups.
///
/// ## Delegate Responsibilities
///
/// 1. **Window/Tab Access**: Provides extensions with the current window/tab state
/// 2. **Tab Operations**: Creates new tabs when extensions request them
/// 3. **Permission Prompts**: Shows UI when extensions request additional permissions
/// 4. **Popup Display**: Presents extension popups in native popovers
///
/// ## Thread Safety
///
/// All delegate methods are called on the main actor by WebKit.
final class ExtensionControllerDelegate: NSObject, WKWebExtensionControllerDelegate {
    // MARK: - Properties

    /// The extension manager that owns this delegate.
    private unowned let manager: ExtensionManager

    // MARK: - Initialization

    /// Creates a controller delegate.
    ///
    /// - Parameter manager: The extension manager.
    init(manager: ExtensionManager) {
        self.manager = manager
        super.init()
    }

    // MARK: - Convenience Accessors

    private var state: BrowserState { manager.state }
    private var windowManager: WindowManager? { state.pagePool?.windowManager }
    private var tabManager: TabManager? { state.pagePool?.tabManager }
    private var pagePool: WebPagePool? { state.pagePool }

    // MARK: - Window Management

    func webExtensionController(
        _: WKWebExtensionController,
        openWindowsFor _: WKWebExtensionContext,
    ) -> [any WKWebExtensionWindow] {
        guard let windowManager else { return [] }

        return windowManager.windowControllers.compactMap { controller in
            guard let nsWindow = controller.window else { return nil }
            return manager.extensionWindow(for: controller.windowState, nsWindow: nsWindow)
        }
    }

    func webExtensionController(
        _: WKWebExtensionController,
        focusedWindowFor _: WKWebExtensionContext,
    ) -> (any WKWebExtensionWindow)? {
        guard let windowManager else { return nil }
        guard let controller = windowManager.activeWindowController,
              let nsWindow = controller.window else { return nil }

        return manager.extensionWindow(for: controller.windowState, nsWindow: nsWindow)
    }

    func webExtensionController(
        _: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for _: WKWebExtensionContext,
    ) async throws -> (any WKWebExtensionWindow)? {
        guard let windowManager else { return nil }

        let controller = windowManager.createWindow()
        guard let nsWindow = controller.window else { return nil }

        // Apply window frame if valid (NaN means not specified)
        let frame = configuration.frame
        if !frame.origin.x.isNaN, !frame.origin.y.isNaN,
           !frame.size.width.isNaN, !frame.size.height.isNaN {
            nsWindow.setFrame(frame, display: true)
        }

        switch configuration.windowState {
        case .minimized:
            nsWindow.miniaturize(nil)
        case .maximized:
            nsWindow.zoom(nil)
        case .fullscreen:
            nsWindow.toggleFullScreen(nil)
        default:
            break
        }

        return manager.extensionWindow(for: controller.windowState, nsWindow: nsWindow)
    }

    // MARK: - Tab Management

    func webExtensionController(
        _: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for _: WKWebExtensionContext,
    ) async throws -> (any WKWebExtensionTab)? {
        guard let tabManager, let pagePool else { return nil }

        // Get target space from specified window or active window
        let targetSpace: Space? = if let extensionWindow = configuration.window,
                                     let refraxWindow = extensionWindow as? RefraxExtensionWindow,
                                     let windowState = refraxWindow.windowState {
            state.space(for: windowState.activeSpaceID ?? UUID())
        } else {
            windowManager?.activeWindowController?.windowState.activeSpace
        }

        // Create the tab
        let url = configuration.url ?? .blank
        let tab = tabManager.createTab(
            url: url,
            in: targetSpace,
            makeActive: configuration.shouldBeActive,
        )

        Logger.info(
            "Extension created new tab: \(url.absoluteString)",
            category: Logger.extensions,
        )

        guard let tabPage = tab.pages.first else { return nil }
        return manager.extensionTab(for: tabPage, pagePool: pagePool)
    }

    // MARK: - Permission Prompts

    func webExtensionController(
        _: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in _: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
    ) async -> (Set<WKWebExtension.Permission>, Date?) {
        let extensionName = extensionContext.webExtension.displayName ?? "Unknown Extension"
        let extensionIcon = extensionContext.webExtension.icon(for: CGSize(width: 64, height: 64))

        Logger.info(
            "Extension '\(extensionName)' requested permissions: \(permissions)",
            category: Logger.extensions,
        )

        return await withCheckedContinuation { continuation in
            let request = PermissionRequest(
                extensionName: extensionName,
                extensionIcon: extensionIcon,
                requestType: .permissions(permissions),
                continuation: .permissions(continuation),
            )
            MainActor.assumeIsolated {
                manager.permissionPromptManager.enqueue(request)
            }
        }
    }

    func webExtensionController(
        _: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in _: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
    ) async -> (Set<URL>, Date?) {
        let extensionName = extensionContext.webExtension.displayName ?? "Unknown Extension"
        let extensionIcon = extensionContext.webExtension.icon(for: CGSize(width: 64, height: 64))

        Logger.info(
            "Extension '\(extensionName)' requested URL access: \(urls)",
            category: Logger.extensions,
        )

        return await withCheckedContinuation { continuation in
            let request = PermissionRequest(
                extensionName: extensionName,
                extensionIcon: extensionIcon,
                requestType: .urls(urls),
                continuation: .urls(continuation),
            )
            MainActor.assumeIsolated {
                manager.permissionPromptManager.enqueue(request)
            }
        }
    }

    func webExtensionController(
        _: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in _: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
    ) async -> (Set<WKWebExtension.MatchPattern>, Date?) {
        let extensionName = extensionContext.webExtension.displayName ?? "Unknown Extension"
        let extensionIcon = extensionContext.webExtension.icon(for: CGSize(width: 64, height: 64))

        Logger.info(
            "Extension '\(extensionName)' requested match patterns: \(matchPatterns)",
            category: Logger.extensions,
        )

        return await withCheckedContinuation { continuation in
            let request = PermissionRequest(
                extensionName: extensionName,
                extensionIcon: extensionIcon,
                requestType: .matchPatterns(matchPatterns),
                continuation: .matchPatterns(continuation),
            )
            MainActor.assumeIsolated {
                manager.permissionPromptManager.enqueue(request)
            }
        }
    }

    // MARK: - Extension Actions & Popups

    func webExtensionController(
        _: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for extensionContext: WKWebExtensionContext,
    ) async throws {
        let extensionName = extensionContext.webExtension.displayName ?? "Unknown Extension"
        let extensionIcon = extensionContext.webExtension.icon(for: CGSize(width: 32, height: 32))

        Logger.info(
            "Extension '\(extensionName)' wants to show popup",
            category: Logger.extensions,
        )

        // Get the popup web view from the action
        guard let popupWebView = action.popupWebView else {
            Logger.warning(
                "Extension '\(extensionName)' action has no popup web view",
                category: Logger.extensions,
            )
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            let request = ExtensionPopupRequest(
                extensionName: extensionName,
                extensionIcon: extensionIcon,
                popupWebView: popupWebView,
                continuation: continuation,
            )
            MainActor.assumeIsolated {
                manager.popupManager.enqueue(request)
            }
        }
    }

    // MARK: - Context Menu

    func webExtensionController(
        _: WKWebExtensionController,
        presentContextMenu _: [Any],
        for extensionContext: WKWebExtensionContext,
    ) async -> Any? {
        // Present extension context menu items
        Logger.info(
            "Extension '\(extensionContext.webExtension.displayName ?? "Unknown")' wants to show context menu",
            category: Logger.extensions,
        )

        // TODO: Implement context menu integration
        return nil
    }

    // MARK: - Notifications

    func webExtensionController(
        _: WKWebExtensionController,
        sendNotificationWithTitle title: String,
        subtitle _: String?,
        body _: String,
        iconURL _: URL?,
        for extensionContext: WKWebExtensionContext,
    ) async -> Bool {
        // Send a native notification for the extension
        Logger.info(
            "Extension '\(extensionContext.webExtension.displayName ?? "Unknown")' notification: \(title)",
            category: Logger.extensions,
        )

        // TODO: Implement notification delivery via UNUserNotificationCenter
        return false
    }
}
