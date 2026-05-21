import SwiftUI

// MARK: - View Modifiers

extension View {
    /// Determines whether horizontal swipe gestures trigger backward and forward page navigation.
    ///
    /// When enabled, horizontal swipe gestures trigger back and forward
    /// page navigation in the web view.
    ///
    /// - Parameter value: The gesture behavior to apply.
    /// - Returns: A view with the modified behavior.
    ///
    /// ## Example
    ///
    /// ```swift
    /// WebView(page)
    ///     .webViewBackForwardNavigationGestures(.enabled)
    /// ```
    func webViewBackForwardNavigationGestures(
        _ value: WebView.BackForwardNavigationGesturesBehavior,
    ) -> some View {
        environment(\.webViewAllowsBackForwardNavigationGestures, value)
    }

    /// Determines whether pressing a link displays a preview of the destination for the link.
    ///
    /// When enabled, pressing and holding on a link shows a preview
    /// of the linked content.
    ///
    /// - Parameter value: The link preview behavior to apply.
    /// - Returns: A view with the modified behavior.
    ///
    /// ## Example
    ///
    /// ```swift
    /// WebView(page)
    ///     .webViewLinkPreviews(.enabled)
    /// ```
    func webViewLinkPreviews(
        _ value: WebView.LinkPreviewBehavior,
    ) -> some View {
        environment(\.webViewAllowsLinkPreview, value)
    }

    /// Determines whether magnify gestures change the view's magnification.
    ///
    /// When enabled, pinch gestures change the web view's magnification level.
    ///
    /// - Parameter value: The magnification behavior to apply.
    /// - Returns: A view with the modified behavior.
    ///
    /// ## Example
    ///
    /// ```swift
    /// WebView(page)
    ///     .webViewMagnificationGestures(.enabled)
    /// ```
    func webViewMagnificationGestures(
        _ value: WebView.MagnificationGesturesBehavior,
    ) -> some View {
        environment(\.webViewMagnificationGestures, value)
    }

    /// Specifies the visibility of the webpage's natural background color within this view.
    ///
    /// By default, WebViews are opaque, and use the page's natural background color as their
    /// background color. Use this modifier if you would like to not use this behavior and
    /// instead provide a custom background using SwiftUI.
    ///
    /// - Parameter visibility: The visibility to use for the background.
    /// - Returns: A view with the specified content background visibility.
    ///
    /// ## Example
    ///
    /// ```swift
    /// WebView(page)
    ///     .webViewContentBackground(.hidden)
    /// ```
    func webViewContentBackground(
        _ visibility: Visibility,
    ) -> some View {
        environment(\.webViewContentBackground, visibility)
    }

    /// Sets the scroll edge effect style for web views.
    ///
    /// - Parameters:
    ///   - style: The scroll edge effect style to apply.
    ///   - edges: The edges to apply the style to.
    /// - Returns: A view with the modified style.
    ///
    /// ## Example
    ///
    /// ```swift
    /// WebView(page)
    ///     .webViewScrollEdgeEffectStyle(.soft, for: .all)
    /// ```
    func webViewScrollEdgeEffectStyle(
        _ style: ScrollEdgeEffectStyle?,
        for edges: Edge.Set,
    ) -> some View {
        ignoresSafeArea(edges: edges)
            .environment(\.webViewScrollEdgeEffectStyleContext, .init(style: style, edges: edges))
    }

    /// Determines whether to allow people to select or otherwise interact with text.
    ///
    /// When enabled, users can select and copy text from web content.
    ///
    /// - Parameter selectability: The text selectability setting.
    /// - Returns: A view with the modified setting.
    ///
    /// ## Example
    ///
    /// ```swift
    /// WebView(page)
    ///     .webViewTextSelection(.enabled)
    /// ```
    func webViewTextSelection<S: TextSelectability>(_: S) -> some View {
        environment(\.webViewTextSelection, S.allowsSelection)
    }

    /// Determines whether a web view can display content full screen.
    ///
    /// When enabled, elements like videos can enter fullscreen mode.
    ///
    /// - Parameter value: The fullscreen behavior to apply.
    /// - Returns: A view with the modified behavior.
    ///
    /// ## Example
    ///
    /// ```swift
    /// WebView(page)
    ///     .webViewElementFullscreenBehavior(.enabled)
    /// ```
    func webViewElementFullscreenBehavior(
        _ value: WebView.ElementFullscreenBehavior,
    ) -> some View {
        environment(\.webViewElementFullscreenBehavior, value)
    }

    /// Controls the find navigator presentation for web views.
    ///
    /// - Parameter isPresented: Binding controlling visibility.
    /// - Returns: A view with find navigator support.
    ///
    /// ## Example
    ///
    /// ```swift
    /// @State private var showingFind = false
    ///
    /// WebView(page)
    ///     .webViewFindNavigator(isPresented: $showingFind)
    /// ```
    func webViewFindNavigator(isPresented: Binding<Bool>) -> some View {
        environment(\.webViewFindContext, FindContext(isPresented: isPresented))
    }

    /// Scroll position control is not implemented in Refrax.
    ///
    /// This API is intentionally unavailable because:
    /// - SwiftUI's `ScrollPosition` lacks the edge detection needed for web content
    /// - Browser scroll state is managed by WebKit internally
    /// - Programmatic scrolling should use `WebPage.scrollTo(edge:)` or JavaScript
    ///
    /// For scroll position needs:
    /// - To scroll to top/bottom: Use `WebPage.backingWebView.scrollTo(edge:animated:)`
    /// - To observe scroll position: Implement `WebPageWebView.Delegate.geometryDidChange(_:)`
    @available(*, unavailable, message: "Scroll position control is not implemented. Use WebPage.backingWebView.scrollTo(edge:animated:) for programmatic scrolling.")
    func webViewScrollPosition(_: Binding<ScrollPosition>) -> some View {
        self
    }

    // MARK: - Unavailable Modifiers

    /// Scroll geometry observation is not implemented in Refrax.
    ///
    /// Use `WebPageWebView.Delegate.geometryDidChange(_:)` directly for scroll tracking.
    /// See `WebViewEnvironment.swift` for details on why this is unavailable.
    @available(*, unavailable, message: "Scroll geometry observation is handled via WebPageWebView.Delegate for browser performance")
    func webViewOnScrollGeometryChange<T: Hashable & Sendable>(
        for _: T.Type,
        of _: @escaping @Sendable (ScrollGeometry) -> T,
        action _: @escaping @Sendable (T, T) -> Void,
    ) -> some View {
        self
    }

    /// Scroll input behavior is not implemented in Refrax (visionOS feature).
    ///
    /// See `WebViewEnvironment.swift` for details on why this is unavailable.
    @available(*, unavailable, message: "Scroll input behavior is a visionOS feature not applicable to macOS")
    func webViewScrollInputBehavior(_: ScrollInputBehavior, for _: ScrollInputKind) -> some View {
        self
    }

    #if os(macOS)
        /// Context menu building via SwiftUI environment is not implemented in Refrax.
        ///
        /// Use `WKUIDelegateAdapter.menuBuilder` instead for browser context menus.
        /// See `WebViewEnvironment.swift` for details on why this is unavailable.
        @available(*, unavailable, message: "Use WKUIDelegateAdapter.menuBuilder for browser context menus")
        func webViewContextMenu(
            @ViewBuilder menu _: @MainActor @escaping (WebView.ActivatedElementInfo) -> some View,
        ) -> some View {
            self
        }
    #endif

    /// Sets whether the web view is active (interactive) or in portal mode.
    ///
    /// In active mode, the web view receives user input. In inactive mode,
    /// a `CAPortalLayer` mirrors the content read-only.
    ///
    /// - Parameter isActive: Whether the web view should be interactive.
    /// - Returns: A view with the modified active state.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Active - receives input
    /// WebView(page)
    ///     .webViewIsActive(true)
    ///
    /// // Inactive - read-only mirror
    /// WebView(page)
    ///     .webViewIsActive(false)
    /// ```
    func webViewIsActive(_ isActive: Bool) -> some View {
        environment(\.webViewIsActive, isActive)
    }

    /// Blocks all pointer interactions with the WebView.
    ///
    /// This modifier uses WebKit's `_ignoresMouseMoveEvents` property to block
    /// interaction at the WKWebView level.
    ///
    /// - Parameter isBlocked: When `true`, all mouse events are ignored.
    /// - Returns: A view with conditional web interaction blocking.
    func webViewIgnoresMouseMoveEvents(_ isBlocked: Bool) -> some View {
        environment(\.webViewIgnoresMouseMoveEvents, isBlocked)
    }

    /// Blocks all WebView interactions.
    ///
    /// This modifier uses WebKit's `_ignoresAllEvents` property to block
    /// interaction at the WKWebView level.
    ///
    /// - Parameter isBlocked: When `true`, all user events are ignored.
    /// - Returns: A view with conditional web interaction blocking.
    func webViewIgnoresAllEvents(_ isBlocked: Bool) -> some View {
        environment(\.webViewIgnoresAllEvents, isBlocked)
    }

    /// Sets a callback to be invoked when the user clicks on the web view.
    ///
    /// This is used for focus tracking - the callback is called before the click
    /// event is passed to the web view, allowing the browser to track which view
    /// last received user interaction.
    ///
    /// - Parameter action: The action to perform when a mouse down event occurs.
    /// - Returns: A view with the mouse down callback configured.
    ///
    /// ## Example
    ///
    /// ```swift
    /// WebView(page)
    ///     .webViewOnMouseDown {
    ///         windowState.recordInteraction(with: page.tabPage.id)
    ///     }
    /// ```
    func webViewOnMouseDown(_ action: (() -> Void)?) -> some View {
        environment(\.webViewOnMouseDown, action)
    }

    /// Sets the top content inset for the web view.
    ///
    /// When set, the web content is pushed down by this amount, creating space
    /// for a toolbar or other UI elements that overlay the web view. The web
    /// content will scroll behind the inset area.
    ///
    /// This uses WebKit's `_topContentInset` API to properly inset the rendering area.
    ///
    /// - Parameter inset: The inset value in points.
    /// - Returns: A view with the top content inset configured.
    ///
    /// ## Example
    ///
    /// ```swift
    /// WebView(page)
    ///     .webViewTopContentInset(52) // Height of toolbar
    /// ```
    func webViewTopContentInset(_ inset: CGFloat) -> some View {
        environment(\.webViewTopContentInset, inset)
    }

    /// Forces web views to be inactive regardless of ownership state.
    ///
    /// When `true`, any `WebViewContainer` in this view hierarchy will not claim the WebView,
    /// allowing another window to take ownership. This is used when transitioning between
    /// docked and separate window modes for reference panes.
    ///
    /// - Parameter isInactive: Whether to force web views to be inactive.
    /// - Returns: A view with the forced inactive state configured.
    func webViewForcedInactive(_ isInactive: Bool = true) -> some View {
        environment(\.webViewForcedInactive, isInactive)
    }

    /// Sets a custom ownership ID for multi-window scenarios.
    ///
    /// When set, `WebViewContainer` uses this ID for ownership comparisons instead of
    /// `ObjectIdentifier(windowState)`. This enables windows like `ReflectedViewController`
    /// that manage ownership via their own controller identity to use `WebViewContainer`.
    ///
    /// - Parameter id: The ownership ID to use for this view hierarchy.
    /// - Returns: A view with the custom ownership ID configured.
    func webViewOwnershipID(_ id: ObjectIdentifier) -> some View {
        environment(\.webViewOwnershipID, id)
    }

    /// Controls whether WebKit should automatically adjust content insets.
    ///
    /// When `true` (default), WebKit monitors window position and titlebar adjacency
    /// to automatically compute content insets. When `false`, WebKit won't override
    /// manually set content insets during window operations.
    ///
    /// - Parameter enabled: Whether automatic content inset adjustment is enabled.
    /// - Returns: A view with the automatic content inset adjustment configured.
    func webViewAutomaticallyAdjustsContentInsets(_ enabled: Bool) -> some View {
        environment(\.webViewAutomaticallyAdjustsContentInsets, enabled)
    }

    /// Enables the automatic content inset background fill system for scroll pocket.
    ///
    /// When enabled, WebKit uses the NSScrollPocket system (macOS 26+) which:
    /// - Renders scroll pocket with `NSScrollPocketStyleAutomatic`
    /// - Automatically samples and adapts colors from page content
    /// - Enables sticky header detection via `prefersSolidColorHardScrollPocket`
    ///
    /// ## Prerequisites
    /// For the scroll pocket to be created, also set:
    /// - `webViewTopContentInset(_ inset:)` to a value > 0
    ///
    /// - Parameter enabled: Whether automatic content inset background fill is enabled.
    /// - Returns: A view with automatic content inset background fill configured.
    func webViewUsesAutomaticContentInsetBackgroundFill(_ enabled: Bool) -> some View {
        environment(\.webViewUsesAutomaticContentInsetBackgroundFill, enabled)
    }
}

// MARK: - Performance Optimization Modifiers

extension View {
    /// Locks web view configuration settings after initial application.
    ///
    /// When applied, settings like `allowsBackForwardNavigationGestures`, `allowsLinkPreview`,
    /// `allowsMagnification`, etc. are applied once and subsequent SwiftUI updates skip them.
    /// This significantly improves performance during rapid tab switching.
    ///
    /// - Parameter locked: Whether to lock configuration. Defaults to `true`.
    /// - Returns: A view with locked configuration.
    ///
    /// ## Usage
    ///
    /// Apply this modifier **after** all other web view configuration modifiers:
    ///
    /// ```swift
    /// WebView(page)
    ///     .webViewBackForwardNavigationGestures(.enabled)
    ///     .webViewLinkPreviews(.enabled)
    ///     .webViewMagnificationGestures(.enabled)
    ///     .webViewConfigurationLocked()  // Lock after setting all options
    /// ```
    ///
    /// ## Performance Impact
    ///
    /// - **Tab switching**: Eliminates redundant WKWebView property updates
    /// - **Split view resizing**: Reduces SwiftUI update overhead
    /// - **Multi-window**: Portal mode transitions become faster
    ///
    /// ## How It Works
    ///
    /// Without locking, every SwiftUI update cycle checks and potentially sets:
    /// - `allowsBackForwardNavigationGestures`
    /// - `allowsLinkPreview`
    /// - `allowsMagnification`
    /// - `_drawsBackground`
    /// - `preferences.isTextInteractionEnabled`
    /// - `preferences.isElementFullscreenEnabled`
    /// - Scroll bounce behaviors
    ///
    /// With locking enabled, these are set once on first render and cached.
    /// Subsequent SwiftUI updates only handle display mode (active/portal) and
    /// dynamic properties (find navigator, scroll position).
    ///
    /// ## When to Use
    ///
    /// Use this modifier when:
    /// - Web view configuration doesn't change at runtime
    /// - Performance during tab switching is important
    /// - The browser has a single configuration for all tabs
    ///
    /// Do NOT use if:
    /// - Configuration needs to change dynamically per-page
    /// - Different tabs require different settings
    ///
    /// - Note: Dynamic properties (find navigator, scroll position, interaction blocking)
    ///   are always applied regardless of locking.
    func webViewConfigurationLocked(_ locked: Bool = true) -> some View {
        environment(\.webViewConfigurationLocked, locked)
    }
}

// MARK: - Browser Behaviors Convenience

extension View {
    /// Applies standard browser behaviors to a web view with configuration locking.
    ///
    /// This is a convenience modifier that applies common browser settings:
    /// - Back/forward navigation gestures
    /// - Link previews
    /// - Text selection
    /// - Element fullscreen
    /// - **Configuration locking for performance**
    ///
    /// - Returns: A view with browser behaviors applied and locked.
    ///
    /// ## Example
    ///
    /// ```swift
    /// WebView(page)
    ///     .browserBehaviors()
    /// ```
    ///
    /// This is equivalent to:
    ///
    /// ```swift
    /// WebView(page)
    ///     .webViewBackForwardNavigationGestures(.enabled)
    ///     .webViewLinkPreviews(.enabled)
    ///     .webViewConfigurationLocked()
    /// ```
    func browserBehaviors() -> some View {
        webViewBackForwardNavigationGestures(.enabled)
            .webViewLinkPreviews(.enabled)
            .webViewConfigurationLocked()
    }
}
