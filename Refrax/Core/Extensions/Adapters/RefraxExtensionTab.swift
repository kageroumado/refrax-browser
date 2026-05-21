import AppKit
import Foundation
import WebKit

/// Bridges a Refrax `TabPage` to WebKit's extension tab interface.
///
/// This adapter implements `WKWebExtensionTab` to expose Refrax's tab model
/// to browser extensions. Extensions can query tab properties (URL, title, status)
/// and perform actions (activate, reload, close).
///
/// ## Lifecycle
///
/// Tab adapters are created by `ExtensionManager.extensionTab(for:)` and cached
/// for the lifetime of the `TabPage`. When the tab closes, `ExtensionManager`
/// removes the adapter.
///
/// ## Thread Safety
///
/// All methods are called on the main actor by WebKit's extension system.

final class RefraxExtensionTab: NSObject, WKWebExtensionTab {
    // MARK: - Properties

    /// The tab page this adapter represents.
    weak var tabPage: TabPage?

    /// The parent tab, derived from tabPage.
    var tab: Tab? { tabPage?.tab }

    /// The web page pool for accessing active WebViews.
    private weak var pagePool: WebPagePool?

    /// The extension manager for window adapter access.
    private weak var manager: ExtensionManager?

    // MARK: - Initialization

    /// Creates a tab adapter.
    ///
    /// - Parameters:
    ///   - tabPage: The tab page to adapt.
    ///   - pagePool: The web page pool for WebView access.
    ///   - manager: The extension manager.
    init(tabPage: TabPage, pagePool: WebPagePool, manager: ExtensionManager) {
        self.tabPage = tabPage
        self.pagePool = pagePool
        self.manager = manager
        super.init()
    }

    // MARK: - WKWebExtensionTab Protocol

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        guard let tab, let space = tab.space else { return nil }
        guard let manager, let pagePool else { return nil }

        // Don't expose window if this is a private space and extension isn't allowed
        if space.dataStoreMode.isPrivate, !isExtensionAllowedInPrivateMode(context, manager: manager) {
            return nil
        }

        // Find the window showing this tab's space
        guard let windowManager = pagePool.windowManager else { return nil }
        for controller in windowManager.windowControllers {
            if controller.windowState.activeSpaceID == space.id,
               let nsWindow = controller.window {
                return manager.extensionWindow(for: controller.windowState, nsWindow: nsWindow)
            }
        }
        return nil
    }

    func mainWebView(for _: WKWebExtensionContext) -> WKWebView? {
        guard let tabPage else { return nil }
        return pagePool?.existingPage(for: tabPage.id)?.backingWebView
    }

    func tabTitle(for _: WKWebExtensionContext) -> String? {
        tabPage?.title
    }

    func url(for _: WKWebExtensionContext) -> URL? {
        tabPage?.url
    }

    func isPinned(for _: WKWebExtensionContext) -> Bool {
        tab?.isPinned ?? false
    }

    func isReaderModeAvailable(for _: WKWebExtensionContext) -> Bool {
        // Reader mode detection requires implementation
        false
    }

    func isShowingReaderMode(for _: WKWebExtensionContext) -> Bool {
        false
    }

    func isPlayingAudio(for _: WKWebExtensionContext) -> Bool {
        guard let tabPage, let page = pagePool?.existingPage(for: tabPage.id) else {
            return false
        }
        return page.audioState == .playing
    }

    func isMuted(for _: WKWebExtensionContext) -> Bool {
        guard let tabPage, let page = pagePool?.existingPage(for: tabPage.id) else {
            return false
        }
        return page.audioState == .muted
    }

    func size(for _: WKWebExtensionContext) -> CGSize {
        guard let tabPage, let page = pagePool?.existingPage(for: tabPage.id) else {
            return .zero
        }
        return page.backingWebView.frame.size
    }

    func isLoadingComplete(for _: WKWebExtensionContext) -> Bool {
        guard let tabPage, let page = pagePool?.existingPage(for: tabPage.id) else {
            return true // No page means nothing is loading
        }
        return !page.isLoading
    }

    func zoomFactor(for _: WKWebExtensionContext) -> Double {
        guard let tabPage, let page = pagePool?.existingPage(for: tabPage.id) else {
            return 1.0
        }
        return Double(page.backingWebView.pageZoom)
    }

    // MARK: - Actions

    func activate(for _: WKWebExtensionContext) async throws {
        guard let tab, let pagePool else {
            throw ExtensionError.notInstalled
        }
        guard let tabManager = pagePool.tabManager,
              let windowManager = pagePool.windowManager else {
            throw ExtensionError.notInstalled
        }

        // Find the window showing this tab's space
        if let space = tab.space {
            for controller in windowManager.windowControllers {
                if controller.windowState.activeSpaceID == space.id {
                    tabManager.setActiveTab(tab, in: controller.windowState)
                    return
                }
            }
        }
        // Fallback: use active window
        if let activeController = windowManager.activeWindowController {
            tabManager.setActiveTab(tab, in: activeController.windowState)
        }
    }

    func select(for context: WKWebExtensionContext) async throws {
        // In Refrax, select and activate are the same operation
        try await activate(for: context)
    }

    func deselect(for _: WKWebExtensionContext) async throws {
        // No-op in single-selection model
    }

    func duplicate(
        for _: WKWebExtensionContext,
        with options: WKWebExtension.TabConfiguration?,
    ) async throws -> any WKWebExtensionTab {
        guard let tab, let tabPage, let pagePool else {
            throw ExtensionError.notInstalled
        }
        guard let tabManager = pagePool.tabManager else {
            throw ExtensionError.notInstalled
        }

        // Create duplicate tab with same URL
        let newTab = tabManager.createTab(
            url: tabPage.url,
            in: tab.space,
            makeActive: options?.shouldBeActive ?? false,
        )

        // Return adapter for new tab
        guard let manager, let newPage = newTab.pages.first else {
            throw ExtensionError.notInstalled
        }
        return manager.extensionTab(for: newPage, pagePool: pagePool)
    }

    func close(for _: WKWebExtensionContext) async throws {
        guard let tab, let pagePool else { return }
        guard let tabManager = pagePool.tabManager else { return }
        tabManager.closeTab(tab)
    }

    func reload(for _: WKWebExtensionContext, fromOrigin: Bool) async throws {
        guard let tabPage else { return }
        guard let page = pagePool?.existingPage(for: tabPage.id) else { return }

        // reload(fromOrigin:) returns an AsyncSequence, but we don't need to await it
        // The navigation will proceed asynchronously
        _ = page.reload(fromOrigin: fromOrigin)
    }

    func goBack(for _: WKWebExtensionContext) async throws {
        guard let tabPage else { return }
        guard let page = pagePool?.existingPage(for: tabPage.id) else { return }
        page.goBack()
    }

    func goForward(for _: WKWebExtensionContext) async throws {
        guard let tabPage else { return }
        guard let page = pagePool?.existingPage(for: tabPage.id) else { return }
        page.goForward()
    }

    func loadURL(_ url: URL, for _: WKWebExtensionContext) async throws {
        guard let tabPage else { return }

        // Update the tabPage URL first
        tabPage.url = url

        // Load in the WebPage if it exists
        if let page = pagePool?.existingPage(for: tabPage.id) {
            _ = page.load(url)
        }
    }

    func toggleReaderMode(for _: WKWebExtensionContext) async throws {
        // Reader mode not yet implemented
    }

    func detectWebpageLocale(for _: WKWebExtensionContext) async throws -> Locale? {
        guard let tabPage else { return nil }
        guard let page = pagePool?.existingPage(for: tabPage.id) else { return nil }

        // Use WebKit's language detection if available
        if let languageCode = page.backingWebView._pageLanguage {
            return Locale(identifier: languageCode)
        }
        return nil
    }

    func setZoomFactor(_ zoomFactor: Double, for _: WKWebExtensionContext) async throws {
        guard let tabPage else { return }
        guard let page = pagePool?.existingPage(for: tabPage.id) else { return }
        page.backingWebView.pageZoom = CGFloat(zoomFactor)
    }

    func setMuted(_ muted: Bool, for _: WKWebExtensionContext) async throws {
        guard let tabPage else { return }
        guard let page = pagePool?.existingPage(for: tabPage.id) else { return }

        // Use toggle if current state doesn't match desired state
        if page.audioState.isMuted != muted {
            page.toggleAudioMute()
        }
    }

    func setPinned(_ pinned: Bool, for _: WKWebExtensionContext) async throws {
        guard let tab else { return }
        tab.isPinned = pinned
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

// MARK: - Private WKWebView Extensions

private extension WKWebView {
    /// Private WebKit API for page language detection.
    var _pageLanguage: String? {
        value(forKey: "_pageLanguage") as? String
    }
}
