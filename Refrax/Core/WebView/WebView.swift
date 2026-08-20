import SwiftUI
import WebKit

/// A SwiftUI view for displaying interactive web content.
///
/// `WebView` provides a SwiftUI interface for displaying web content managed by a `WebPage`.
/// It mirrors Apple's WebKit SwiftUI API while providing additional browser-specific features.
///
/// ## Key Features
///
/// - **WebPage integration**: Full control via `WebPage` observable object
/// - **Multi-window support**: Same page can appear in multiple windows via portal layers
/// - **Deep link routing**: Automatically renders native views for `refrax://` URLs
/// - **Browser behaviors**: Back/forward gestures, link previews, text selection
///
/// ## Basic Usage
///
/// ```swift
/// // Create with explicit WebPage
/// let page = WebPage()
/// page.load(url)
///
/// WebView(page)
///     .webViewBackForwardNavigationGestures(.enabled)
///     .webViewLinkPreviews(.enabled)
/// ```
///
/// ## URL-based Initialization
///
/// For simpler use cases, initialize directly with a URL:
///
/// ```swift
/// WebView(url: URL(string: "https://example.com"))
/// ```
///
/// This creates an internal `WebPage` and loads the URL automatically.
///
/// ## Multi-Window Display
///
/// In multi-window scenarios, only one window should have the interactive web view.
/// Others can display a read-only mirror:
///
/// ```swift
/// // Active window - receives input
/// WebView(page)
///     .webViewIsActive(true)
///
/// // Secondary window - read-only portal mirror
/// WebView(page)
///     .webViewIsActive(false)
/// ```
///
/// ## Deep Links
///
/// URLs with the `refrax://` scheme render native interstitial views:
///
/// - `refrax://ssl-error` → SSL certificate error page
/// - `refrax://focus-blocked` → Focus mode blocked page
struct WebView: View {
    // MARK: - Storage

    /// The web page providing the content.
    private let page: WebPage

    // MARK: - Environment

    /// Environment value controlling active/portal mode.
    @Environment(\.webViewIsActive) private var isActive

    /// Environment value for interaction blocking.
    @Environment(\.webViewIgnoresMouseMoveEvents) private var ignoresMouseMoveEvents

    /// Environment value for blocking all events when overlay is visible.
    @Environment(\.webViewIgnoresAllEvents) private var ignoresAllEvents

    // MARK: - Initialization

    /// Creates a web view displaying the content managed by a `WebPage`.
    ///
    /// - Parameter page: The `WebPage` managing the web content.
    init(_ page: WebPage) {
        self.page = page
    }

    // MARK: - Body

    var body: some View {
        WebViewRepresentable(
            page: page,
            isActive: isActive,
            ignoresAllEvents: ignoresAllEvents,
            ignoresMouseMoveEvents: ignoresMouseMoveEvents,
        )
    }
}

// MARK: - Internal WebViewRepresentable

/// NSViewRepresentable bridge between SwiftUI and the Cocoa web view adapter.
///
/// ## Performance Optimizations
///
/// This representable implements several optimizations for rapid tab switching:
///
/// 1. **Configuration Locking**: When `webViewConfigurationLocked` is `true`, static
///    settings (gestures, previews, etc.) are applied once and subsequent updates skipped.
///
/// 2. **Change Detection**: The coordinator caches previous values to avoid redundant
///    property assignments on unchanged values.
///
/// 3. **Minimal updateNSView**: Only display mode and dynamic properties are updated
///    on every SwiftUI pass when configuration is locked.
///
/// ## Reference
///
/// Mirrors WebKit's `WebViewRepresentable` from:
/// `WebKit/Source/WebKit/_WebKit_SwiftUI/Implementation/WebViewRepresentable.swift`
struct WebViewRepresentable: NSViewRepresentable {
    /// The web page providing the content.
    let page: WebPage

    /// Whether this view should be in active (interactive) mode.
    let isActive: Bool

    /// Whether interaction is blocked.
    let ignoresAllEvents: Bool

    /// Whether all events are blocked due to an overlay.
    let ignoresMouseMoveEvents: Bool

    func makeNSView(context _: Context) -> CocoaWebViewAdapter {
        let adapter = CocoaWebViewAdapter()
        // Don't call updateDisplayMode here - the adapter has zero bounds at this point.
        // SwiftUI will immediately call updateNSView after layout, which will set up
        // the display mode with correct bounds.
        return adapter
    }

    func updateNSView(_ adapter: CocoaWebViewAdapter, context: Context) {
        let webView = page.backingWebView
        let coordinator = context.coordinator
        let environment = context.environment

        // Check if configuration is locked - skip most updates if so
        let isLocked = environment.webViewConfigurationLocked

        // Track whether we need to reconfigure (page changed or first time for this page)
        let pageChanged = coordinator.currentPageID != page.id
        let needsConfiguration = pageChanged || !coordinator.hasAppliedInitialConfiguration

        if needsConfiguration {
            coordinator.currentPageID = page.id
            coordinator.hasAppliedInitialConfiguration = true

            // Apply full web view configuration on page change
            applyFullConfiguration(webView, environment: environment, coordinator: coordinator)
        } else if !isLocked {
            // Only apply configuration updates if not locked
            applyConfigurationUpdates(webView, environment: environment, coordinator: coordinator)
        }

        // Display mode ALWAYS needs updating (tab switching, portal mode)
        updateDisplayMode(adapter, webView: webView)

        // Interaction blocking ALWAYS needs updating (quick look, etc.)
        applyInteractionBlocking(webView)

        // Dynamic properties that may change frequently (find, scroll position)
        applyDynamicSettings(adapter, environment: environment)

        // Update coordinator state
        coordinator.update(adapter, environment: environment)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView _: CocoaWebViewAdapter, context _: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else {
            return nil
        }

        // WebKit requires integer sizes to avoid rendering glitches.
        // Rounding down ensures the view never exceeds the requested size.
        // Reference: WebKit's WebViewRepresentable.swift:147-152
        return CGSize(width: width.rounded(.down), height: height.rounded(.down))
    }

    static func dismantleNSView(_ nsView: CocoaWebViewAdapter, coordinator: Coordinator) {
        // Don't call setInactiveMode() here — it would remove the webView from the
        // superview, but that's unnecessary work:
        // 1. The adapter is being removed from the view hierarchy by SwiftUI anyway
        // 2. When the webView is needed again, addSubview() will automatically
        //    remove it from its old superview (this adapter) before adding to the new one
        // 3. Explicit removal here causes extra view hierarchy churn during tab switching
        //
        // We just clean up the delegate to prevent callbacks to a dismantled adapter.
        nsView.prepareForDismantle()
        coordinator.cleanup()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Display Mode

    /// Updates the display mode based on active state.
    ///
    /// This is always called regardless of configuration lock since tab switching
    /// and multi-window scenarios require mode updates.
    private func updateDisplayMode(_ adapter: CocoaWebViewAdapter, webView: WebPageWebView) {
        // While the windowed-fullscreen video window hosts the web view, the
        // tab keeps its frozen snapshot — reclaiming the web view here would
        // yank it out of the video window on the next SwiftUI pass.
        if page.isWebViewInVideoWindow {
            if case .active = adapter.displayMode {
                adapter.setSnapshotMode(for: page)
            }
            return
        }

        if isActive {
            if adapter.bounds.size == .zero {
                // Adapter hasn't been laid out yet. Defer activation until after layout.
                // This happens when created inside an NSSplitViewItem inspector that hasn't
                // completed its initial layout pass. Without deferral, active mode is never
                // set and the content stays invisible.
                DispatchQueue.main.async {
                    guard adapter.bounds.size != .zero else { return }
                    adapter.setActiveMode(webView: webView, expectedFrame: webView.frame)
                }
                return
            }

            adapter.setActiveMode(webView: webView, expectedFrame: webView.frame)
        } else {
            if let layer = webView.layer {
                adapter.setPortalMode(sourceLayer: layer)
            } else {
                adapter.setInactiveMode()
            }
        }
    }

    // MARK: - Configuration

    /// Applies full web view configuration (called on page change or first setup).
    ///
    /// These settings are typically static and don't change during the lifetime
    /// of a browsing session. We check current values before setting to avoid
    /// redundant property assignments that might trigger internal WebKit work.
    private func applyFullConfiguration(
        _ webView: WebPageWebView,
        environment: EnvironmentValues,
        coordinator: Coordinator,
    ) {
        // Navigation gestures
        let allowsGestures = environment.webViewAllowsBackForwardNavigationGestures != .disabled
        if webView.allowsBackForwardNavigationGestures != allowsGestures {
            webView.allowsBackForwardNavigationGestures = allowsGestures
        }
        coordinator.cachedAllowsBackForwardGestures = allowsGestures

        // Link previews
        let allowsLinkPreview = environment.webViewAllowsLinkPreview != .disabled
        if webView.allowsLinkPreview != allowsLinkPreview {
            webView.allowsLinkPreview = allowsLinkPreview
        }
        coordinator.cachedAllowsLinkPreview = allowsLinkPreview

        // Magnification
        let allowsMagnification = environment.webViewMagnificationGestures != .disabled
        if webView.allowsMagnification != allowsMagnification {
            webView.allowsMagnification = allowsMagnification
        }
        coordinator.cachedAllowsMagnification = allowsMagnification

        // Background drawing
        let drawsBackground = environment.webViewContentBackground != .hidden
        if webView._drawsBackground != drawsBackground {
            webView._drawsBackground = drawsBackground
        }
        coordinator.cachedDrawsBackground = drawsBackground

        // NOTE: Scroll edge effect style (_usesAutomaticContentInsetBackgroundFill) is NOT set here.
        // It MUST be set through the adapter in applyDynamicSettings() AFTER the content insets
        // are configured. Setting it early causes WebKit's setClientImplicitlyRequestedTopScrollPocket()
        // to be called with topContentInset=0, and subsequent calls early-return without ever
        // calling updateScrollPocket() with the correct insets.

        // Automatic content inset adjustment
        // Disable when manually providing content insets (e.g., reference pane window)
        let automaticallyAdjustsInsets = environment.webViewAutomaticallyAdjustsContentInsets
        if webView._automaticallyAdjustsContentInsets != automaticallyAdjustsInsets {
            webView._automaticallyAdjustsContentInsets = automaticallyAdjustsInsets
        }

        // Text selection
        let textSelection = environment.webViewTextSelection
        if webView.configuration.preferences.isTextInteractionEnabled != textSelection {
            webView.configuration.preferences.isTextInteractionEnabled = textSelection
        }
        coordinator.cachedTextSelection = textSelection

        // Element fullscreen
        let fullscreenEnabled = environment.webViewElementFullscreenBehavior == .enabled
        if webView.configuration.preferences.isElementFullscreenEnabled != fullscreenEnabled {
            webView.configuration.preferences.isElementFullscreenEnabled = fullscreenEnabled
        }
        coordinator.cachedElementFullscreen = fullscreenEnabled

        // Scroll bounce behavior (apply once)
        applyScrollBounceBehavior(webView, environment: environment, coordinator: coordinator)
    }

    /// Applies configuration updates only for changed values (when not locked).
    ///
    /// Uses cached values in coordinator to detect changes and avoid redundant updates.
    private func applyConfigurationUpdates(
        _ webView: WebPageWebView,
        environment: EnvironmentValues,
        coordinator: Coordinator,
    ) {
        // Navigation gestures
        let allowsGestures = environment.webViewAllowsBackForwardNavigationGestures != .disabled
        if coordinator.cachedAllowsBackForwardGestures != allowsGestures {
            webView.allowsBackForwardNavigationGestures = allowsGestures
            coordinator.cachedAllowsBackForwardGestures = allowsGestures
        }

        // Link previews
        let allowsLinkPreview = environment.webViewAllowsLinkPreview != .disabled
        if coordinator.cachedAllowsLinkPreview != allowsLinkPreview {
            webView.allowsLinkPreview = allowsLinkPreview
            coordinator.cachedAllowsLinkPreview = allowsLinkPreview
        }

        // Magnification
        let allowsMagnification = environment.webViewMagnificationGestures != .disabled
        if coordinator.cachedAllowsMagnification != allowsMagnification {
            webView.allowsMagnification = allowsMagnification
            coordinator.cachedAllowsMagnification = allowsMagnification
        }

        // Background drawing
        let drawsBackground = environment.webViewContentBackground != .hidden
        if coordinator.cachedDrawsBackground != drawsBackground {
            webView._drawsBackground = drawsBackground
            coordinator.cachedDrawsBackground = drawsBackground
        }

        // Text selection
        let textSelection = environment.webViewTextSelection
        if coordinator.cachedTextSelection != textSelection {
            webView.configuration.preferences.isTextInteractionEnabled = textSelection
            coordinator.cachedTextSelection = textSelection
        }

        // Element fullscreen
        let fullscreenEnabled = environment.webViewElementFullscreenBehavior == .enabled
        if coordinator.cachedElementFullscreen != fullscreenEnabled {
            webView.configuration.preferences.isElementFullscreenEnabled = fullscreenEnabled
            coordinator.cachedElementFullscreen = fullscreenEnabled
        }
    }

    /// Applies interaction blocking state.
    private func applyInteractionBlocking(_ webView: WebPageWebView) {
        if webView._ignoresAllEvents != ignoresAllEvents {
            webView._ignoresAllEvents = ignoresAllEvents
        }
        if webView._ignoresMouseMoveEvents != ignoresMouseMoveEvents {
            webView._ignoresMouseMoveEvents = ignoresMouseMoveEvents
        }
    }

    /// Applies dynamic settings that may change frequently.
    ///
    /// These are always applied regardless of configuration lock:
    /// - Find navigator state
    /// - Scroll position
    /// - Mouse down callback
    /// - Top content inset
    private func applyDynamicSettings(
        _ adapter: CocoaWebViewAdapter,
        environment: EnvironmentValues,
    ) {
        // Find navigator
        adapter.findContext = environment.webViewFindContext

        // Scroll position
        adapter.scrollPositionContext = environment.webViewScrollPositionContext

        // Mouse down callback for focus tracking
        adapter.onMouseDown = environment.webViewOnMouseDown

        // Top content inset for toolbar areas.
        // IMPORTANT: This must be set BEFORE usesAutomaticContentInsetBackgroundFill for scroll
        // pocket creation to work correctly. Here's why:
        //
        // WebKit's setClientImplicitlyRequestedTopScrollPocket() only calls updateScrollPocket()
        // the FIRST time the flag is set. Subsequent calls early-return. So the order matters:
        //
        // 1. applyTopContentInset() → _setTopContentInset(40) sets obscuredContentInsets.top=40
        //    (but doesn't trigger scroll pocket creation because usesAutomaticContentInsetBackgroundFill=false)
        // 2. applyAutomaticContentInsetBackgroundFill() → _usesAutomaticContentInsetBackgroundFill=true
        //    → WebKit calls setClientImplicitlyRequestedTopScrollPocket() (first time)
        //    → updateScrollPocket() is called with topContentInset=40 → scroll pocket created!
        //
        // The setters have didSet guards that call the apply methods only when values change,
        // so we don't need to call them explicitly here.
        adapter.topContentInset = environment.webViewTopContentInset

        // Automatic content inset background fill for scroll pocket system (sticky header detection).
        // This triggers scroll pocket creation if topContentInset > 0 was set above.
        //
        // The value is derived from two sources:
        // 1. webViewScrollEdgeEffectStyleContext - if set via .webViewScrollEdgeEffectStyle(_:for:)
        // 2. webViewUsesAutomaticContentInsetBackgroundFill - if set explicitly
        // The scroll edge context takes precedence if present.
        let usesAutomaticFill: Bool = if let scrollEdgeContext = environment.webViewScrollEdgeEffectStyleContext {
            // When using scroll edge effect styles, automatic fill = not hard style
            scrollEdgeContext.style != .hard
        } else {
            environment.webViewUsesAutomaticContentInsetBackgroundFill
        }
        adapter.usesAutomaticContentInsetBackgroundFill = usesAutomaticFill
    }

    /// Applies scroll bounce behavior settings.
    private func applyScrollBounceBehavior(
        _ webView: WebPageWebView,
        environment: EnvironmentValues,
        coordinator: Coordinator,
    ) {
        let verticalBounce = EquatableScrollBounceBehavior(environment.verticalScrollBounceBehavior)
        let horizontalBounce = EquatableScrollBounceBehavior(environment.horizontalScrollBounceBehavior)

        // Apply vertical bounce if changed
        if coordinator.cachedVerticalBounce != verticalBounce {
            applyBounceBehavior(verticalBounce, to: webView, axis: .vertical)
            coordinator.cachedVerticalBounce = verticalBounce
        }

        // Apply horizontal bounce if changed
        if coordinator.cachedHorizontalBounce != horizontalBounce {
            applyBounceBehavior(horizontalBounce, to: webView, axis: .horizontal)
            coordinator.cachedHorizontalBounce = horizontalBounce
        }
    }

    /// Applies bounce behavior for a specific axis.
    private func applyBounceBehavior(
        _ behavior: EquatableScrollBounceBehavior,
        to webView: WebPageWebView,
        axis: Axis,
    ) {
        switch behavior {
        case .always:
            if axis == .vertical {
                webView.alwaysBounceVertical = true
                webView.bouncesVertically = true
            } else {
                webView.alwaysBounceHorizontal = true
                webView.bouncesHorizontally = true
            }
        case .automatic, .basedOnSize:
            // On macOS, disable rubber-band bounce by default. iOS-style elastic
            // overscroll interacts poorly with pages that animate element heights
            // (loading skeletons, pulsing indicators) — WebKit's scroll position
            // compensation oscillates instead of settling at the edge boundary.
            if axis == .vertical {
                webView.alwaysBounceVertical = false
                webView.bouncesVertically = false
            } else {
                webView.alwaysBounceHorizontal = false
                webView.bouncesHorizontally = false
            }
        default:
            break
        }
    }
}

// MARK: - Coordinator

extension WebViewRepresentable {
    /// Coordinator managing representable state and updates.
    ///
    /// The coordinator serves two purposes:
    /// 1. Managing find navigator and scroll position updates
    /// 2. Caching configuration values for change detection optimization
    ///
    /// ## Change Detection
    ///
    /// To avoid redundant WKWebView property assignments on every SwiftUI update,
    /// the coordinator caches the last-applied values and only updates when changed.
    /// This is especially important for properties like `allowsBackForwardNavigationGestures`
    /// which may trigger internal WKWebView reconfiguration.
    final class Coordinator {
        /// The ID of the currently configured page.
        var currentPageID: WebPage.ID?

        /// Whether initial configuration has been applied.
        var hasAppliedInitialConfiguration = false

        // MARK: - Cached Configuration Values

        /// Cached value for back/forward navigation gestures.
        var cachedAllowsBackForwardGestures: Bool?

        /// Cached value for link preview.
        var cachedAllowsLinkPreview: Bool?

        /// Cached value for magnification.
        var cachedAllowsMagnification: Bool?

        /// Cached value for background drawing.
        var cachedDrawsBackground: Bool?

        /// Cached value for text selection.
        var cachedTextSelection: Bool?

        /// Cached value for element fullscreen.
        var cachedElementFullscreen: Bool?

        /// Cached value for vertical bounce behavior.
        var cachedVerticalBounce: EquatableScrollBounceBehavior?

        /// Cached value for horizontal bounce behavior.
        var cachedHorizontalBounce: EquatableScrollBounceBehavior?

        /// Updates coordinator state with new configuration.
        func update(_ adapter: CocoaWebViewAdapter, environment: EnvironmentValues) {
            updateFindNavigator(adapter, environment: environment)
            updateScrollPosition(adapter, environment: environment)
        }

        /// Cleans up coordinator resources.
        func cleanup() {
            currentPageID = nil
            hasAppliedInitialConfiguration = false
            clearCachedValues()
        }

        /// Clears all cached configuration values.
        private func clearCachedValues() {
            cachedAllowsBackForwardGestures = nil
            cachedAllowsLinkPreview = nil
            cachedAllowsMagnification = nil
            cachedDrawsBackground = nil
            cachedTextSelection = nil
            cachedElementFullscreen = nil
            cachedVerticalBounce = nil
            cachedHorizontalBounce = nil
        }

        // MARK: - Find Navigator

        private func updateFindNavigator(_ adapter: CocoaWebViewAdapter, environment _: EnvironmentValues) {
            guard let findContext = adapter.findContext else { return }

            let isVisible = adapter.isFindNavigatorVisible

            if let isPresented = findContext.isPresented?.wrappedValue {
                if isPresented, !isVisible {
                    showFindNavigator(adapter)
                } else if !isPresented, isVisible {
                    hideFindNavigator(adapter)
                }
            }
        }

        private func showFindNavigator(_ adapter: CocoaWebViewAdapter) {
            DispatchQueue.main.async {
                adapter.webView?.enclosingScrollView?.isFindBarVisible = true
            }
        }

        private func hideFindNavigator(_ adapter: CocoaWebViewAdapter) {
            DispatchQueue.main.async {
                adapter.webView?.enclosingScrollView?.isFindBarVisible = false
            }
        }

        // MARK: - Scroll Position

        private func updateScrollPosition(_ adapter: CocoaWebViewAdapter, environment _: EnvironmentValues) {
            guard let webView = adapter.webView,
                  let scrollContext = adapter.scrollPositionContext,
                  let position = scrollContext.position?.wrappedValue
            else { return }

            // Only scroll to top if not already positioned by user
            if !position.isPositionedByUser {
                webView.setContentOffset(x: 0, y: 0, animated: false)
            }
        }
    }
}

// MARK: - Scroll Bounce Behavior Wrapper

/// Wrapper for equatable comparison of `ScrollBounceBehavior`.
///
/// `ScrollBounceBehavior` doesn't conform to `Equatable`, so we use a normalized
/// case identifier to compare values. This avoids fragile byte comparisons.
struct EquatableScrollBounceBehavior: Equatable {
    static let automatic = Self(.automatic)
    static let always = Self(.always)
    static let basedOnSize = Self(.basedOnSize)

    let behavior: ScrollBounceBehavior

    /// Normalized identifier for comparison.
    private let caseID: Int

    init(_ behavior: ScrollBounceBehavior) {
        self.behavior = behavior
        // Determine case by comparing against known values
        self.caseID = Self.identifyCase(behavior)
    }

    /// Identifies the case of a ScrollBounceBehavior by comparing against known values.
    private static func identifyCase(_ behavior: ScrollBounceBehavior) -> Int {
        // Compare raw bytes against known cases to determine which one this is
        // This is safe because we only compare against the three known cases
        let knownCases: [(ScrollBounceBehavior, Int)] = [
            (.automatic, 0),
            (.always, 1),
            (.basedOnSize, 2),
        ]

        for (known, id) in knownCases {
            if bytesEqual(behavior, known) {
                return id
            }
        }
        return -1 // Unknown case
    }

    /// Compares two ScrollBounceBehavior values by their raw bytes.
    private static func bytesEqual(_ lhs: ScrollBounceBehavior, _ rhs: ScrollBounceBehavior) -> Bool {
        withUnsafeBytes(of: lhs) { lhsPtr in
            withUnsafeBytes(of: rhs) { rhsPtr in
                lhsPtr.elementsEqual(rhsPtr)
            }
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.caseID == rhs.caseID
    }
}

// MARK: - Edge Extensions

private extension Edge {
    /// Converts SwiftUI Edge to NSDirectionalRectEdge.
    var directionalEdge: NSDirectionalRectEdge {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }
}
