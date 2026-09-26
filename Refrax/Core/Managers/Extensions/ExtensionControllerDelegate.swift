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
/// 2. **Tab Operations**: Opens the windows, tabs, and options pages extensions request
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

    private var state: BrowserState {
        manager.state
    }
    private var windowManager: WindowManager? {
        state.pagePool?.windowManager
    }
    private var tabManager: TabManager? {
        state.pagePool?.tabManager
    }
    private var pagePool: WebPagePool? {
        state.pagePool
    }

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

    /// Opens a window showing a space that holds the requested tabs.
    ///
    /// A Refrax window shows one space, so the window's tabs are its space's: tabs the
    /// extension names move into that space, and each of `tabURLs` opens as a new tab
    /// after them. The first of those tabs is selected.
    func webExtensionController(
        _: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for _: WKWebExtensionContext,
    ) async throws -> (any WKWebExtensionWindow)? {
        guard let windowManager, let tabManager else { return nil }

        let space = try space(forNewWindow: configuration.shouldBePrivate)
        let previousKeyWindow = NSApp.keyWindow

        var tabs = configuration.tabs.compactMap { ($0 as? RefraxExtensionTab)?.tab }
        tabManager.moveTabs(tabs.filter { $0.space?.id != space.id }, to: space)
        for url in configuration.tabURLs {
            tabs.append(tabManager.createTab(
                url: url,
                in: space,
                makeActive: false,
                loadImmediately: true,
                insertionStrategy: .append,
            ))
        }

        let controller = if let firstTab = tabs.first {
            windowManager.createWindow(with: space, activating: firstTab)
        } else {
            windowManager.createWindow(with: space)
        }
        guard let nsWindow = controller.window else { return nil }
        if !configuration.shouldBeFocused {
            previousKeyWindow?.makeKeyAndOrderFront(nil)
        }

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

    /// The space a new extension-requested window shows: the active window's space, or for a
    /// private window, a private space.
    ///
    /// - Throws: ``ExtensionError/noPrivateSpace`` when a private window is requested and no
    ///   private space exists.
    private func space(forNewWindow isPrivate: Bool) throws -> Space {
        let activeSpace = windowManager?.activeWindowController?.windowState.activeSpace
        let candidates = [activeSpace].compactMap(\.self) + state.spaces
        guard let space = candidates.first(where: { $0.dataStoreMode.isPrivate == isPrivate }) ?? (isPrivate ? nil : candidates.first) else {
            throw ExtensionError.noPrivateSpace
        }
        return space
    }

    // MARK: - Tab Management

    func webExtensionController(
        _: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for context: WKWebExtensionContext,
    ) async throws -> (any WKWebExtensionTab)? {
        guard let tabManager, let pagePool else { return nil }

        // The parent tab's space, else the space of the window the extension named, else the active one.
        let parentTab = (configuration.parentTab as? RefraxExtensionTab)?.tab
        let windowState = (configuration.window as? RefraxExtensionWindow)?.windowState
            ?? windowManager?.activeWindowController?.windowState
        guard let space = parentTab?.space ?? windowState?.activeSpace ?? state.spaces.first else { return nil }

        let url = configuration.url ?? .blank
        let tab = tabManager.createTab(
            url: url,
            in: space,
            groupID: parentTab?.groupID,
            isPinned: configuration.shouldBePinned,
            makeActive: false,
            loadImmediately: true,
            insertionStrategy: insertionStrategy(at: Int(configuration.index), in: space),
        )

        Logger.info(
            "Extension created new tab: \(url.absoluteString)",
            category: Logger.extensions,
        )

        let extensionTab = manager.extensionTab(for: tab.activePage, pagePool: pagePool)
        if configuration.shouldBeActive {
            try await extensionTab.activate(for: context)
        }
        if configuration.shouldBeMuted {
            try await extensionTab.setMuted(true, for: context)
        }
        return extensionTab
    }

    /// Where a tab lands to take `index` among its space's tabs, the index extensions see
    /// through ``RefraxExtensionWindow``. Past the end, it goes last.
    private func insertionStrategy(at index: Int, in space: Space) -> TabPositioner.InsertionStrategy {
        guard space.tabs.indices.contains(index) else { return .append }
        return .atPosition(space.tabs[index].position)
    }

    /// Shows the extension's options page: selects a tab already showing it, or opens one in
    /// the active window's space.
    func webExtensionController(
        _: WKWebExtensionController,
        openOptionsPageFor context: WKWebExtensionContext,
    ) async throws {
        guard let optionsPageURL = context.optionsPageURL else { throw ExtensionError.noOptionsPage }
        guard let tabManager, let pagePool else { throw ExtensionError.notInstalled }

        let existingPage = state.spaces.lazy.flatMap(\.tabs).flatMap(\.pages).first { page in
            ExtensionPageRouting.isSamePage(page.url, optionsPageURL)
        }
        let tabPage: TabPage
        if let existingPage {
            tabPage = existingPage
        } else {
            guard let space = windowManager?.activeWindowController?.windowState.activeSpace ?? state.spaces.first else {
                throw ExtensionError.notInstalled
            }
            tabPage = tabManager.createTab(
                url: optionsPageURL,
                in: space,
                makeActive: false,
                loadImmediately: true,
                insertionStrategy: .afterActive,
            ).activePage
        }

        try await manager.extensionTab(for: tabPage, pagePool: pagePool).activate(for: context)
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

    /// Shows the action's popup in WebKit's own popover, under the address bar of the
    /// active window.
    ///
    /// WebKit owns the popover and its web view: it installs their delegates, sizes the
    /// popover to the page's content, and routes links the popup opens to new tabs.
    func webExtensionController(
        _: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for extensionContext: WKWebExtensionContext,
    ) async throws {
        let extensionName = extensionContext.webExtension.displayName ?? "Unknown Extension"
        guard let popover = action.popupPopover else {
            Logger.warning("Extension '\(extensionName)' action has no popup", category: Logger.extensions)
            return
        }
        guard let controller = windowManager?.activeWindowController,
              let contentView = controller.window?.contentView
        else {
            throw PopupError.noWindow
        }

        let anchor = Self.popupAnchor(addressBar: controller.windowState.addressBarFrame, in: contentView)
        popover.show(relativeTo: anchor, of: contentView, preferredEdge: contentView.isFlipped ? .maxY : .minY)
    }

    private nonisolated enum PopupError: Error, LocalizedError {
        case noWindow

        var errorDescription: String? {
            "No browser window to show the popup in"
        }
    }

    /// The address bar's rectangle in `contentView`'s coordinates, or a point at the top
    /// center when the address bar is hidden.
    ///
    /// The address bar reports its frame in SwiftUI's global space, which has a top-left origin.
    private static func popupAnchor(addressBar frame: CGRect, in contentView: NSView) -> CGRect {
        let bounds = contentView.bounds
        guard !frame.isEmpty, bounds.contains(CGPoint(x: frame.midX, y: frame.midY)) else {
            let y = contentView.isFlipped ? bounds.minY + 40 : bounds.maxY - 40
            return CGRect(x: bounds.midX, y: y, width: 1, height: 1)
        }
        guard !contentView.isFlipped else { return frame }
        return CGRect(x: frame.minX, y: bounds.height - frame.maxY, width: frame.width, height: frame.height)
    }
}
