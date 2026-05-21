import AppKit
import Observation
import WebKit

/// Manages web view display state across multiple windows.
///
/// `RefraxWebViewManager` coordinates which window has the "active" (interactive)
/// display of a tab when the same tab is visible in multiple windows. It also
/// provides facilities for creating screen share windows that mirror tab content.
///
/// ## Multi-Window Coordination
///
/// When a tab is displayed in multiple windows, only one can be interactive.
/// The manager tracks which window owns active display:
///
/// ```swift
/// // Window requests active display
/// manager.requestActiveDisplay(for: page, in: windowID)
///
/// // Check if this window has active display
/// let isActive = manager.hasActiveDisplay(for: page, in: windowID)
/// ```
///
/// ## Screen Share Windows
///
/// The manager can create dedicated windows for screen sharing a single tab:
///
/// ```swift
/// let shareWindow = manager.createScreenShareWindow(for: page)
/// // User can then share just this window
/// ```
///
/// ## Thread Safety
///
/// All operations must be performed on the main actor.
@Observable
final class RefraxWebViewManager {
    // MARK: - Types

    /// Identifier for a window.
    typealias WindowID = UUID

    /// Active display registration for a tab.
    private struct ActiveDisplay {
        let pageID: WebPage.ID
        let windowID: WindowID
        let timestamp: ContinuousClock.Instant
    }

    // MARK: - Properties

    /// Active display registrations keyed by page ID.
    private var activeDisplays: [WebPage.ID: ActiveDisplay] = [:]

    /// Screen share windows keyed by page ID.
    private var screenShareWindows: [WebPage.ID: NSWindow] = [:]

    /// Shared instance for app-wide coordination.
    static let shared = RefraxWebViewManager()

    // MARK: - Initialization

    private init() {}

    // MARK: - Active Display Management

    /// Requests active display of a page in a window.
    ///
    /// If another window currently has active display, that window
    /// loses it and should switch to portal mode.
    ///
    /// - Parameters:
    ///   - page: The page requesting active display.
    ///   - windowID: The window requesting active display.
    func requestActiveDisplay(for page: WebPage, in windowID: WindowID) {
        let display = ActiveDisplay(
            pageID: page.id,
            windowID: windowID,
            timestamp: .now,
        )

        activeDisplays[page.id] = display
    }

    /// Releases active display of a page from a window.
    ///
    /// - Parameters:
    ///   - page: The page to release.
    ///   - windowID: The window releasing display.
    func releaseActiveDisplay(for page: WebPage, in windowID: WindowID) {
        guard let display = activeDisplays[page.id],
              display.windowID == windowID
        else {
            return
        }

        activeDisplays.removeValue(forKey: page.id)
    }

    /// Checks if a window has active display of a page.
    ///
    /// - Parameters:
    ///   - page: The page to check.
    ///   - windowID: The window to check.
    /// - Returns: `true` if the window has active display.
    func hasActiveDisplay(for page: WebPage, in windowID: WindowID) -> Bool {
        guard let display = activeDisplays[page.id] else {
            // No active display registered - this window can claim it
            return true
        }

        return display.windowID == windowID
    }

    /// Returns the window ID that has active display of a page.
    ///
    /// - Parameter page: The page to query.
    /// - Returns: The window ID with active display, or `nil` if none.
    func activeDisplayWindow(for page: WebPage) -> WindowID? {
        activeDisplays[page.id]?.windowID
    }

    // MARK: - Screen Share Windows

    /// Creates a dedicated window for screen sharing a single tab.
    ///
    /// The window contains a `CAPortalLayer` that mirrors the tab's content,
    /// allowing users to share just this window instead of their entire browser.
    ///
    /// - Parameters:
    ///   - page: The page to share.
    ///   - size: The initial window size.
    /// - Returns: The created window, already visible.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let shareWindow = manager.createScreenShareWindow(for: page)
    /// // In screen sharing app, select this window
    /// ```
    func createScreenShareWindow(
        for page: WebPage,
        size: CGSize = CGSize(width: 1_280, height: 720),
    ) -> NSWindow {
        // Reuse existing window if available
        if let existingWindow = screenShareWindows[page.id], existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            return existingWindow
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false,
        )

        window.title = "Screen Share: \(page.tabPage.title)"
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false

        // Create portal view
        let portalView = ScreenSharePortalView(page: page)
        window.contentView = portalView

        // Track window
        screenShareWindows[page.id] = window

        // Clean up when closed
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main,
        ) { [weak self] _ in
            return MainActor.assumeIsolated {
                self?.screenShareWindows.removeValue(forKey: page.id)
            }
        }

        window.center()
        window.makeKeyAndOrderFront(nil)

        return window
    }

    /// Closes the screen share window for a page if one exists.
    ///
    /// - Parameter page: The page whose share window to close.
    func closeScreenShareWindow(for page: WebPage) {
        screenShareWindows[page.id]?.close()
        screenShareWindows.removeValue(forKey: page.id)
    }

    /// Checks if a screen share window exists for a page.
    ///
    /// - Parameter page: The page to check.
    /// - Returns: `true` if a share window exists and is visible.
    func hasScreenShareWindow(for page: WebPage) -> Bool {
        screenShareWindows[page.id]?.isVisible ?? false
    }
}

// MARK: - Screen Share Portal View

/// NSView that displays a portal layer mirroring a web view's content.
///
/// Used in screen share windows to provide a read-only mirror of tab content
/// that can be shared without exposing the full browser UI.
final class ScreenSharePortalView: NSView {
    // MARK: - Properties

    private let page: WebPage
    private var portalLayer: CALayer?

    // MARK: - Initialization

    init(page: WebPage) {
        self.page = page
        super.init(frame: .zero)
        setupPortalLayer()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Setup

    private func setupPortalLayer() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        guard let portalClass = NSClassFromString("CAPortalLayer") as? CALayer.Type else {
            Logger.error("CAPortalLayer not available for screen share", category: Logger.ui)
            return
        }

        let sourceLayer = page.backingWebView.layer

        let portal = portalClass.init()
        portal.setValue(sourceLayer, forKey: "sourceLayer")
        portal.setValue(true, forKey: "matchesTransform")

        // Get cross-window context ID
        var contextId: UInt32 = 0
        if let sourceView = sourceLayer?.delegate as? NSView,
           let windowLayer = sourceView.window?.contentView?.layer,
           let windowContext: CAContext = windowLayer.context(), windowContext.contextId != 0 {
            contextId = windowContext.contextId
            portal.setValue(contextId, forKey: "sourceContextId")
        } else if let sl = sourceLayer, let ctx: CAContext = sl.context(), ctx.contextId != 0 {
            contextId = ctx.contextId
            portal.setValue(contextId, forKey: "sourceContextId")
        }

        // Also set other portal properties for correct rendering
        portal.setValue(true, forKey: "matchesOpacity")
        portal.setValue(true, forKey: "crossDisplay")
        portal.setValue(true, forKey: "allowsBackdropGroups")

        layer?.addSublayer(portal)
        portalLayer = portal
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        if let portal = portalLayer {
            portal.frame = bounds
        }
    }

    // MARK: - Updates

    /// Updates the portal to track a potentially new web view layer.
    ///
    /// Call this if the page's web view might have been recreated.
    func updatePortalSource() {
        let newLayer = page.backingWebView.layer
        portalLayer?.setValue(newLayer, forKey: "sourceLayer")
    }
}

// MARK: - WebPage Extension

extension WebPage {
    /// Creates a screen share window for this page.
    ///
    /// - Parameter size: The initial window size.
    /// - Returns: The created window.
    func createScreenShareWindow(size: CGSize = CGSize(width: 1_280, height: 720)) -> NSWindow {
        RefraxWebViewManager.shared.createScreenShareWindow(for: self, size: size)
    }

    /// Closes the screen share window for this page.
    func closeScreenShareWindow() {
        RefraxWebViewManager.shared.closeScreenShareWindow(for: self)
    }

    /// Whether a screen share window exists for this page.
    var hasScreenShareWindow: Bool {
        RefraxWebViewManager.shared.hasScreenShareWindow(for: self)
    }
}
