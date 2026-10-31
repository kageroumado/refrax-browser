import SwiftUI

/// NSViewRepresentable hosting one pane's page in a ``CocoaWebViewAdapter``.
///
/// The page view keys each pane by its page, so the adapter lives as long as the page is a
/// pane of the tab, whichever cell it covers: a web view never moves between adapters while
/// panes trade places. The page is optional for the moment between a pane appearing and its
/// page being made, when the adapter shows nothing.
///
/// ## Dynamic Properties
///
/// Unlike WebView which applies static browser configurations, PaneWebViewAdapter
/// focuses on display mode management. Dynamic properties like `ignoresAllEvents`
/// are applied here since they change based on layout mode and overlay state.
struct PaneWebViewAdapter: NSViewRepresentable {
    /// The web page to display, or nil for an empty slot.
    let page: WebPage?

    /// Whether this adapter should be in active (interactive) mode.
    /// Only relevant when page is non-nil.
    let isActive: Bool

    /// Whether the adapter should display a GPU snapshot instead of live content.
    ///
    /// When true, the adapter captures the current content as a static snapshot
    /// and removes the WKWebView. This prevents WebKit from re-laying out content
    /// during layout mode animations.
    var isSnapshotMode: Bool = false

    /// Expected frame size hint for zero-bounds scenarios.
    let expectedFrame: CGRect

    /// The pane's corner radius, applied to the adapter's own layer with `masksToBounds`, so
    /// WebKit's remote layers and the snapshot are clipped by Core Animation rather than by
    /// a SwiftUI shape above them.
    var cornerRadius: CGFloat = 0

    /// Whether the webView should ignore all events.
    /// Used during layout mode and space lock.
    var ignoresAllEvents: Bool = false

    /// Callback when mouse down occurs in the webView.
    /// Used for focus tracking in multi-pane layouts.
    var onMouseDown: (() -> Void)?

    func makeNSView(context _: Context) -> CocoaWebViewAdapter {
        CocoaWebViewAdapter()
    }

    /// Whole points, rounded down: WebKit lays out and composites a fractional size with
    /// blurred edges, and a pane never grows past the space it was given.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView _: CocoaWebViewAdapter, context _: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width.rounded(.down), height: height.rounded(.down))
    }

    func updateNSView(_ adapter: CocoaWebViewAdapter, context: Context) {
        let coordinator = context.coordinator
        let environment = context.environment

        guard let page else {
            // No page - ensure adapter is inactive
            if coordinator.currentPageID != nil {
                adapter.setInactiveMode()
                coordinator.currentPageID = nil
            }
            return
        }

        let webView = page.backingWebView
        let pageChanged = coordinator.currentPageID != page.id

        if pageChanged {
            coordinator.currentPageID = page.id

            // Apply static browser configuration on page change.
            // These are typically the same for all browser tabs.
            applyStaticConfiguration(webView)
        }

        // Update display mode FIRST.
        // This must happen before applyDynamicProperties because:
        // 1. topContentInset's didSet calls applyTopContentInset()
        // 2. applyTopContentInset() checks `guard case let .active(webView) = displayMode`
        // 3. If we're not in active mode yet, the inset application is skipped!
        //
        // This matches WebView.updateNSView which also calls updateDisplayMode() before applyDynamicSettings().
        if page.isWebViewInVideoWindow {
            // The windowed-fullscreen video window hosts the web view; keep
            // the frozen snapshot rather than reclaiming it.
            if case .active = adapter.displayMode {
                adapter.setSnapshotMode(for: page)
            }
        } else if isSnapshotMode {
            // Snapshot mode: freeze current content as GPU snapshot for layout mode.
            // This prevents WebKit from re-laying out content at the tile size.
            switch adapter.displayMode {
            case let .snapshot(webPageID) where webPageID == page.id:
                break
            case let .active(current) where current === webView:
                adapter.setSnapshotMode(for: page)
            default:
                // Nothing of this page is rendered here yet (fresh adapter, or a pane
                // swap while frozen), so there is nothing to capture: show it live at
                // tile size instead.
                adapter.setActiveMode(
                    webView: webView,
                    expectedFrame: expectedFrame,
                    preferExpectedFrame: pageChanged,
                )
            }
        } else if isActive {
            // Leaving snapshot mode on the same page: bring the webView back with the
            // snapshot held as a cover until WebKit paints. A snapshot of a different
            // page (exit-layout-mode and tab-switch land in one update) must not cover
            // the incoming webView, so that case goes through setActiveMode.
            if case let .snapshot(webPageID) = adapter.displayMode, webPageID == page.id {
                adapter.exitSnapshotMode(webView: webView, expectedFrame: expectedFrame)
            } else {
                // When page changes (tab switch), prefer expectedFrame over stale adapter bounds.
                // This prevents the webView from briefly fitting into the old layout's size.
                adapter.setActiveMode(
                    webView: webView,
                    expectedFrame: expectedFrame,
                    preferExpectedFrame: pageChanged,
                )
            }
        } else {
            if let layer = webView.layer {
                adapter.setPortalMode(sourceLayer: layer)
            } else {
                adapter.setInactiveMode()
            }
        }

        adapter.setCornerRadius(cornerRadius)

        // Apply dynamic properties AFTER display mode is set.
        // This ensures the adapter is in active mode when topContentInset triggers applyTopContentInset().
        applyDynamicProperties(webView, adapter: adapter, environment: environment)
    }

    // MARK: - Configuration

    /// Applies static browser configuration on page change.
    ///
    /// These settings are typically the same for all browser tabs and don't
    /// change during normal usage. Applied once per page display.
    private func applyStaticConfiguration(_ webView: WebPageWebView) {
        // Navigation gestures - standard browser behavior
        if !webView.allowsBackForwardNavigationGestures {
            webView.allowsBackForwardNavigationGestures = true
        }

        // Link previews - standard browser behavior
        if webView.allowsLinkPreview {
            webView.allowsLinkPreview = false
        }

        // Text selection - standard browser behavior
        if !webView.configuration.preferences.isTextInteractionEnabled {
            webView.configuration.preferences.isTextInteractionEnabled = true
        }

        // Fullscreen - allow video fullscreen
        if !webView.configuration.preferences.isElementFullscreenEnabled {
            webView.configuration.preferences.isElementFullscreenEnabled = true
        }
    }

    /// Applies dynamic properties that change based on current state.
    private func applyDynamicProperties(_ webView: WebPageWebView, adapter: CocoaWebViewAdapter, environment: EnvironmentValues) {
        // While a plug-in engine renders the page, the paused WebKit view stays in
        // place underneath it and must not take hit tests meant for the engine's view.
        // Runs after the display-mode update, which unhides the web view on activation.
        let isEngineHosted = page?.enginePage != nil
        if webView.isHidden != isEngineHosted {
            webView.isHidden = isEngineHosted
        }

        // Event blocking - changes based on layout mode and space lock.
        if webView._ignoresAllEvents != ignoresAllEvents {
            webView._ignoresAllEvents = ignoresAllEvents
        }

        // Mouse down callback for focus tracking
        adapter.onMouseDown = onMouseDown

        // Find navigator from environment
        if let findContext = environment.webViewFindContext {
            adapter.findContext = findContext

            // Show/hide find bar based on the binding value.
            // Must go through NSTextFinder to ensure findBarView is created
            // before isFindBarVisible is set (NSTextFinderBarContainer protocol).
            let isVisible = adapter.isFindNavigatorVisible
            if let isPresented = findContext.isPresented?.wrappedValue {
                if isPresented, !isVisible {
                    DispatchQueue.main.async {
                        adapter.findInteraction?.performAction(.showFindInterface)
                    }
                } else if !isPresented, isVisible {
                    DispatchQueue.main.async {
                        adapter.findInteraction?.performAction(.hideFindInterface)
                    }
                }
            }
        }

        // Top content inset for toolbar areas.
        // IMPORTANT: This must be set BEFORE usesAutomaticContentInsetBackgroundFill for scroll
        // pocket creation to work correctly.
        adapter.topContentInset = environment.webViewTopContentInset

        // Automatic content inset background fill for scroll pocket system.
        // The value is derived from scroll edge context if set, otherwise the explicit setting.
        let usesAutomaticFill: Bool = if let scrollEdgeContext = environment.webViewScrollEdgeEffectStyleContext {
            scrollEdgeContext.style != .hard
        } else {
            environment.webViewUsesAutomaticContentInsetBackgroundFill
        }
        adapter.usesAutomaticContentInsetBackgroundFill = usesAutomaticFill
    }

    static func dismantleNSView(_ adapter: CocoaWebViewAdapter, coordinator: Coordinator) {
        adapter.prepareForDismantle()
        coordinator.cleanup()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    final class Coordinator {
        var currentPageID: WebPage.ID?

        func cleanup() {
            currentPageID = nil
        }
    }
}
