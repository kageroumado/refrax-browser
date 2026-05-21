import AppKit
import Observation
import WebKit

// MARK: - WebInspectorManager

/// Manages Web Inspector lifecycle and docking for WKWebViews.
///
/// All action methods require an explicit `WKWebView` parameter — the manager does not
/// cache webView references, eliminating fragile weak-reference state. Inspector state
/// (shown/attached/side) is tracked per-tab for menu updates and restoration on tab switch.
///
/// Developer extras are always enabled at WKWebView configuration time, so `_inspector`
/// is available whenever the web process is running.
///
/// ## Tab Lifecycle
///
/// The manager tracks inspector state per-tab and restores it when tabs are
/// re-selected. Notify the manager of tab visibility changes:
///
/// ```swift
/// inspectorManager.tabDidBecomeVisible(tabPage.id, webView: webView)
/// inspectorManager.tabWillBecomeHidden(tabPage.id, webView: webView)
/// inspectorManager.tabDidClose(tabPage.id, webView: webView)
/// ```
@Observable
final class WebInspectorManager {
    // MARK: - Types

    /// Attachment side for docked inspector.
    enum AttachmentSide: Int, CaseIterable, Sendable {
        /// Inspector docked at bottom of web view.
        case bottom = 0

        /// Inspector docked at right side of web view.
        case right = 1
    }

    /// Inspector state for a single tab (UI state only, no webView reference).
    private struct InspectorState {
        /// Whether the inspector was explicitly shown by the user.
        var isShown: Bool = false

        /// Whether the inspector is attached (docked) to the web view.
        var isAttached: Bool = false

        /// The attachment side when docked.
        var attachmentSide: AttachmentSide = .bottom
    }

    // MARK: - Dependencies

    /// Delegate for handling inspector-initiated URL opening.
    @ObservationIgnored
    weak var urlHandler: (any WebInspectorURLHandler)?

    // MARK: - State

    /// Per-tab inspector state tracking.
    private var inspectorStates: [TabPage.ID: InspectorState] = [:]

    /// Inspector delegate handlers keyed by web view.
    ///
    /// Using NSMapTable with weak keys to automatically clean up when web views are deallocated.
    private var delegateHandlers = NSMapTable<WKWebView, InspectorDelegateHandler>.weakToStrongObjects()

    // MARK: - Initialization

    /// Creates an inspector manager.
    init() {}

    // MARK: - Public API

    /// Shows the Web Inspector for a tab.
    ///
    /// - Parameters:
    ///   - tabPageID: The TabPage ID to show the inspector for.
    ///   - webView: The WKWebView to inspect.
    ///   - attached: If `true`, docks the inspector. If `false`, detaches. If `nil` (default),
    ///               respects WebKit's stored preference (user's last choice).
    func showInspector(for tabPageID: TabPage.ID, webView: WKWebView, attached: Bool? = nil) {
        guard let inspector = prepareInspector(on: webView) else {
            Logger.warning(
                "Cannot show inspector: web process not running for TabPage \(tabPageID)",
                category: Logger.webview,
            )
            return
        }

        let side = inspectorStates[tabPageID]?.attachmentSide ?? .bottom
        let willBeAttached = configureAttachmentPreference(attached: attached, side: side)

        inspector.show()

        ensureState(for: tabPageID)
        inspectorStates[tabPageID]?.isShown = true
        inspectorStates[tabPageID]?.isAttached = willBeAttached

        Logger.debug(
            "Opened Web Inspector (\(willBeAttached ? "attached" : "detached")) for TabPage \(tabPageID)",
            category: Logger.webview,
        )
    }

    /// Closes the Web Inspector for a tab.
    ///
    /// - Parameters:
    ///   - tabPageID: The TabPage ID to close the inspector for.
    ///   - webView: The WKWebView whose inspector to close.
    func closeInspector(for tabPageID: TabPage.ID, webView: WKWebView) {
        if let inspector = webView._inspector {
            inspector.close()
        }

        inspectorStates[tabPageID]?.isShown = false
        inspectorStates[tabPageID]?.isAttached = false
    }

    /// Toggles the Web Inspector visibility for a tab.
    ///
    /// - Parameters:
    ///   - tabPageID: The TabPage ID to toggle the inspector for.
    ///   - webView: The WKWebView to inspect.
    ///   - attached: If showing, whether to dock the inspector.
    func toggleInspector(for tabPageID: TabPage.ID, webView: WKWebView, attached: Bool = false) {
        if isInspectorShown(for: tabPageID) {
            closeInspector(for: tabPageID, webView: webView)
        } else {
            showInspector(for: tabPageID, webView: webView, attached: attached)
        }
    }

    /// Attaches (docks) the inspector to the web view.
    ///
    /// If the inspector is not visible, it will be shown attached.
    ///
    /// - Parameters:
    ///   - tabPageID: The TabPage ID.
    ///   - webView: The WKWebView to inspect.
    ///   - side: The side to dock to. Default is `.bottom`.
    func attachInspector(for tabPageID: TabPage.ID, webView: WKWebView, side: AttachmentSide = .bottom) {
        guard let inspector = prepareInspector(on: webView) else { return }

        ensureState(for: tabPageID)
        inspectorStates[tabPageID]?.attachmentSide = side
        configureInspectorToOpenAttached(side: side)

        if inspector.isVisible {
            inspector.attach()
        } else {
            showInspector(for: tabPageID, webView: webView, attached: true)
        }

        inspectorStates[tabPageID]?.isAttached = true
    }

    /// Detaches the inspector to a floating window.
    ///
    /// - Parameters:
    ///   - tabPageID: The TabPage ID.
    ///   - webView: The WKWebView whose inspector to detach.
    func detachInspector(for tabPageID: TabPage.ID, webView: WKWebView) {
        if let inspector = webView._inspector, inspector.isVisible {
            inspector.detach()
        }

        inspectorStates[tabPageID]?.isAttached = false
    }

    /// Toggles between attached and detached states.
    ///
    /// - Parameters:
    ///   - tabPageID: The TabPage ID.
    ///   - webView: The WKWebView to inspect.
    func toggleAttachment(for tabPageID: TabPage.ID, webView: WKWebView) {
        let state = inspectorStates[tabPageID]

        if state?.isAttached == true {
            detachInspector(for: tabPageID, webView: webView)
        } else {
            attachInspector(for: tabPageID, webView: webView, side: state?.attachmentSide ?? .bottom)
        }
    }

    /// Shows the JavaScript console panel in the inspector.
    ///
    /// - Parameters:
    ///   - tabPageID: The TabPage ID.
    ///   - webView: The WKWebView to inspect.
    ///   - attached: If `true`, docks the inspector. If `false`, detaches. If `nil` (default),
    ///               respects WebKit's stored preference.
    func showJavaScriptConsole(for tabPageID: TabPage.ID, webView: WKWebView, attached: Bool? = nil) {
        guard let inspector = prepareInspector(on: webView) else { return }

        let side = inspectorStates[tabPageID]?.attachmentSide ?? .bottom
        let willBeAttached = configureAttachmentPreference(attached: attached, side: side)

        inspector.showConsole()

        ensureState(for: tabPageID)
        inspectorStates[tabPageID]?.isShown = true
        inspectorStates[tabPageID]?.isAttached = willBeAttached
    }

    /// Shows the page resources panel in the inspector.
    ///
    /// - Parameters:
    ///   - tabPageID: The TabPage ID.
    ///   - webView: The WKWebView to inspect.
    ///   - attached: If `true`, docks the inspector. If `false`, detaches. If `nil` (default),
    ///               respects WebKit's stored preference.
    func showPageResources(for tabPageID: TabPage.ID, webView: WKWebView, attached: Bool? = nil) {
        guard let inspector = prepareInspector(on: webView) else { return }

        let side = inspectorStates[tabPageID]?.attachmentSide ?? .bottom
        let willBeAttached = configureAttachmentPreference(attached: attached, side: side)

        inspector.showResources()

        ensureState(for: tabPageID)
        inspectorStates[tabPageID]?.isShown = true
        inspectorStates[tabPageID]?.isAttached = willBeAttached
    }

    /// Shows the page source in the inspector.
    ///
    /// - Parameters:
    ///   - tabPageID: The TabPage ID.
    ///   - webView: The WKWebView to inspect.
    ///   - attached: If `true`, docks the inspector. If `false`, detaches. If `nil` (default),
    ///               respects WebKit's stored preference.
    func showPageSource(for tabPageID: TabPage.ID, webView: WKWebView, attached: Bool? = nil) {
        guard let inspector = prepareInspector(on: webView) else { return }

        let side = inspectorStates[tabPageID]?.attachmentSide ?? .bottom
        let willBeAttached = configureAttachmentPreference(attached: attached, side: side)

        inspector.show()
        inspector.showResources()

        ensureState(for: tabPageID)
        inspectorStates[tabPageID]?.isShown = true
        inspectorStates[tabPageID]?.isAttached = willBeAttached
    }

    /// Toggles page profiling (Timeline Recording).
    ///
    /// - Parameters:
    ///   - tabPageID: The TabPage ID.
    ///   - webView: The WKWebView to inspect.
    func togglePageProfiling(for tabPageID: TabPage.ID, webView: WKWebView) {
        guard let inspector = prepareInspector(on: webView) else { return }

        if !inspector.isVisible {
            showInspector(for: tabPageID, webView: webView)
        }

        inspector.togglePageProfiling()
    }

    /// Toggles element selection mode.
    ///
    /// - Parameters:
    ///   - tabPageID: The TabPage ID.
    ///   - webView: The WKWebView to inspect.
    func toggleElementSelection(for tabPageID: TabPage.ID, webView: WKWebView) {
        guard let inspector = prepareInspector(on: webView) else { return }

        if !inspector.isVisible {
            showInspector(for: tabPageID, webView: webView)
        }

        inspector.toggleElementSelection()
    }

    // MARK: - State Queries

    /// Checks if page profiling is currently active.
    ///
    /// - Parameters:
    ///   - tabPageID: The TabPage ID.
    ///   - webView: The WKWebView to check.
    /// - Returns: `true` if profiling is active.
    func isProfilingPage(for tabPageID: TabPage.ID, webView: WKWebView) -> Bool {
        webView._inspector?.isProfilingPage ?? false
    }

    /// Checks if element selection mode is active.
    ///
    /// - Parameters:
    ///   - tabPageID: The TabPage ID.
    ///   - webView: The WKWebView to check.
    /// - Returns: `true` if element selection is active.
    func isElementSelectionActive(for tabPageID: TabPage.ID, webView: WKWebView) -> Bool {
        webView._inspector?.isElementSelectionActive ?? false
    }

    /// Checks if the inspector is currently shown.
    ///
    /// Uses tracked state — does not require a webView.
    ///
    /// - Parameter tabPageID: The TabPage ID.
    /// - Returns: `true` if the inspector is visible.
    func isInspectorShown(for tabPageID: TabPage.ID) -> Bool {
        inspectorStates[tabPageID]?.isShown ?? false
    }

    /// Checks if the inspector is currently attached (docked).
    ///
    /// - Parameter tabPageID: The TabPage ID.
    /// - Returns: `true` if the inspector is docked.
    func isInspectorAttached(for tabPageID: TabPage.ID) -> Bool {
        inspectorStates[tabPageID]?.isAttached ?? false
    }

    /// Gets the current attachment side.
    ///
    /// - Parameter tabPageID: The TabPage ID.
    /// - Returns: The attachment side, or `.bottom` if not set.
    func attachmentSide(for tabPageID: TabPage.ID) -> AttachmentSide {
        inspectorStates[tabPageID]?.attachmentSide ?? .bottom
    }

    // MARK: - Tab Lifecycle Events

    /// Called when a tab becomes visible (selected).
    ///
    /// Restores the inspector if it was previously shown.
    ///
    /// - Parameters:
    ///   - tabPageID: The TabPage ID.
    ///   - webView: The WKWebView for the tab.
    func tabDidBecomeVisible(_ tabPageID: TabPage.ID, webView: WKWebView) {
        let previousState = inspectorStates[tabPageID]
        let wasShown = previousState?.isShown ?? false
        let wasAttached = previousState?.isAttached ?? false
        let attachmentSide = previousState?.attachmentSide ?? .bottom

        // Ensure state exists
        if inspectorStates[tabPageID] == nil {
            inspectorStates[tabPageID] = InspectorState()
        }

        // Restore inspector if it was shown
        guard wasShown else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))

            guard let inspector = webView._inspector else { return }

            if !inspector.isVisible {
                self.installDelegateIfNeeded(on: webView, inspector: inspector)

                if wasAttached {
                    self.configureInspectorToOpenAttached(side: attachmentSide)
                } else {
                    self.configureInspectorToOpenDetached()
                }

                inspector.show()

                Logger.debug(
                    "Restored Web Inspector (\(wasAttached ? "attached" : "detached")) for TabPage \(tabPageID)",
                    category: Logger.webview,
                )
            }
        }
    }

    /// Called when a tab is about to become hidden (deselected).
    ///
    /// Removes inspector views from the hierarchy to prevent them from
    /// becoming orphaned or appearing on wrong tabs.
    ///
    /// - Parameters:
    ///   - tabPageID: The TabPage ID.
    ///   - webView: The WKWebView for the tab.
    func tabWillBecomeHidden(_ tabPageID: TabPage.ID, webView: WKWebView) {
        guard let superview = webView.superview else { return }
        removeInspectorFromHierarchy(in: superview)
    }

    /// Called when a tab is being closed.
    ///
    /// - Parameters:
    ///   - tabPageID: The TabPage ID.
    ///   - webView: The WKWebView for the tab.
    func tabDidClose(_ tabPageID: TabPage.ID, webView: WKWebView) {
        if let inspector = webView._inspector, inspector.isVisible {
            inspector.close()
        }

        inspectorStates.removeValue(forKey: tabPageID)
    }

    /// Called when a tab is being closed (without webView access).
    ///
    /// - Parameter tabPageID: The TabPage ID.
    func tabDidClose(_ tabPageID: TabPage.ID) {
        inspectorStates.removeValue(forKey: tabPageID)
    }

    /// Closes all open inspectors.
    ///
    /// Since the manager doesn't hold webView references, this only clears
    /// tracked state. WebKit will close inspector windows when webViews are deallocated.
    func closeAllInspectors() {
        inspectorStates.removeAll()
    }

    // MARK: - Private Implementation

    /// WebKit UserDefaults keys for inspector preferences.
    private enum Preferences {
        static let startsAttached = "__WebInspectorPageGroupLevel1__.WebKit2InspectorStartsAttached"
        static let attachmentSide = "__WebInspectorPageGroupLevel1__.WebKit2InspectorAttachmentSide"
    }

    /// Prepares a webView's inspector for use: installs delegate if needed and returns the inspector.
    ///
    /// - Parameter webView: The WKWebView to prepare.
    /// - Returns: The `_WKInspector` instance, or `nil` if the web process isn't running.
    private func prepareInspector(on webView: WKWebView) -> _WKInspector? {
        guard let inspector = webView._inspector else { return nil }
        installDelegateIfNeeded(on: webView, inspector: inspector)
        return inspector
    }

    /// Ensures an `InspectorState` exists for the given tab, creating one if needed.
    private func ensureState(for tabPageID: TabPage.ID) {
        if inspectorStates[tabPageID] == nil {
            inspectorStates[tabPageID] = InspectorState()
        }
    }

    /// Configures the inspector to open detached.
    private func configureInspectorToOpenDetached() {
        UserDefaults.standard.set(false, forKey: Preferences.startsAttached)
    }

    /// Configures the inspector to open attached at the specified side.
    private func configureInspectorToOpenAttached(side: AttachmentSide) {
        UserDefaults.standard.set(true, forKey: Preferences.startsAttached)
        UserDefaults.standard.set(side.rawValue, forKey: Preferences.attachmentSide)
    }

    /// Configures attachment preference and returns the resulting attachment state.
    ///
    /// - Parameters:
    ///   - attached: If `true`, configures for attached. If `false`, configures for detached.
    ///               If `nil`, reads WebKit's stored preference (user's last choice).
    ///   - side: The attachment side to use when attaching.
    /// - Returns: Whether the inspector will be attached based on the configuration.
    private func configureAttachmentPreference(attached: Bool?, side: AttachmentSide) -> Bool {
        if let attached {
            if attached {
                configureInspectorToOpenAttached(side: side)
            } else {
                configureInspectorToOpenDetached()
            }
            return attached
        } else {
            return UserDefaults.standard.bool(forKey: Preferences.startsAttached)
        }
    }

    /// Installs the delegate on the inspector.
    private func installDelegateIfNeeded(on webView: WKWebView, inspector: _WKInspector) {
        guard delegateHandlers.object(forKey: webView) == nil else { return }

        let handler = InspectorDelegateHandler(manager: self)
        inspector.delegate = handler
        delegateHandlers.setObject(handler, forKey: webView)
    }

    /// Removes inspector views from hierarchy to prevent orphaning.
    private func removeInspectorFromHierarchy(in container: NSView) {
        for subview in container.subviews where subview.className.contains("WKInspector") {
            subview.removeFromSuperview()
        }
    }
}

// MARK: - Inspector Delegate Handler

/// Handles inspector delegate callbacks.
private final class InspectorDelegateHandler: NSObject, _WKInspectorDelegate {
    weak var manager: WebInspectorManager?

    init(manager: WebInspectorManager) {
        self.manager = manager
        super.init()
    }

    nonisolated func inspector(_: _WKInspector, openURLExternally url: URL) {
        MainActor.assumeIsolated {
            manager?.urlHandler?.openURLFromInspector(url)
        }
    }

    func inspectorFrontendLoaded(_: _WKInspector) {
        // Can be used for additional setup after inspector frontend loads
    }
}

// MARK: - URL Handler Protocol

/// Protocol for handling URLs opened from the Web Inspector.
protocol WebInspectorURLHandler: AnyObject {
    /// Opens a URL that was requested by the Web Inspector.
    ///
    /// Typically this should open the URL in a new tab or window.
    ///
    /// - Parameter url: The URL to open.
    func openURLFromInspector(_ url: URL)
}
