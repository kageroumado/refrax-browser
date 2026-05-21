import Foundation
import WebKit

/// Adapter that implements WebKit's private `WKHistoryDelegatePrivate` protocol.
///
/// This adapter provides access to history-related events that aren't available
/// through the public `WKNavigationDelegate`:
/// - Title changes after page load (JavaScript `document.title = "..."`)
/// - Client-side redirects (JavaScript location changes)
/// - Server-side redirects with source and destination URLs
///
/// ## Usage
/// ```swift
/// let adapter = HistoryDelegateAdapter(historyManager: historyManager)
/// adapter.attach(to: wkWebView, tabID: tabPage.id)
/// ```
///
/// ## Why This Exists
/// The public `WKNavigationDelegate` only provides the title at page load
/// completion. Modern web apps frequently update titles via JavaScript after
/// load (e.g., email clients showing unread count, chat apps showing
/// new messages). This adapter tracks those changes.
final class HistoryDelegateAdapter: NSObject, WKHistoryDelegatePrivate {
    // MARK: - Properties

    private weak var webView: WKWebView?
    private let historyManager: HistoryManager
    private var tabID: UUID?

    /// Tracks the last title to avoid redundant updates.
    /// Title updates can fire at 10-50+ Hz on some pages even when unchanged.
    private var lastTitle: String?

    /// Callback invoked when JavaScript updates the page title.
    /// Used to sync title changes to the TabPage model.
    var onTitleChange: ((String) -> Void)?

    /// Callback invoked when a client-side redirect occurs (History API, meta refresh, etc.).
    /// Used to sync URL changes for SPAs that use `history.pushState()` instead of navigation.
    var onURLChange: ((URL) -> Void)?

    // MARK: - Initialization

    init(historyManager: HistoryManager) {
        self.historyManager = historyManager
        super.init()
    }

    // MARK: - Attachment

    /// Attaches the history delegate to a WKWebView.
    ///
    /// - Parameters:
    ///   - webView: The WKWebView to monitor.
    ///   - tabID: The tab ID for history entry updates.
    func attach(to webView: WKWebView, tabID: UUID) {
        self.webView = webView
        self.tabID = tabID
        lastTitle = nil

        webView._historyDelegate = self
    }

    /// Detaches from the current WKWebView.
    func detach() {
        guard let webView else { return }

        webView._historyDelegate = nil

        self.webView = nil
        tabID = nil
        lastTitle = nil
    }

    /// Updates the tab ID (call when the session is transferred to a new tab).
    func updateTabID(_ newTabID: UUID) {
        tabID = newTabID
    }
}

// MARK: - WKHistoryDelegatePrivate Conformance

extension HistoryDelegateAdapter {
    /// Called when the page title changes after initial load.
    ///
    /// This is triggered when JavaScript modifies `document.title`.
    /// Some pages fire this at 10-50+ Hz even when the title hasn't changed,
    /// so we deduplicate to avoid unnecessary history manager updates.
    func _webView(_: WKWebView, didUpdateHistoryTitle title: String, for _: URL) {
        guard let tabID else { return }
        guard title != lastTitle else { return }
        lastTitle = title
        historyManager.updateEntry(for: tabID, title: title)
        onTitleChange?(title)
    }

    /// Called when a client-side redirect occurs.
    ///
    /// Client-side redirects are caused by JavaScript navigation,
    /// `<meta http-equiv="refresh">`, or History API.
    ///
    /// SPAs like GitHub and YouTube use `history.pushState()` to update the URL
    /// without triggering a full navigation. This callback allows us to detect
    /// these URL changes and update the TabPage model accordingly.
    func _webView(
        _: WKWebView,
        didPerformClientRedirectFrom _: URL,
        to destinationURL: URL,
    ) {
        onURLChange?(destinationURL)
    }

    /// Called when a server-side redirect occurs (HTTP 3xx).
    func _webView(
        _: WKWebView,
        didPerformServerRedirectFrom _: URL,
        to _: URL,
    ) {
        // Debug-only: redirects are tracked but not logged
    }

    /// Called when a navigation completes with navigation data.
    func _webView(_: WKWebView, didNavigateWithNavigationData _: WKNavigationData) {
        // Debug-only: navigation data tracked but not logged
    }
}
