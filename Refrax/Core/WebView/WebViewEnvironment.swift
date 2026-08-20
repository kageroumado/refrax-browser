import SwiftUI

// MARK: - Environment Values Extension

extension EnvironmentValues {
    /// Context for overriding AddressBar behavior in different contexts.
    ///
    /// When set, AddressBar uses this context instead of the default WindowState-based behavior.
    /// This enables reusing AddressBar in contexts like the reference pane window.
    @Entry var addressBarContext: AddressBarContext? = nil
    
    /// Whether the AddressBar is floating over the main content instead of being inside the Sidebar.
    @Entry var addressBarIsFloating: Bool = false

    /// Controls whether horizontal swipe gestures trigger back/forward navigation.
    @Entry var webViewAllowsBackForwardNavigationGestures: WebView.BackForwardNavigationGesturesBehavior = .enabled

    /// Controls link preview behavior when pressing on links.
    ///
    /// Defaults to `.disabled` because Refrax provides its own link preview via
    /// `LinkPreviewManager`, which handles both Shift+Click and Force Touch with
    /// a custom panel that preserves WebPage sessions when converting to tabs.
    @Entry var webViewAllowsLinkPreview: WebView.LinkPreviewBehavior = .disabled

    /// Controls magnification gesture behavior.
    @Entry var webViewMagnificationGestures: WebView.MagnificationGesturesBehavior = .automatic

    /// Controls content background visibility.
    @Entry var webViewContentBackground: Visibility = .automatic

    /// Controls scroll edge effect style.
    @Entry var webViewScrollEdgeEffectStyleContext: ScrollEdgeEffectStyleContext? = nil

    /// Controls whether text selection is enabled.
    @Entry var webViewTextSelection: Bool = true

    /// Controls element fullscreen behavior.

    /// Find navigator context for find-in-page.
    @Entry var webViewFindContext: FindContext? = nil

    /// Scroll position context for bidirectional scroll sync.
    @Entry var webViewScrollPositionContext: ScrollPositionContext? = nil

    /// Whether the web view should be in active (interactive) mode.
    @Entry var webViewIsActive: Bool = true

    /// Whether web view interaction is blocked.
    @Entry var webViewIgnoresMouseMoveEvents: Bool = false

    /// Whether all events to the web view are blocked due to an overlay.
    ///
    /// When `true`, the web view will not receive any input events, allowing
    /// overlaying UI elements (sidebar, detail tray) to receive all interactions.
    /// This prevents:
    /// - Clicks on web content under the overlay
    /// - Hover effects and cursor changes
    /// - Scroll events
    ///
    /// Use this when an overlay covers the web view and should receive events
    /// instead of the underlying web content.
    ///
    /// - Note: This uses WebKit's private `_ignoresAllEvents` API. For blocking
    ///   only mouse move events (e.g., cursor changes), a separate API would be needed.
    @Entry var webViewIgnoresAllEvents: Bool = false

    /// Callback invoked when the user clicks on the web view.
    /// Used for focus tracking in the address bar.
    @Entry var webViewOnMouseDown: (() -> Void)? = nil

    /// Top content inset for the web view.
    ///
    /// When set to a non-zero value, the web content is pushed down by this amount,
    /// creating space for a toolbar or other UI elements that overlay the web view.
    /// This uses WebKit's `_topContentInset` API to properly inset the rendering area.
    @Entry var webViewTopContentInset: CGFloat = 0

    /// Whether WebKit should automatically adjust content insets based on window position.
    ///
    /// When `true` (default), WebKit monitors window position and titlebar adjacency
    /// to automatically compute content insets. This works well for main browser windows.
    ///
    /// Set to `false` when manually providing content insets (e.g., in the reference pane
    /// window) to prevent WebKit from overriding manual insets during window operations.
    @Entry var webViewAutomaticallyAdjustsContentInsets: Bool = true

    /// Whether WebKit should use the automatic content inset background fill system.
    ///
    /// When `true`, enables the NSScrollPocket system (macOS 26+) which:
    /// - Renders scroll pocket with `NSScrollPocketStyleAutomatic`
    /// - Automatically samples and adapts colors from page content
    /// - Enables sticky header detection via `_prefersSolidColorHardScrollPocket`
    ///
    /// ## Prerequisites
    /// For the scroll pocket to be created, you must also set:
    /// - `webViewTopContentInset > 0`
    ///
    /// When `false` (default), scroll pocket renders with `NSScrollPocketStyleHard`
    /// (solid color) requiring manual color management.
    @Entry var webViewUsesAutomaticContentInsetBackgroundFill: Bool = false

    /// Forces the web view to be inactive regardless of ownership state.
    ///
    /// Used when transitioning between docked and separate window modes for reference panes.
    /// When `true`, any `WebViewContainer` in this hierarchy will not claim the WebView,
    /// allowing another window to take ownership.
    @Entry var webViewForcedInactive: Bool = false

    /// Custom ownership ID for multi-window scenarios.
    ///
    /// When set, `WebViewContainer` uses this ID for ownership comparisons instead of
    /// `ObjectIdentifier(windowState)`. This enables windows like `ReflectedViewController`
    /// that manage ownership via their own controller identity to use `WebViewContainer`.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// WebViewContainer(page: webPage)
    ///     .webViewOwnershipID(ObjectIdentifier(self))
    /// ```
    @Entry var webViewOwnershipID: ObjectIdentifier? = nil

    // MARK: - Performance Optimization

    /// Whether configuration settings are locked after initial application.
    ///
    /// When `true`, settings like `allowsBackForwardNavigationGestures`, `allowsLinkPreview`,
    /// `allowsMagnification`, etc. are applied once and subsequent updates are skipped.
    /// This significantly improves performance during rapid tab switching where settings
    /// remain constant across different web pages.
    ///
    /// ## Usage
    ///
    /// Apply this modifier at your container level after setting all configuration:
    ///
    /// ```swift
    /// WebView(page)
    ///     .webViewBackForwardNavigationGestures(.enabled)
    ///     .webViewLinkPreviews(.enabled)
    ///     .webViewConfigurationLocked()  // Lock after setting
    /// ```
    ///
    /// ## Performance Impact
    ///
    /// - **Tab switching**: Eliminates redundant WKWebView property updates
    /// - **Split view resizing**: Reduces SwiftUI update overhead
    /// - **Multi-window**: Portal mode transitions become faster
    ///
    /// - Note: Settings can still be changed by removing and re-adding the modifier.
    @Entry var webViewConfigurationLocked: Bool = false
}

// MARK: - Behavior Types

extension WebView {
    /// Behavior for horizontal swipe gestures triggering back/forward navigation.
    enum BackForwardNavigationGesturesBehavior: Sendable {
        /// Automatic behavior - system chooses based on context (defaults to enabled).
        case automatic

        /// Back/forward gestures are enabled.
        case enabled

        /// Back/forward gestures are disabled.
        case disabled
    }

    /// Behavior for link preview on press.
    enum LinkPreviewBehavior: Sendable {
        /// Automatic behavior - system chooses based on context (defaults to enabled).
        case automatic

        /// Link previews are enabled.
        case enabled

        /// Link previews are disabled.
        case disabled
    }

    /// Behavior for magnification gestures.
    enum MagnificationGesturesBehavior: Sendable {
        /// Automatic behavior - system chooses based on context (defaults to enabled).
        case automatic

        /// Magnification gestures are enabled.
        case enabled

        /// Magnification gestures are disabled.
        case disabled
    }

    /// Information about an activated element for context menus.
    struct ActivatedElementInfo: Hashable, Sendable {
        /// The URL of the activated link, if any.
        let linkURL: URL?

        /// The source URL of an activated image, if any.
        let imageURL: URL?

        /// The media URL (video/audio) if activated.
        let mediaURL: URL?

        /// Creates element info with the given URLs.
        init(linkURL: URL? = nil, imageURL: URL? = nil, mediaURL: URL? = nil) {
            self.linkURL = linkURL
            self.imageURL = imageURL
            self.mediaURL = mediaURL
        }

        /// Creates element info from the context menu adapter.
        init(_ adapter: WKContextMenuElementInfoAdapter) {
            self.linkURL = adapter.linkURL
            self.imageURL = nil
            self.mediaURL = nil
        }
    }
}

// MARK: - Context Types

/// Context for find navigator state.
struct FindContext: Sendable {
    /// Binding controlling whether the find navigator is presented.
    let isPresented: Binding<Bool>?
}

/// Context for scroll position state.
struct ScrollPositionContext: Sendable {
    /// Binding to the scroll position.
    let position: Binding<ScrollPosition>?

    /// Creates a scroll position context with the given position binding.
    init(position: Binding<ScrollPosition>? = nil) {
        self.position = position
    }
}

/// Context for scroll edge effect style.
struct ScrollEdgeEffectStyleContext: Sendable {
    /// The scroll edge effect style.
    let style: ScrollEdgeEffectStyle?

    /// The edges to apply the style to.
    let edges: Edge.Set
}

// MARK: - Unavailable APIs

/// Scroll geometry change observation is not implemented in Refrax.
///
/// This feature is intentionally omitted because:
/// - Browser-level scroll tracking uses `WebPageWebView.Delegate` directly
/// - SwiftUI environment-based scroll observation adds overhead without benefit
/// - The browser manages scroll state through `WKUIDelegateAdapter` and direct delegation
///
/// If you need scroll geometry updates, implement `WebPageWebView.Delegate.geometryDidChange(_:)`
/// on your adapter or view controller instead.
///
/// Reference: WebKit's `OnScrollGeometryChangeContext` in EnvironmentValues+Extras.swift
@available(*, unavailable, message: "Scroll geometry observation is handled via WebPageWebView.Delegate for browser performance")
struct OnScrollGeometryChangeContext: Sendable {
    let transform: @Sendable (ScrollGeometry) -> AnyHashable
    let action: @Sendable (AnyHashable, AnyHashable) -> Void
}

/// Scroll input behavior context is not implemented in Refrax.
///
/// This feature is intentionally omitted because:
/// - visionOS-specific feature not applicable to macOS browser
/// - Look-based scrolling not relevant for desktop browsing
///
/// Reference: WebKit's `ScrollInputBehaviorContext` for visionOS overlay regions
@available(*, unavailable, message: "Scroll input behavior is a visionOS feature not applicable to macOS")
struct ScrollInputBehaviorContext: Sendable {
    let behavior: ScrollInputBehavior
    let input: ScrollInputKind
}

#if os(macOS)
    /// Context menu building via SwiftUI environment is not implemented in Refrax.
    ///
    /// This feature is intentionally omitted because:
    /// - Refrax uses `WKUIDelegateAdapter.menuBuilder` for context menu handling
    /// - Browser context menus require richer functionality than SwiftUI closures provide
    /// - The delegate handles tab-specific actions, downloads, history, and bookmark integration
    ///
    /// Use `WKUIDelegateAdapter.menuBuilder` for context menu customization.
    ///
    /// Reference: WebKit's `ContextMenuContext` in EnvironmentValues+Extras.swift
    @available(*, unavailable, message: "Use WKUIDelegateAdapter.menuBuilder for browser context menus")
    struct ContextMenuContext: Sendable {
        let menuBuilder: @MainActor @Sendable (WebView.ActivatedElementInfo) -> NSMenu
    }
#endif

// MARK: - Scroll Position Value

/// A value representing a scroll position for web views.
///
/// Use this type with the `.webViewScrollPosition(_:)` modifier to
/// programmatically control the scroll position of a web view.
struct ScrollPositionValue: Hashable, Sendable {
    /// A specific point to scroll to.
    let point: CGPoint?

    /// An edge to scroll to.
    let edge: NSRectEdge?

    /// A specific X offset to scroll to.
    let x: CGFloat?

    /// A specific Y offset to scroll to.
    let y: CGFloat?

    /// Creates a scroll position value for a specific point.
    static func point(_ point: CGPoint) -> ScrollPositionValue {
        ScrollPositionValue(point: point, edge: nil, x: nil, y: nil)
    }

    /// Creates a scroll position value for a specific edge.
    static func edge(_ edge: NSRectEdge) -> ScrollPositionValue {
        ScrollPositionValue(point: nil, edge: edge, x: nil, y: nil)
    }

    /// Creates a scroll position value for a specific X offset.
    static func x(_ x: CGFloat) -> ScrollPositionValue {
        ScrollPositionValue(point: nil, edge: nil, x: x, y: nil)
    }

    /// Creates a scroll position value for a specific Y offset.
    static func y(_ y: CGFloat) -> ScrollPositionValue {
        ScrollPositionValue(point: nil, edge: nil, x: nil, y: y)
    }

    private init(point: CGPoint?, edge: NSRectEdge?, x: CGFloat?, y: CGFloat?) {
        self.point = point
        self.edge = edge
        self.x = x
        self.y = y
    }
}

// MARK: - Address Bar Context

/// Context for overriding AddressBar behavior in different contexts.
///
/// This enables reusing the AddressBar component in contexts like the reference pane window,
/// where the web page source and lens behavior differ from the main window.
///
/// ## Usage
///
/// Apply the context via environment modifier:
/// ```swift
/// AddressBar()
///     .environment(\.addressBarContext, AddressBarContext(
///         webPage: myWebPage,
///         tabPage: myTabPage,
///         onOpenLens: { /* custom lens behavior */ },
///         isLensVisible: false
///     ))
/// ```
struct AddressBarContext {
    /// The web page to display navigation state for.
    let webPage: WebPage?

    /// The tab page to display URL from.
    let tabPage: TabPage?

    /// Action called when the address bar is tapped to open the lens.
    let onOpenLens: () -> Void

    /// Whether the lens is currently visible (controls AddressBar opacity).
    let isLensVisible: Bool

    /// Action called when find-in-page is requested.
    let onShowFindNavigator: () -> Void

    /// Creates an AddressBar context with custom behavior.
    ///
    /// - Parameters:
    ///   - webPage: The web page to display navigation state for.
    ///   - tabPage: The tab page to display URL from.
    ///   - onOpenLens: Action called when the address bar is tapped.
    ///   - isLensVisible: Whether the lens is currently visible.
    ///   - onShowFindNavigator: Action called when find-in-page is requested.
    init(
        webPage: WebPage?,
        tabPage: TabPage?,
        onOpenLens: @escaping () -> Void,
        isLensVisible: Bool,
        onShowFindNavigator: @escaping () -> Void,
    ) {
        self.webPage = webPage
        self.tabPage = tabPage
        self.onOpenLens = onOpenLens
        self.isLensVisible = isLensVisible
        self.onShowFindNavigator = onShowFindNavigator
    }
}
