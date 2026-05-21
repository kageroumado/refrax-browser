import AppKit
import Foundation
import QuartzCore
import SwiftUI
import WebKit

// MARK: - CocoaWebViewAdapter

/// NSView adapter for displaying web content in active or portal mode.
///
/// `CocoaWebViewAdapter` is the macOS view that hosts a `WebPageWebView`. It provides:
///
/// - **Active mode**: Embeds the WKWebView directly (interactive)
/// - **Portal mode**: Displays a read-only mirror via `CAPortalLayer` (multi-window)
/// - **Find-in-page**: Manages find bar visibility and constraints
///
/// ## Design Notes
///
/// This adapter mirrors WebKit's `CocoaWebViewAdapter` to maintain API compatibility.
/// Key responsibilities:
/// - Managing WebPageWebView lifecycle and constraints
/// - Find bar container support via NSTextFinderBarContainer
/// - Portal layer management for multi-window display
///
/// ## Multi-Window Portal Mode
///
/// Portal mode enables a single WKWebView to appear in multiple windows simultaneously.
/// Only one window hosts the actual WKWebView (active mode), while other windows display
/// a live mirror using `CAPortalLayer` (portal mode).
///
/// ### How CAPortalLayer Works
///
/// `CAPortalLayer` is a private Core Animation layer class that mirrors the contents
/// of another layer in real-time. Unlike snapshots, portal layers show live content
/// including animations, video, and scroll position changes.
///
/// ### Cross-Window Portal Requirements
///
/// For `CAPortalLayer` to work across different windows, two properties must be set:
///
/// 1. **`sourceLayer`**: The layer to mirror (the WKWebView's backing layer)
/// 2. **`sourceContextId`**: The CAContext ID of the window containing the source layer
///
/// Simply setting `sourceLayer` alone only works within the same window/rendering context.
/// For cross-window portaling, `sourceContextId` is **required**. This is obtained from
/// the source layer's `CAContext` via the private `-context` method.
///
/// ### Coordinate System Handling
///
/// WKWebView uses a flipped coordinate system internally via `WKFlippedView`. The portal
/// layer configuration must account for this:
///
/// - Portal the `webView.layer` directly (not sublayers) to preserve coordinate handling
/// - Set `matchesTransform = true` to inherit the source layer's transform chain
/// - The source layer's `isGeometryFlipped = true` naturally handles the flip
///
/// ### WKWebView Layer Hierarchy
///
/// Understanding WebKit's layer structure is critical for correct portaling:
///
/// ```
/// webView.layer (NSViewBackingLayer, isGeometryFlipped=true)
///   └── WKFlippedView.layer (CALayer, isGeometryFlipped=false)
///         └── m_rootLayer (WKCompositingLayer, contains actual web content)
///               └── ... content layers (WKCompositingLayer)
/// ```
///
/// We portal `webView.layer` because:
/// - It has `isGeometryFlipped = true` which correctly handles coordinate conversion
/// - Its sublayers would require manual flip correction
/// - The entire layer tree is captured including scroll position
///
/// ## Performance Optimizations
///
/// ### Portal Layer Transitions
///
/// Portal mode transitions use `CATransaction.setDisableActions(true)` to prevent
/// implicit animations during tab switching. This is critical for smooth rapid
/// tab switching where users expect immediate visual feedback.
///
/// ### Live Resize
///
/// Note: We intentionally do NOT use snapshot-based resize optimization on macOS.
/// WKWebView has its own internal live resize handling, and adding bitmap snapshots
/// via `bitmapImageRepForCachingDisplay` actually decreases performance because:
/// 1. CPU-based bitmap capture blocks the main thread
/// 2. Memory allocation for the bitmap adds pressure
/// 3. View hierarchy manipulation (insert/remove) adds overhead
///
/// The iOS pattern (`_beginAnimatedResizeWithUpdates:`) is designed for discrete
/// animated transitions (rotation), not continuous drag operations like macOS
/// split view resizing.
///
/// ## Private APIs Used
///
/// Portal mode requires the following private APIs:
/// - `CAPortalLayer`: Private CALayer subclass for layer mirroring
/// - `CAContext`: Private class representing a rendering context
/// - `CALayer.context()`: Private method to get a layer's CAContext
/// - `CAContext.contextId`: Property returning the unique context identifier
///
/// These are declared in `CAContextPrivate.h` and `QuartzCoreSPI.h`.
///
/// ## Reference
///
/// Mirrors WebKit's `CocoaWebViewAdapter` from:
/// `WebKit/Source/WebKit/_WebKit_SwiftUI/Implementation/CocoaWebViewAdapter.swift`
final class CocoaWebViewAdapter: NSView, WebPageWebView.Delegate {
    // MARK: - Display Mode

    /// The current display mode of the adapter.
    enum DisplayMode: Equatable {
        /// No content displayed.
        case inactive

        /// Active WKWebView embedded (interactive).
        case active(webView: WebPageWebView)

        /// Portal layer mirroring another view's layer (read-only).
        case portal(sourceLayer: CALayer)

        /// GPU-captured snapshot replacing live content (layout mode).
        ///
        /// Stores the web page ID so we know which page to reclaim on exit.
        case snapshot(webPageID: WebPage.ID)

        static func == (lhs: DisplayMode, rhs: DisplayMode) -> Bool {
            switch (lhs, rhs) {
            case (.inactive, .inactive):
                true
            case let (.active(lhsWebView), .active(rhsWebView)):
                lhsWebView === rhsWebView
            case let (.portal(lhsLayer), .portal(rhsLayer)):
                lhsLayer === rhsLayer
            case let (.snapshot(lhsID), .snapshot(rhsID)):
                lhsID == rhsID
            default:
                false
            }
        }
    }

    /// The current display mode.
    private(set) var displayMode: DisplayMode = .inactive

    // MARK: - Web View

    /// The currently active web view, if in active mode.
    var webView: WebPageWebView? {
        if case let .active(webView) = displayMode {
            return webView
        }
        return nil
    }

    // MARK: - Find-in-Page Support

    /// Find context for controlling find navigator presentation.
    var findContext: FindContext?

    /// Whether the find navigator is currently visible.
    var isFindNavigatorVisible: Bool {
        isFindBarVisible
    }

    /// Find bar visibility state (required by NSTextFinderBarContainer).
    var isFindBarVisible: Bool = false {
        didSet {
            guard oldValue != isFindBarVisible else {
                return
            }

            // Update the binding if available
            if let isPresented = findContext?.isPresented {
                isPresented.wrappedValue = isFindBarVisible
            }

            if isFindBarVisible {
                findBarDidBecomeVisible()
            } else {
                findBarDidBecomeHidden()
            }
        }
    }

    /// The find bar view managed by NSTextFinder (required by NSTextFinderBarContainer).
    var findBarView: NSView?

    /// Lazy-created text finder for find-in-page.
    ///
    /// The `client` property is set lazily when find is first invoked, not during
    /// adapter initialization. This avoids NSTextFinder creation overhead during
    /// tab switching when find is never used.
    private var _findInteraction: NSTextFinder?

    var findInteraction: NSTextFinder? {
        if _findInteraction == nil {
            let finder = NSTextFinder()
            finder.isIncrementalSearchingEnabled = true
            finder.incrementalSearchingShouldDimContentView = false
            finder.findBarContainer = self
            // Set client to current webView (may be nil if called before setActiveMode)
            if case let .active(webView) = displayMode {
                finder.client = webView
            }
            _findInteraction = finder
        }
        return _findInteraction
    }

    // MARK: - Scroll Position

    /// Scroll position context for programmatic scroll control.
    var scrollPositionContext: ScrollPositionContext?

    // MARK: - Interaction Callback

    /// Callback invoked when the user clicks on the web view.
    /// Used to track focus for address bar updates.
    var onMouseDown: (() -> Void)?

    // MARK: - Content Inset

    /// Top content inset for toolbar overlay areas.
    ///
    /// When set, the web content is pushed down by this amount using WebKit's
    /// `_topContentInset` API, creating space for toolbars while allowing
    /// content to scroll behind them.
    var topContentInset: CGFloat = 0 {
        didSet {
            guard topContentInset != oldValue else { return }
            applyTopContentInset()
        }
    }

    /// Whether to use automatic content inset background fill (scroll pocket system).
    ///
    /// When enabled, WebKit uses the NSScrollPocket system which:
    /// - Enables sticky header detection via `_prefersSolidColorHardScrollPocket`
    /// - Automatically samples and adapts colors from page content
    var usesAutomaticContentInsetBackgroundFill: Bool = false {
        didSet {
            guard usesAutomaticContentInsetBackgroundFill != oldValue else { return }
            applyAutomaticContentInsetBackgroundFill()
        }
    }

    // MARK: - Layout Override

    /// Returns empty constraints to prevent WKFullScreenWindowController and Web Inspector
    /// from capturing and reactivating constraints after this view is gone.
    ///
    /// WebKit's inspector docking system and fullscreen controller use frame-based layout
    /// internally, directly manipulating the inspected view's frame. If we expose Auto Layout
    /// constraints, they conflict with WebKit's frame changes, breaking docked inspector layout.
    override var constraints: [NSLayoutConstraint] {
        []
    }

    // MARK: - Portal Layer

    /// The portal layer used for read-only display in multi-window scenarios.
    private var portalLayer: CAPortalLayer?

    /// GPU-captured snapshot layer that sits behind the portal as a transition fallback.
    ///
    /// When a secondary window closes, its `prepareForDismantle` removes the webView from
    /// the hierarchy, orphaning the main window's `CAPortalLayer` source. The portal renders
    /// nothing for 1-2 frames until `setActiveMode` is called. This snapshot layer, captured
    /// via `CGSHWCaptureWindowList` before the mode switch, bridges that gap.
    private var transitionSnapshotLayer: CALayer?

    /// The source layer for a pending portal creation.
    /// Used to prevent duplicate deferred portal creation when SwiftUI triggers multiple updates.
    private var pendingPortalSourceLayer: CALayer?

    /// Whether the webView is currently being moved between windows.
    ///
    /// When true, `applyTopContentInset()` is deferred to the `_prepareForMoveToWindow`
    /// completion handler. Applying insets during the transition causes WebKit to
    /// miscalculate scroll position compensation, jumping content to near-bottom.
    private var isPendingWindowMove = false

    /// Whether we've already attempted a portal recovery for the current portal.
    /// This prevents infinite recreation loops if the portal consistently fails to render.
    private var hasAttemptedPortalRecovery = false

    /// Whether the webView frame should be held constant during a snapshot exit transition.
    ///
    /// During the exit animation, the adapter bounds animate from tile-size to full-size.
    /// Without this flag, `layout()` and `autoresizingMask` would resize the webView on every
    /// frame, triggering WebKit re-layout at intermediate sizes. The iOS pattern holds the
    /// webView at the final target size while the snapshot covers the transition.
    private var isHoldingWebViewFrame = false

    /// Cancellable work item for the pending snapshot exit cleanup.
    /// Invalidated if layout mode is re-entered before the exit animation completes.
    private var snapshotExitWork: DispatchWorkItem?

    /// Local event monitor for tracking mouse down events.
    private var mouseDownMonitor: Any?

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupMouseDownMonitor()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        if let monitor = mouseDownMonitor {
            NSEvent.removeMonitor(monitor)
            mouseDownMonitor = nil
        }
    }

    // MARK: - Event Monitoring

    /// Sets up a local event monitor to track mouse down events within this view.
    ///
    /// WKWebView intercepts mouse events before they reach the parent view's
    /// `mouseDown(with:)` method. To track clicks for focus management, we use
    /// a local event monitor that sees all events before they're dispatched.
    private func setupMouseDownMonitor() {
        mouseDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.handleMouseDownEvent(event)
            return event // Always pass the event through
        }
    }

    /// Handles mouse down events from the local monitor.
    ///
    /// Checks if the event occurred within this view's bounds and calls
    /// the `onMouseDown` callback if so.
    private func handleMouseDownEvent(_ event: NSEvent) {
        guard let window,
              event.window === window else {
            return
        }

        // Convert event location to this view's coordinate system
        let locationInWindow = event.locationInWindow
        let locationInView = convert(locationInWindow, from: nil)

        // Check if the click is within our bounds
        if bounds.contains(locationInView) {
            onMouseDown?()
        }
    }

    // MARK: - Display Mode Management

    /// Sets the adapter to active mode with the given web view.
    ///
    /// In active mode, the web view is embedded as a subview and receives
    /// user interaction events. The webView is always added immediately -
    /// if bounds are zero, the webView will be laid out correctly when
    /// bounds become valid in `layout()`.
    ///
    /// - Parameters:
    ///   - webView: The web view to display.
    ///   - expectedFrame: Optional hint for the expected frame size. If provided and the
    ///     adapter has zero bounds, the webView is set to this frame before adding.
    ///     This prevents visual glitches when the webView already has content.
    /// Enters active mode, embedding the webView directly.
    ///
    /// - Parameters:
    ///   - webView: The webView to embed.
    ///   - expectedFrame: Hint for the expected frame size.
    ///   - preferExpectedFrame: When true, use expectedFrame even if adapter has valid bounds.
    ///     Use this during page/tab switches when adapter bounds are stale from previous content.
    func setActiveMode(webView: WebPageWebView, expectedFrame: CGRect? = nil, preferExpectedFrame: Bool = false) {
        // Fast path: already active with this webView as our subview — nothing to do
        if case let .active(currentWebView) = displayMode,
           currentWebView === webView,
           webView.superview === self {
            return
        }

        pendingPortalSourceLayer = nil

        // Check if this is a cross-window move BEFORE cleaning up.
        let isMovingWindows = webView.window != nil && webView.window !== window

        cleanupCurrentMode()

        if isMovingWindows, let targetWindow = window {
            // For cross-window moves, defer everything to _prepareForMove completion.
            // Moving the webView before WebKit finishes preparing causes scroll/texture
            // corruption because the compositing context hasn't been updated yet.
            isPendingWindowMove = true
            displayMode = .inactive

            webView._prepareForMove(to: targetWindow) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isPendingWindowMove = false

                    self.addWebViewAfterPreparation(webView, expectedFrame: expectedFrame, preferExpectedFrame: preferExpectedFrame)
                    self.finishActiveMode(webView: webView)
                    self.removeTransitionSnapshot()
                }
            }
        } else {
            addWebViewAfterPreparation(webView, expectedFrame: expectedFrame, preferExpectedFrame: preferExpectedFrame)
            finishActiveMode(webView: webView)
            removeTransitionSnapshot()
        }
    }

    /// Adds the webView to the view hierarchy with proper frame and configuration.
    ///
    /// - Parameters:
    ///   - webView: The webView to add.
    ///   - expectedFrame: Hint for the expected frame size.
    ///   - preferExpectedFrame: When true, use expectedFrame even if adapter has valid bounds.
    /// Adds the webView to the view hierarchy with proper frame configuration.
    ///
    /// For cross-window moves, the caller (`setActiveMode`) handles `_prepareForMove`
    /// and calls this method from the completion handler. This method only handles
    /// frame setup and `addSubview`.
    private func addWebViewAfterPreparation(_ webView: WebPageWebView, expectedFrame: CGRect?, preferExpectedFrame: Bool = false) {
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]

        // Determine the frame to use:
        // 1. If preferExpectedFrame is true and expectedFrame is valid, use that
        //    (for tab switches where adapter bounds are stale from previous content)
        // 2. Else if adapter has valid bounds, use those (for resize scenarios)
        // 3. Else if expectedFrame provided, use that
        // 4. Otherwise keep webView's current frame (will be corrected in layout())
        let targetFrame: CGRect
        if preferExpectedFrame, let expected = expectedFrame, expected.width > 0, expected.height > 0 {
            targetFrame = CGRect(origin: .zero, size: expected.size)
            // Also update adapter bounds to match, preventing jerk from bounds mismatch.
            // This is safe because SwiftUI will update bounds on the next layout pass anyway.
            if bounds.size != expected.size {
                frame = CGRect(origin: frame.origin, size: expected.size)
            }
        } else if bounds.width > 0, bounds.height > 0 {
            targetFrame = bounds
        } else if let expected = expectedFrame, expected.width > 0, expected.height > 0 {
            targetFrame = CGRect(origin: .zero, size: expected.size)
        } else {
            targetFrame = webView.frame
        }

        if webView.frame != targetFrame {
            webView.frame = targetFrame
        }

        addSubview(webView)
    }

    /// Finishes active mode setup after webView is in hierarchy.
    private func finishActiveMode(webView: WebPageWebView) {
        // Ensure the webView is visible (it may have been hidden if it was in another adapter)
        webView.isHidden = false

        // Always ensure delegate is set (it may have been cleared)
        webView.delegate = self

        // Update find interaction client if it was already created.
        // Also cancel any ongoing search since we're displaying a different page now.
        if let finder = _findInteraction {
            // Check if we're switching to a different webView
            let clientChanged = finder.client !== webView
            finder.client = webView

            // If the client changed and find bar is visible, cancel the search.
            // The new page's find state will be applied via the environment.
            if clientChanged, isFindBarVisible {
                finder.cancelFindIndicator()
                webView._hideFindUI()
            }
        }

        displayMode = .active(webView: webView)

        // Apply content inset settings now that we're in active mode.
        // These may have been set while inactive (didSet skips apply when not active),
        // so we must apply them now. The order matters:
        // 1. topContentInset sets the obscured insets
        // 2. automaticContentInsetBackgroundFill triggers scroll pocket creation
        applyTopContentInset()
        applyAutomaticContentInsetBackgroundFill()
    }

    /// Sets the adapter to portal mode mirroring the given layer.
    ///
    /// In portal mode, a `CAPortalLayer` displays a read-only copy of another
    /// view's layer. This is used for multi-window scenarios where only one
    /// window should be interactive.
    ///
    /// ## Performance
    ///
    /// Portal layer creation and configuration is wrapped in a CATransaction
    /// with disabled actions to prevent implicit animations during tab switching.
    /// This is critical for smooth rapid tab switching where the user expects
    /// immediate visual feedback.
    ///
    /// ## Multi-Window Behavior
    ///
    /// Portal creation is ALWAYS deferred to the next run loop iteration.
    /// This is critical because:
    /// 1. The source layer's CAContext may not be updated yet after a window switch
    /// 2. The active window's adapter needs time to claim the webView
    /// 3. Layer hierarchy changes need to propagate before we can get valid context IDs
    ///
    /// - Parameter sourceLayer: The layer to mirror.
    func setPortalMode(sourceLayer: CALayer) {
        guard displayMode != .portal(sourceLayer: sourceLayer) else {
            return
        }

        // Prevent duplicate deferred portal creation when SwiftUI triggers multiple updates.
        if pendingPortalSourceLayer === sourceLayer {
            return
        }

        // Capture a GPU snapshot BEFORE cleaning up, while the webView is still in the hierarchy.
        // This snapshot sits behind the portal and becomes visible if the portal source is orphaned
        // (e.g., when the secondary window closes), preventing a 1-2 frame blank flash.
        if case .active = displayMode {
            captureTransitionSnapshot()
        }

        // Always clean up current mode first.
        cleanupCurrentMode()

        displayMode = .inactive
        pendingPortalSourceLayer = sourceLayer

        // Defer portal creation to the next run loop iteration.
        //
        // This gives the active window's adapter time to claim the webView and
        // allows layer hierarchy changes to propagate. The readiness checks in
        // createPortalIfReady handle all timing — if the source isn't ready yet
        // (no superlayer, still our descendant, context mismatch), it retries
        // automatically on the next run loop iteration.
        DispatchQueue.main.async { [weak self] in
            self?.createPortalIfReady(sourceLayer: sourceLayer)
        }
    }

    /// Creates a portal layer if the source is ready (no longer our subview, has a superlayer, and has a valid context).
    ///
    /// ## Race Condition Prevention
    ///
    /// When switching windows, there's a critical race condition:
    /// 1. Active window takes the WebView (adds it to its view hierarchy)
    /// 2. Inactive window's adapter calls setPortalMode → defers to createPortalIfReady
    /// 3. WebView's layer may have a superlayer but still have a STALE contextId
    /// 4. Portal created with old contextId → shows blank
    ///
    /// To prevent this, we verify the source layer's context is valid AND matches
    /// the context of its current window before creating the portal. If the context
    /// appears stale (doesn't match the window's context), we defer and retry.
    private func createPortalIfReady(sourceLayer: CALayer) {
        // If we've since switched to a different mode, don't create portal
        guard case .inactive = displayMode else {
            return
        }

        // Check again if source is still our descendant
        if let sourceView = sourceLayer.delegate as? NSView, sourceView.isDescendant(of: self) {
            DispatchQueue.main.async { [weak self] in
                self?.createPortalIfReady(sourceLayer: sourceLayer)
            }
            return
        }

        // Check if source layer has a valid superlayer
        guard sourceLayer.superlayer != nil else {
            DispatchQueue.main.async { [weak self] in
                self?.createPortalIfReady(sourceLayer: sourceLayer)
            }
            return
        }

        // Check if the source layer has a valid context that matches its current window.
        // This prevents the race condition where the layer has moved to a new window
        // but the CAContext hasn't been updated yet.
        if let sourceView = sourceLayer.delegate as? NSView,
           let sourceWindow = sourceView.window,
           let windowContentLayer = sourceWindow.contentView?.layer {
            let windowContext: CAContext? = windowContentLayer.context()
            let sourceContext: CAContext? = sourceLayer.context()

            let sourceCtxId = sourceContext?.contextId ?? 0

            // If the window has a context but the source layer doesn't, or they don't match,
            // the layer is still transitioning - defer and retry
            if let windowCtx = windowContext, windowCtx.contextId != 0 {
                if sourceContext == nil || sourceCtxId == 0 || sourceCtxId != windowCtx.contextId {
                    DispatchQueue.main.async { [weak self] in
                        self?.createPortalIfReady(sourceLayer: sourceLayer)
                    }
                    return
                }
            }
        }

        createPortal(sourceLayer: sourceLayer)
    }

    /// Creates and configures the portal layer for cross-window mirroring.
    ///
    /// ## How It Works
    ///
    /// This method creates a `CAPortalLayer` that mirrors the source WKWebView's layer
    /// in real-time. The portal shows live content including:
    /// - Scroll position changes
    /// - Animations and transitions
    /// - Video playback
    /// - Dynamic content updates
    ///
    /// ## Cross-Window Requirements
    ///
    /// For CAPortalLayer to work across different windows, we must set both:
    /// 1. `sourceLayer` - The layer to mirror
    /// 2. `sourceContextId` - The CAContext ID of the source window
    ///
    /// Without `sourceContextId`, the portal only works within the same window.
    /// The context ID is obtained via the private `CALayer.context()` method.
    ///
    /// ## Coordinate System
    ///
    /// WKWebView uses a flipped coordinate system (origin at top-left) internally.
    /// The key insight is:
    /// - `webView.layer` (NSViewBackingLayer) has `isGeometryFlipped = true`
    /// - Its first sublayer (WKFlippedView.layer) has `isGeometryFlipped = false`
    ///
    /// By portaling `webView.layer` directly and setting `matchesTransform = true`,
    /// the portal correctly inherits the coordinate transformation chain, ensuring
    /// scroll direction and content positioning match the source.
    ///
    /// ## Portal Layer Configuration
    ///
    /// - `hidesSourceLayer = false`: Keep source visible in the active window
    /// - `matchesOpacity = true`: Match source layer opacity
    /// - `matchesPosition = false`: Position the portal independently
    /// - `matchesTransform = true`: Inherit transform chain (critical for flipped coordinates)
    /// - `allowsBackdropGroups = true`: Support backdrop filters/blur effects
    /// - `crossDisplay = true`: Allow portaling across different displays
    ///
    /// - Parameter sourceLayer: The WKWebView's backing layer to mirror.
    private func createPortal(sourceLayer: CALayer) {
        // Ensure the source layer is attached to a valid hierarchy.
        // Orphaned layers (no superlayer) cannot be portaled.
        guard sourceLayer.superlayer != nil else {
            displayMode = .inactive
            DispatchQueue.main.async { [weak self] in
                self?.createPortalIfReady(sourceLayer: sourceLayer)
            }
            return
        }

        // Batch all CALayer operations to prevent implicit animations.
        // This is critical for smooth, instant tab switching.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        // Create and configure the portal layer.
        //
        // We portal webView.layer directly because:
        // 1. It has isGeometryFlipped=true which correctly handles coordinate conversion
        // 2. Portaling sublayers would require manual flip correction
        // 3. The entire layer tree is captured including scroll state
        let portal = CAPortalLayer()
        portal.sourceLayer = sourceLayer
        portal.hidesSourceLayer = false // Keep source visible in active window
        portal.matchesOpacity = true // Match source opacity
        portal.matchesPosition = false // We position the portal ourselves
        portal.matchesTransform = true // CRITICAL: Inherit transform chain for correct flip handling
        portal.allowsBackdropGroups = true // Support backdrop blur effects
        portal.crossDisplay = true // Allow cross-display portaling
        portal.frame = bounds
        portal.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        // Set the source context ID for cross-window portaling.
        //
        // CAPortalLayer.sourceLayer alone only works within the same window/CAContext.
        // For cross-window support, we must also set sourceContextId.
        //
        // IMPORTANT: We prefer getting the context from the SOURCE WINDOW's content layer
        // rather than the source layer directly. This is more reliable because:
        // 1. The window's context is the canonical source of truth
        // 2. The source layer's context may be stale during window transitions
        // 3. All layers in a window share the same context
        //
        // The context ID is obtained via the private -context method declared in CAContextPrivate.h.
        var contextId: UInt32 = 0

        // Primary method: Get context from the source window's content layer
        if let sourceView = sourceLayer.delegate as? NSView,
           let windowLayer = sourceView.window?.contentView?.layer,
           let windowContext: CAContext = windowLayer.context(), windowContext.contextId != 0 {
            contextId = windowContext.contextId
        }

        // Fallback: Try the source layer directly
        if contextId == 0, let sourceContext: CAContext = sourceLayer.context(), sourceContext.contextId != 0 {
            contextId = sourceContext.contextId
        }

        // Last resort: Walk up the layer tree to find a context
        if contextId == 0 {
            var currentLayer: CALayer? = sourceLayer.superlayer
            while let layer = currentLayer {
                if let ctx: CAContext = layer.context(), ctx.contextId != 0 {
                    contextId = ctx.contextId
                    break
                }
                currentLayer = layer.superlayer
            }
        }

        if contextId != 0 {
            portal.sourceContextId = contextId
        }
        // If no context found, portal will still work within the same window

        // Insert portal above snapshot layer (if present) so it covers the static fallback.
        // When the portal source is valid, it renders live content on top of the snapshot.
        // If the source is orphaned, the portal becomes transparent and the snapshot shows through.
        if let snapshot = transitionSnapshotLayer {
            layer?.insertSublayer(portal, above: snapshot)
        } else {
            layer?.addSublayer(portal)
        }
        portalLayer = portal

        CATransaction.commit()

        // Force the portal layer to update by re-setting sourceLayer after the transaction.
        // This is a workaround for a CAPortalLayer quirk where the layer may not render
        // correctly when first added, especially after mouse-click window activation.
        // Re-setting sourceLayer triggers an internal update that forces rendering.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let savedSourceLayer = portal.sourceLayer
        let savedContextId = portal.sourceContextId
        portal.sourceLayer = nil
        portal.sourceLayer = savedSourceLayer
        portal.sourceContextId = savedContextId
        CATransaction.commit()

        pendingPortalSourceLayer = nil
        hasAttemptedPortalRecovery = false
        displayMode = .portal(sourceLayer: sourceLayer)

        // Force the portal to refresh after the source webView completes its first
        // presentation update in the new window. On the first cross-window move,
        // the compositing context may not be fully established when the portal is
        // created, causing it to render as transparent. Re-setting sourceLayer after
        // the first render forces the WindowServer to re-evaluate the connection.
        if let sourceWebView = (sourceLayer.delegate as? NSView) as? WebPageWebView {
            Task(name: "Refresh portal after presentation update") { [weak self] in
                await sourceWebView.waitForPresentationUpdate()

                guard let self,
                      case .portal = self.displayMode,
                      let portal = self.portalLayer else { return }

                CATransaction.begin()
                CATransaction.setDisableActions(true)

                // Refresh the context ID in case it changed after the first render.
                if let windowLayer = sourceWebView.window?.contentView?.layer,
                   let ctx: CAContext = windowLayer.context(), ctx.contextId != 0 {
                    portal.sourceContextId = ctx.contextId
                }

                let sl = portal.sourceLayer
                portal.sourceLayer = nil
                portal.sourceLayer = sl
                CATransaction.commit()
            }
        }

        // Schedule a validation check after a short delay.
        // This catches edge cases where the portal was created during mouse-click
        // window activation but didn't render correctly due to WindowServer timing.
        // If the portal still isn't rendering (shows white/blank), we recreate it once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.validatePortalRendering(sourceLayer: sourceLayer)
        }
    }

    /// Validates that the portal is rendering correctly and recreates it if not.
    ///
    /// This method is called shortly after portal creation to catch cases where
    /// the portal was created but isn't rendering correctly. This can happen due to:
    /// - Mouse-click window activation timing issues with the WindowServer
    /// - Stale context IDs from a previous window
    /// - CAPortalLayer failing to establish the cross-window connection
    ///
    /// The validation checks:
    /// 1. Context ID mismatch between portal and source window
    /// 2. Portal layer rendering as pure white/blank (indicates failed mirroring)
    ///
    /// Recovery is attempted only once to prevent infinite recreation loops.
    private func validatePortalRendering(sourceLayer: CALayer) {
        // Only validate if we're still in portal mode for this source
        guard case let .portal(currentSourceLayer) = displayMode,
              currentSourceLayer === sourceLayer,
              let portal = portalLayer else {
            return
        }

        // Don't attempt recovery more than once per portal
        guard !hasAttemptedPortalRecovery else {
            return
        }

        // Get the current context ID from the source window
        guard let sourceView = sourceLayer.delegate as? NSView,
              let windowLayer = sourceView.window?.contentView?.layer,
              let windowContext: CAContext = windowLayer.context(),
              windowContext.contextId != 0 else {
            return
        }

        let currentContextId = windowContext.contextId
        var needsRecreation = false

        // Check 1: Context ID mismatch
        if portal.sourceContextId != currentContextId {
            needsRecreation = true
        }

        // Check 2: Portal is rendering as white/blank
        // This happens when CAPortalLayer fails to establish the cross-window connection
        if !needsRecreation,
           let contents = portal.contents,
           CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
            // swiftlint:disable:next force_cast
            let cgImage = contents as! CGImage
            // If the portal has contents but they're a solid white image, it's broken
            if isImagePureWhite(cgImage) {
                needsRecreation = true
            }
        }

        if needsRecreation {
            hasAttemptedPortalRecovery = true

            // Remove the broken portal
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            portal.removeFromSuperlayer()
            portalLayer = nil
            CATransaction.commit()

            // Recreate with correct context
            displayMode = .inactive
            createPortal(sourceLayer: sourceLayer)
        }
    }

    /// Checks if a CGImage is pure white (or nearly pure white).
    ///
    /// This is used to detect broken portal layers that render as blank white.
    /// A broken CAPortalLayer will often show a solid white image instead of
    /// the mirrored content.
    private func isImagePureWhite(_ image: CGImage) -> Bool {
        // Sample a few pixels from the image to check if it's pure white
        // We check the corners and center to avoid false positives
        guard image.width > 0, image.height > 0 else {
            return false
        }

        // Create a small bitmap context to sample pixels
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else {
            return false
        }

        // Sample center pixel
        let centerX = CGFloat(image.width) / 2
        let centerY = CGFloat(image.height) / 2
        context.draw(image, in: CGRect(x: -centerX, y: -centerY, width: CGFloat(image.width), height: CGFloat(image.height)))

        // Check if pixel is white (R, G, B all > 250)
        let r = pixelData[0]
        let g = pixelData[1]
        let b = pixelData[2]

        return r > 250 && g > 250 && b > 250
    }

    /// Sets the adapter to inactive mode with no content.
    func setInactiveMode() {
        guard displayMode != .inactive else {
            return
        }

        pendingPortalSourceLayer = nil
        removeTransitionSnapshot()

        cleanupCurrentMode()
        displayMode = .inactive
    }

    // MARK: - Snapshot Mode (Layout Mode)

    /// Enters snapshot mode by capturing the current content as a GPU snapshot and removing the WKWebView.
    ///
    /// Called when entering layout mode. The snapshot is a static image that animates smoothly
    /// without triggering any WebKit layout work. The webView is removed from the hierarchy
    /// to prevent WebKit from re-laying out content at the tile size.
    ///
    /// - Parameter page: The web page whose content to snapshot.
    func setSnapshotMode(for page: WebPage) {
        guard case .active = displayMode else { return }

        // Cancel any in-flight exit animation from a previous snapshot mode.
        // This handles rapid exit → re-enter: the pending timer would otherwise
        // remove our new snapshot and mess with frame management state.
        cancelSnapshotExitWork()

        // Capture BEFORE removing the webView
        captureTransitionSnapshot()

        // Remove the webView so WebKit doesn't re-layout at the tile size
        let webView = page.backingWebView
        webView.delegate = nil
        webView.removeFromSuperview()

        displayMode = .snapshot(webPageID: page.id)
    }

    /// Cancels any pending snapshot exit work and resets related state.
    ///
    /// Called from `setSnapshotMode` during rapid exit→re-enter to prevent the
    /// pending exit timer from removing the new snapshot. Uses force removal
    /// since the normal `removeTransitionSnapshot()` guards against removal
    /// during `.snapshot` display mode.
    private func cancelSnapshotExitWork() {
        snapshotExitWork?.cancel()
        snapshotExitWork = nil
        isHoldingWebViewFrame = false
        // Force-remove the old snapshot — the normal removeTransitionSnapshot()
        // would refuse since displayMode might still be .snapshot. But we're about
        // to capture a new snapshot, so the old one must go.
        forceRemoveTransitionSnapshot()
    }

    /// Unconditionally removes the transition snapshot, bypassing the display mode guard.
    private func forceRemoveTransitionSnapshot() {
        guard transitionSnapshotLayer != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        transitionSnapshotLayer?.removeFromSuperlayer()
        transitionSnapshotLayer = nil
        CATransaction.commit()
    }

    /// Exits snapshot mode, mirroring the iOS `_endLiveResize` pattern.
    ///
    /// The webView is added at the **final target size** and held there for the entire exit
    /// animation. `layout()` is prevented from resizing it via `isHoldingWebViewFrame`, and
    /// `autoresizingMask` is cleared so AppKit doesn't resize it either. This means WebKit
    /// never re-layouts at intermediate sizes — no content reflow, no scroll position jumps.
    ///
    /// The snapshot layer is moved above the webView so it covers the transition. After the
    /// animation completes, we wait for `_doAfterNextPresentationUpdate:` (same as iOS's
    /// `_endLiveResize`) to confirm WebKit has painted at the final size, then remove the
    /// snapshot.
    ///
    /// - Parameters:
    ///   - webView: The webView to re-add.
    ///   - expectedFrame: The **final** frame the adapter will have after the animation.
    ///   - animationDuration: How long the exit animation runs. The snapshot is held for
    ///     this duration before removal.
    func exitSnapshotMode(webView: WebPageWebView, expectedFrame: CGRect, animationDuration: TimeInterval = 0.5) {
        guard case .snapshot = displayMode else { return }

        // Prevent layout() from resizing the webView during the animation.
        isHoldingWebViewFrame = true

        // Add webView to the hierarchy (sets it to current bounds,
        // which is tile-size — we'll override this below).
        addWebViewAfterPreparation(webView, expectedFrame: expectedFrame)
        finishActiveMode(webView: webView)

        // Override: set webView to the FINAL target size so WebKit renders at full size
        // from the start, avoiding re-layout at every intermediate animation frame.
        // Clear autoresizingMask so AppKit doesn't resize it during the animation either.
        let targetSize = expectedFrame.size
        if targetSize.width > 0, targetSize.height > 0 {
            webView.frame = CGRect(origin: .zero, size: targetSize)
        }
        webView.autoresizingMask = []

        // Move snapshot layer ABOVE the webView so it covers during the animation.
        // (installTransitionSnapshot inserts at position 0, which is below the webView)
        if let snapshot = transitionSnapshotLayer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.addSublayer(snapshot) // Moves existing layer to top
            CATransaction.commit()
        }

        // After the animation completes, restore normal frame management and remove snapshot.
        // Use a cancellable work item so rapid re-entry can abort this cleanup.
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            snapshotExitWork = nil

            // Restore normal frame management
            isHoldingWebViewFrame = false
            webView.autoresizingMask = [.width, .height]
            webView.frame = bounds

            // Wait for WebKit to paint at the final size before revealing
            webView._do(afterNextPresentationUpdate: { [weak self] in
                MainActor.assumeIsolated {
                    self?.removeTransitionSnapshot()
                }
            })

            // Safety fallback if presentation update never fires (suspended page, etc.)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.removeTransitionSnapshot()
            }
        }
        snapshotExitWork = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration, execute: workItem)
    }

    /// Prepares the adapter for dismantling by SwiftUI.
    ///
    /// Clears delegate and removes webView from hierarchy. When the adapter is being
    /// dismantled, the webView needs to be explicitly removed so it can be added
    /// to a different adapter if needed.
    func prepareForDismantle() {
        pendingPortalSourceLayer = nil
        removeTransitionSnapshot()

        // Full cleanup - remove webView from hierarchy
        cleanupCurrentMode()
        displayMode = .inactive
    }

    /// Cleans up the current display mode before switching.
    ///
    /// WebViews are removed from the superview rather than hidden. This prevents
    /// unbounded growth of the subviews array. Adding/removing subviews is cheap;
    /// the main optimization is keeping the same adapter container for each position.
    private func cleanupCurrentMode() {
        switch displayMode {
        case .inactive:
            break

        case let .active(webView):
            if webView.superview === self {
                webView.delegate = nil
                webView.removeFromSuperview()
            }

        case .portal:
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            portalLayer?.removeFromSuperlayer()
            portalLayer = nil
            CATransaction.commit()

        case .snapshot:
            // Snapshot layer is cleaned up separately via removeTransitionSnapshot
            break
        }
    }

    // MARK: - Transition Snapshot

    /// Captures a GPU-backed snapshot of the current window content cropped to adapter bounds.
    ///
    /// Uses `CGSHWCaptureWindowList` (the same API Safari/WebKit uses) to synchronously capture
    /// the window's GPU textures. This must be called BEFORE `cleanupCurrentMode()` removes the
    /// webView from the hierarchy, as the capture needs the rendered content still on screen.
    ///
    /// The snapshot is installed as a layer behind the portal, acting as a static fallback
    /// that becomes visible when the portal source is orphaned (secondary window closes).
    private func captureTransitionSnapshot() {
        guard case .active = displayMode,
              let window, window.isVisible,
              bounds.width > 0, bounds.height > 0 else { return }

        var windowID = CGSWindowID(window.windowNumber)
        let options = CGSWindowCaptureOptions(kCGSCaptureIgnoreGlobalClipShape)

        // GPU hardware capture (same API Safari/WebKit uses)
        guard let snapshots = CGSHWCaptureWindowList(CGSMainConnectionID(), &windowID, 1, options),
              let first = (snapshots as NSArray).firstObject else { return }
        let fullImage = first as! CGImage

        // Crop to adapter bounds in window coordinates
        let adapterInWindow = convert(bounds, to: nil)
        let scale = window.backingScaleFactor
        let cropRect = CGRect(
            x: adapterInWindow.origin.x * scale,
            y: (window.frame.height - adapterInWindow.maxY) * scale,
            width: adapterInWindow.width * scale,
            height: adapterInWindow.height * scale,
        )

        guard let croppedImage = fullImage.cropping(to: cropRect) else { return }
        installTransitionSnapshot(croppedImage, scale: scale)
    }

    /// Installs a captured snapshot image as a sublayer behind the portal.
    private func installTransitionSnapshot(_ image: CGImage, scale: CGFloat) {
        // Remove any existing snapshot first
        transitionSnapshotLayer?.removeFromSuperlayer()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let snapshot = CALayer()
        snapshot.contents = image
        snapshot.contentsGravity = .resizeAspectFill
        snapshot.contentsScale = scale
        snapshot.frame = bounds

        // Insert below portal if it exists, otherwise at bottom
        if let portal = portalLayer {
            layer?.insertSublayer(snapshot, below: portal)
        } else {
            layer?.insertSublayer(snapshot, at: 0)
        }

        transitionSnapshotLayer = snapshot
        CATransaction.commit()
    }

    /// Removes the transition snapshot layer and releases the captured image.
    ///
    /// Refuses to remove the snapshot while in `.snapshot` display mode — in that mode
    /// the snapshot IS the primary content. Only `exitSnapshotMode()` should remove it
    /// (it changes displayMode to `.active` first, then schedules removal).
    private func removeTransitionSnapshot() {
        if case .snapshot = displayMode { return }
        guard transitionSnapshotLayer != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        transitionSnapshotLayer?.removeFromSuperlayer()
        transitionSnapshotLayer = nil
        CATransaction.commit()
    }

    // MARK: - Layout

    /// Synchronizes subview frames based on current bounds.
    ///
    /// This uses frame-based layout (autoresizing masks) instead of Auto Layout constraints
    /// because WebKit's Web Inspector docking system directly manipulates the inspected view's
    /// frame via `inspectedViewFrameDidChange()`. Auto Layout constraints fight with these
    /// direct frame changes, causing the inspector to break when docked.
    override func layout() {
        super.layout()

        // Update transition snapshot frame to match current bounds.
        // This covers both portal transitions and snapshot mode (layout mode).
        if transitionSnapshotLayer != nil {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            transitionSnapshotLayer?.frame = bounds
            CATransaction.commit()
        }

        // Update portal layer frame if in portal mode
        if case .portal = displayMode {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            portalLayer?.frame = bounds
            CATransaction.commit()
        }

        // Sync webView frame: find bar at top, webView below (or fills bounds if no find bar).
        // Skip when holding the webView frame during a snapshot exit transition — the webView
        // is pinned at the final target size while the snapshot covers the animation.
        if case .active = displayMode, !isHoldingWebViewFrame {
            if isFindBarVisible, let findBarView {
                let findBarHeight = findBarView.fittingSize.height
                findBarView.frame = NSRect(
                    x: 0,
                    y: bounds.height - findBarHeight,
                    width: bounds.width,
                    height: findBarHeight,
                )

                webView?.frame = NSRect(
                    x: 0,
                    y: 0,
                    width: bounds.width,
                    height: bounds.height - findBarHeight,
                )
            } else {
                webView?.frame = bounds
            }
        }
    }

    // MARK: - Content Inset

    /// Applies the top content inset to the web view.
    ///
    /// Uses WebKit's `_setObscuredContentInsets:immediate:` API to push web content down,
    /// allowing it to scroll behind toolbar areas. This also triggers scroll pocket creation
    /// when `usesAutomaticContentInsetBackgroundFill` is enabled.
    ///
    /// This is called both when `topContentInset` changes AND after `setActiveMode`
    /// to ensure the inset is applied even when the mode changes while the inset value
    /// remains the same.
    ///
    /// - Parameter immediate: If true, applies the inset immediately without animation.
    ///   This is useful when displaying in a new window to prevent the delayed inset
    ///   application that WebKit normally applies.
    func applyTopContentInset(immediate: Bool = true) {
        guard case let .active(webView) = displayMode else { return }

        // Skip inset application during window moves. The inset was pre-applied
        // in addWebViewToHierarchy before the move to avoid scroll corruption.
        guard !isPendingWindowMove else {
            return
        }

        // Choose API based on whether scroll pocket system is enabled.
        //
        // When usesAutomaticContentInsetBackgroundFill is false:
        //   Use _setTopContentInset which sets obscuredContentInsets without triggering
        //   scroll pocket creation. This is called FIRST during initialization, before
        //   applyAutomaticContentInsetBackgroundFill(), so the insets are set but no
        //   scroll pocket is created yet.
        //
        // When usesAutomaticContentInsetBackgroundFill is true:
        //   Use _setObscuredContentInsets to update insets. If called after scroll pocket
        //   was already created (via applyAutomaticContentInsetBackgroundFill), this just
        //   updates the inset value.
        if usesAutomaticContentInsetBackgroundFill {
            let insets = NSEdgeInsets(top: topContentInset, left: 0, bottom: 0, right: 0)
            webView._setObscuredContentInsets(insets, immediate: immediate)
        } else {
            webView._setTopContentInset(topContentInset, immediate: immediate)
        }
    }

    /// Applies the automatic content inset background fill setting.
    ///
    /// Enables the NSScrollPocket system which allows WebKit to:
    /// - Detect sticky headers via `_prefersSolidColorHardScrollPocket`
    /// - Automatically sample and adapt colors from page content
    ///
    /// ## Scroll Pocket Creation
    ///
    /// Setting `_usesAutomaticContentInsetBackgroundFill = true` triggers WebKit's
    /// `setClientImplicitlyRequestedTopScrollPocket()` which calls `updateScrollPocket()`.
    /// If `obscuredContentInsets().top() > 0` (set by prior call to `applyTopContentInset()`),
    /// the scroll pocket is created at this point.
    ///
    /// This is why the call order matters: `applyTopContentInset()` must be called BEFORE
    /// this function to set the insets, then this function triggers scroll pocket creation.
    func applyAutomaticContentInsetBackgroundFill() {
        guard case let .active(webView) = displayMode else {
            return
        }

        // Defer during window moves, same as applyTopContentInset.
        guard !isPendingWindowMove else { return }

        webView._usesAutomaticContentInsetBackgroundFill = usesAutomaticContentInsetBackgroundFill
    }

    // MARK: - Find Bar Management

    private func findBarDidBecomeVisible() {
        guard webView != nil else {
            return
        }

        guard let findBarView else {
            // NSTextFinder hasn't created the bar view yet — this can happen
            // if isFindBarVisible is set before performAction(.showFindInterface).
            // Reset and bail; the caller should go through NSTextFinder instead.
            isFindBarVisible = false
            return
        }

        // Use frame-based layout with autoresizing for width
        findBarView.translatesAutoresizingMaskIntoConstraints = true
        findBarView.autoresizingMask = [.width, .minYMargin]
        addSubview(findBarView)

        // Trigger layout to position find bar and resize webView
        needsLayout = true
    }

    private func findBarDidBecomeHidden() {
        findBarView?.removeFromSuperview()
        webView?._hideFindUI()

        // Trigger layout to restore webView to full bounds
        needsLayout = true

        DispatchQueue.main.async { [weak self] in
            guard let webView = self?.webView else {
                return
            }
            webView.window?.makeFirstResponder(webView)
        }
    }

    // MARK: - Find Panel Actions

    /// Called by the Find menu items in the Menu Bar.
    @objc(performFindPanelAction:)
    func performFindPanelAction(_ sender: Any!) {
        guard let item = sender as? NSMenuItem,
              let action = NSTextFinder.Action(rawValue: item.tag)
        else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.findInteraction?.performAction(action)
        }
    }
}

// MARK: - NSTextFinderBarContainer

extension CocoaWebViewAdapter: NSTextFinderBarContainer {
    func contentView() -> NSView? {
        webView
    }

    func findBarViewDidChangeHeight() {
        // No action needed
    }
}

// MARK: - WebPageWebView.Delegate

extension CocoaWebViewAdapter {
    /// Receives scroll geometry change notifications from the web view.
    ///
    /// This implementation is intentionally empty because scroll geometry
    /// observation is not used in Refrax. The browser handles scroll tracking
    /// through other means (direct delegate observation, not SwiftUI environment).
    ///
    /// The protocol conformance is required because `WebPageWebView.Delegate`
    /// mandates this method, but Refrax intentionally doesn't propagate these
    /// events through the SwiftUI environment for performance reasons.
    ///
    /// - Note: If you need scroll geometry updates, observe them directly on
    ///   `WebPageWebView` rather than through SwiftUI modifiers.
    func geometryDidChange(_: WKScrollGeometryAdapter) {
        // Intentionally empty - scroll geometry observation is not used in Refrax.
        // See WebViewEnvironment.swift for details on why this feature is unavailable.
    }
}
