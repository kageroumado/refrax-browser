import AppKit
import ObjectiveC
import QuartzCore
import SwiftUI
import WebKit

// MARK: - Link Preview Manager

/// Manages link previews for WKWebView using native WebKit hit testing.
///
/// This manager provides two ways to show link previews:
///
/// 1. **Force Touch**: Detected via trackpad pressure events (stage 1→2 transition).
///    This replaces WebKit's built-in `allowsLinkPreview` behavior with our custom panel.
///
/// 2. **Shift+Click**: A keyboard-accessible alternative for users without Force Touch
///    trackpads or those using a mouse.
///
/// ## Architecture
///
/// The manager uses native WebKit hit test data from `WKUIDelegateAdapter.lastHitTestResult`,
/// which is continuously updated as the mouse moves over elements. This eliminates the need
/// for JavaScript round-trips and provides accurate element bounding boxes for positioning.
///
/// Link previews use the full WebPage pipeline (content blocking, site settings, etc.)
/// by creating a transient preview page via ``TabManager/createPreviewPage(for:in:)``.
/// The preview can be converted to a real tab, preserving the WKWebView session.
///
/// ## Usage
///
/// The manager is created and stored on ``WebPageWebView/linkPreviewManager`` during
/// WebPage initialization when link preview is enabled in settings.
///
/// ## Thread Safety
///
/// All operations must be performed on the main thread.
final class LinkPreviewManager: NSObject {
    // MARK: - Properties

    /// The web view this manager monitors for link previews.
    private weak var webView: WKWebView?

    /// The event monitor for Shift+Click detection.
    private var clickEventMonitor: Any?

    /// The event monitor for Force Touch (pressure) detection.
    private var pressureEventMonitor: Any?

    /// The last observed pressure stage (0=none, 1=light, 2=force).
    private var lastPressureStage: Int = 0

    /// The preview panel.
    private var previewPanel: LinkPreviewPanel?

    /// Whether Shift+Click link preview is enabled.
    ///
    /// Default is `true`.
    var isShiftClickEnabled: Bool = true

    /// Whether Force Touch link preview is enabled.
    ///
    /// Force Touch triggers a preview when the user applies deep pressure on a link.
    /// This requires a Force Touch-capable trackpad.
    ///
    /// Default is `true`.
    var isForceTouchEnabled: Bool = true

    /// Whether Option+Click opens links in a Glimpse window.
    ///
    /// Default is `true`.
    var isOptionClickEnabled: Bool = true

    /// Delay before showing the preview after Shift+Click.
    ///
    /// A small delay allows the user to cancel if they didn't mean to preview.
    /// Default is `0.0` (no delay).
    var previewDelay: TimeInterval = 0.0

    /// Called when a link preview is about to be shown.
    ///
    /// Return `false` to prevent the preview from showing.
    var shouldShowPreview: ((_ url: URL) -> Bool)?

    /// Called when a link preview is shown.
    var didShowPreview: ((_ url: URL) -> Void)?

    /// Called when a link preview is dismissed.
    var didDismissPreview: (() -> Void)?

    // MARK: - Initialization

    /// Creates a link preview manager for the specified web view.
    ///
    /// - Parameter webView: The web view to monitor for link preview gestures.
    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        startMonitoring()
    }

    deinit {
        MainActor.assumeIsolated {
            stopMonitoring()
        }
    }

    /// Stops monitoring and cleans up resources.
    ///
    /// Called automatically on deinit, but can be called manually to stop
    /// monitoring before the manager is deallocated.
    func invalidate() {
        stopMonitoring()
        webView = nil
    }

    // MARK: - Event Monitoring

    private func startMonitoring() {
        startClickMonitoring()
        startPressureMonitoring()
    }

    private func startClickMonitoring() {
        guard clickEventMonitor == nil else { return }

        clickEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return event }

            // Check if click is in our web view
            guard let webView,
                  let window = webView.window,
                  event.window === window
            else {
                return event
            }

            let locationInWindow = event.locationInWindow
            let locationInWebView = webView.convert(locationInWindow, from: nil)

            guard webView.bounds.contains(locationInWebView) else {
                return event
            }

            // Option+Click opens link in Glimpse window
            if isOptionClickEnabled,
               event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.shift),
               !event.modifierFlags.contains(.control) {
                if handleOptionClick(in: webView) {
                    return nil // Consume event
                }
            }

            // Shift+Click shows link preview (shift only, no other modifiers)
            if isShiftClickEnabled,
               event.modifierFlags.contains(.shift),
               !event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.control) {
                if handleShiftClick(in: webView) {
                    return nil // Consume event
                }
            }

            return event
        }
    }

    private func startPressureMonitoring() {
        guard pressureEventMonitor == nil else { return }

        // Monitor pressure events for Force Touch detection
        // Pressure stages: 0 = none, 1 = light click, 2 = force click (deep press)
        pressureEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.pressure]) { [weak self] event in
            guard let self, isForceTouchEnabled else { return event }

            let currentStage = event.stage

            // Detect transition from stage 1 to stage 2 (force touch activation)
            if lastPressureStage == 1, currentStage == 2 {
                if handleForceTouch(event: event) {
                    // Reset stage to prevent repeated triggers
                    lastPressureStage = currentStage
                    return event
                }
            }

            lastPressureStage = currentStage
            return event
        }
    }

    private func stopMonitoring() {
        if let monitor = clickEventMonitor {
            NSEvent.removeMonitor(monitor)
            clickEventMonitor = nil
        }
        if let monitor = pressureEventMonitor {
            NSEvent.removeMonitor(monitor)
            pressureEventMonitor = nil
        }
        lastPressureStage = 0
        dismissPreview()
    }

    // MARK: - Force Touch Handling

    /// Handles Force Touch (deep press) to show a link preview.
    ///
    /// Force Touch is detected when pressure stage transitions from 1 (light) to 2 (force).
    ///
    /// - Parameter event: The pressure event.
    /// - Returns: `true` if a link preview was triggered.
    private func handleForceTouch(event: NSEvent) -> Bool {
        guard let webView,
              let window = webView.window,
              event.window === window
        else {
            return false
        }

        // Check if force touch is over our web view
        let locationInWindow = event.locationInWindow
        let locationInWebView = webView.convert(locationInWindow, from: nil)

        guard webView.bounds.contains(locationInWebView) else {
            return false
        }

        // Use the same hit test logic as Shift+Click
        return handleLinkPreview(in: webView)
    }

    // MARK: - Shift+Click Handling

    /// Handles Shift+Click to show a link preview.
    ///
    /// - Returns: `true` if a link was found and preview is being shown (event should be consumed),
    ///   `false` if no link at cursor (event should pass through for normal handling).
    @discardableResult
    private func handleShiftClick(in webView: WKWebView) -> Bool {
        handleLinkPreview(in: webView)
    }

    // MARK: - Option+Click Handling

    /// Handles Option+Click to open a link in a Glimpse window.
    ///
    /// - Parameter webView: The web view where the click occurred.
    /// - Returns: `true` if a link was found and Glimpse window opened (event should be consumed),
    ///   `false` if no link at cursor (event should pass through for normal handling).
    @discardableResult
    private func handleOptionClick(in webView: WKWebView) -> Bool {
        // Get the cached native hit test result from the UI delegate adapter
        guard let uiDelegate = webView.uiDelegate as? WKUIDelegateAdapter,
              let hitTestResult = uiDelegate.lastHitTestResult,
              let url = hitTestResult.absoluteLinkURL,
              let pagePool = uiDelegate.pagePool,
              let tabManager = pagePool.tabManager
        else {
            return false
        }

        // Open the link in a Glimpse window
        tabManager.windowManager.createGlimpseWindow(url: url)
        return true
    }

    // MARK: - Link Preview Logic

    /// Shows a link preview for the currently hovered link.
    ///
    /// Used by both Shift+Click and Force Touch handlers. Uses native WebKit hit test
    /// data to get the link URL and bounding box.
    ///
    /// - Parameter webView: The web view to check for hovered links.
    /// - Returns: `true` if a link was found and preview is being shown.
    @discardableResult
    private func handleLinkPreview(in webView: WKWebView) -> Bool {
        // Get the cached native hit test result and context from the UI delegate adapter
        guard let uiDelegate = webView.uiDelegate as? WKUIDelegateAdapter,
              let hitTestResult = uiDelegate.lastHitTestResult,
              let url = hitTestResult.absoluteLinkURL,
              let pagePool = uiDelegate.pagePool,
              let tabManager = pagePool.tabManager,
              let owner = uiDelegate.owner,
              let tab = owner.tabPage.tab
        else {
            return false
        }

        // Check if we should show the preview
        if let shouldShow = shouldShowPreview, !shouldShow(url) {
            return false
        }

        // Get the link's bounding box and convert to screen coordinates
        let linkRect = hitTestResult.elementBoundingBox
        let linkScreenRect = convertToScreenCoordinates(linkRect, in: webView)

        // Show preview after delay if configured
        if previewDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + previewDelay) { [weak self] in
                self?.showPreview(for: url, from: linkScreenRect, in: webView, tab: tab, tabManager: tabManager)
            }
        } else {
            showPreview(for: url, from: linkScreenRect, in: webView, tab: tab, tabManager: tabManager)
        }

        return true
    }

    /// Converts a rect from web content coordinates to screen coordinates.
    private func convertToScreenCoordinates(_ rect: CGRect, in webView: WKWebView) -> NSRect {
        guard let window = webView.window else { return rect }

        // Convert from web view coordinates to window coordinates
        let windowRect = webView.convert(rect, to: nil)

        // Convert from window coordinates to screen coordinates
        return window.convertToScreen(windowRect)
    }

    // MARK: - Preview Display

    /// Shows a link preview panel for the given URL using the full WebPage pipeline.
    ///
    /// - Parameters:
    ///   - url: The URL to preview.
    ///   - originRect: The link's bounding rect in screen coordinates (for animation).
    ///   - webView: The web view that triggered the preview.
    ///   - tab: The parent tab that will own the preview page.
    ///   - tabManager: The tab manager for creating the preview page.
    func showPreview(
        for url: URL,
        from originRect: NSRect,
        in webView: WKWebView,
        tab: Tab,
        tabManager: TabManager,
    ) {
        dismissPreview()

        // Create a preview page through the full pipeline (content blocking, site settings, etc.)
        guard let previewWebPage = tabManager.createPreviewPage(for: url, in: tab) else {
            return
        }

        // Calculate panel size and final position based on content area
        let panelSize = calculatePreviewSize(for: webView)
        let finalFrame = calculatePanelFrame(size: panelSize, relativeTo: webView)

        let panel = LinkPreviewPanel(
            webPage: previewWebPage,
            size: panelSize,
            originRect: originRect,
            finalFrame: finalFrame,
            onClose: { [weak self, weak tab, weak tabManager] in
                if let tab, let tabManager {
                    tabManager.clearPreviewPage(for: tab)
                }
                self?.didDismissPreview?()
                self?.previewPanel = nil
            },
            onOpenInNewTab: { [weak self, weak tab, weak tabManager] in
                guard let tab, let tabManager else { return }
                tabManager.convertPreviewToTab(from: tab, makeActive: true)
                self?.dismissPreview()
            },
            onShare: { [weak previewWebPage] shareButton in
                guard let url = previewWebPage?.url else { return }
                let picker = NSSharingServicePicker(items: [url])
                picker.show(relativeTo: .zero, of: shareButton, preferredEdge: .minY)
            },
        )

        // Position at final location and show with animation
        panel.setFrame(finalFrame, display: false)
        // Make child of source window so it stays on top only of Refrax
        if let sourceWindow = webView.window {
            sourceWindow.addChildWindow(panel, ordered: .above)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.animateAppearance()

        previewPanel = panel
        didShowPreview?(url)
    }

    /// Calculates the preview panel size based on the content area.
    private func calculatePreviewSize(for webView: WKWebView) -> NSSize {
        // Try to get size from splitViewController's content area
        if let windowController = webView.window?.windowController as? RefraxWindowController {
            let splitVC = windowController.splitViewController
            if splitVC.splitViewItems.count > 1 {
                let contentItem = splitVC.splitViewItems[1]
                let contentFrame = contentItem.viewController.view.frame
                return NSSize(
                    width: contentFrame.width * 0.8,
                    height: contentFrame.height * 0.9,
                )
            }
        }

        // Fallback to window-based sizing
        if let window = webView.window {
            return NSSize(
                width: window.frame.width * 0.6,
                height: window.frame.height * 0.7,
            )
        }

        return NSSize(width: 800, height: 600)
    }

    /// Calculates the final panel frame centered over the content area.
    private func calculatePanelFrame(size: NSSize, relativeTo webView: WKWebView) -> NSRect {
        guard let window = webView.window else {
            return NSRect(origin: .zero, size: size)
        }

        // Get the content area frame in screen coordinates
        let contentFrame: NSRect
        if let windowController = window.windowController as? RefraxWindowController {
            let splitVC = windowController.splitViewController
            if splitVC.splitViewItems.count > 1 {
                let contentItem = splitVC.splitViewItems[1]
                let contentView = contentItem.viewController.view
                let viewFrame = contentView.convert(contentView.bounds, to: nil)
                contentFrame = window.convertToScreen(viewFrame)
            } else {
                contentFrame = window.convertToScreen(window.contentLayoutRect)
            }
        } else {
            contentFrame = window.convertToScreen(window.contentLayoutRect)
        }

        // Center the panel in the content area
        let x = contentFrame.midX - size.width / 2
        let y = contentFrame.midY - size.height / 2

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Dismisses the current preview, if any.
    func dismissPreview() {
        previewPanel?.close()
        previewPanel = nil
    }

    /// Shows a preview for a URL programmatically.
    ///
    /// Use this method to show a preview from a menu action or keyboard shortcut.
    ///
    /// - Parameter url: The URL to preview.
    func showPreview(for url: URL) {
        guard let webView,
              let uiDelegate = webView.uiDelegate as? WKUIDelegateAdapter,
              let pagePool = uiDelegate.pagePool,
              let tabManager = pagePool.tabManager,
              let owner = uiDelegate.owner,
              let tab = owner.tabPage.tab
        else {
            return
        }

        // Use center of webView as origin for programmatic preview
        let centerRect = NSRect(
            x: webView.bounds.midX - 50,
            y: webView.bounds.midY - 20,
            width: 100,
            height: 40,
        )
        let screenRect = convertToScreenCoordinates(centerRect, in: webView)

        showPreview(for: url, from: screenRect, in: webView, tab: tab, tabManager: tabManager)
    }
}
