import SwiftUI

/// NSViewRepresentable that maintains a stable adapter at a fixed position.
///
/// Unlike `WebViewRepresentable` which requires a `WebPage`, this view accepts
/// an optional page. When page is nil, the adapter exists but shows nothing.
/// This enables a constant view structure (always 4 positions) so SwiftUI
/// never recreates adapters during tab switches or mode transitions.
///
/// ## Architecture
///
/// The key insight is that SwiftUI view identity determines adapter lifecycle.
/// By always having 4 views with position-based IDs, the structure never changes:
/// - Single-pane: .topLeft has content, others are empty (zero size)
/// - Multi-pane: Populated positions have content, empty ones have zero size
/// - Layout mode: All 4 positions visible for editing
///
/// The adapters persist across all transitions. Only the webViews move between them.
///
/// ## Dynamic Properties
///
/// Unlike WebView which applies static browser configurations, PositionedAdapter
/// focuses on display mode management. Dynamic properties like `ignoresAllEvents`
/// are applied here since they change based on layout mode and overlay state.
struct PositionedAdapter: NSViewRepresentable {
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

    /// Whether the webView should ignore all events.
    /// Used during layout mode, space lock, reader mode, etc.
    var ignoresAllEvents: Bool = false

    /// Callback when mouse down occurs in the webView.
    /// Used for focus tracking in multi-pane layouts.
    var onMouseDown: (() -> Void)?

    func makeNSView(context _: Context) -> CocoaWebViewAdapter {
        let adapter = CocoaWebViewAdapter()
        return adapter
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
        if isSnapshotMode {
            // Snapshot mode: freeze current content as GPU snapshot for layout mode.
            // This prevents WebKit from re-laying out content at the tile size.
            if case .snapshot = adapter.displayMode {
                // Already in snapshot mode — nothing to do.
                // Match on .snapshot without checking webPageID to avoid spurious
                // fallthrough from transient SwiftUI re-evaluations where the
                // page object might differ briefly.
            } else if case .active = adapter.displayMode {
                // Was active — capture snapshot and switch
                adapter.setSnapshotMode(for: page)
            } else {
                // Adapter not active (just created or was inactive) — set active normally.
                // Can't snapshot what isn't rendered yet. This path is hit when SwiftUI
                // recreates the adapter during layout mode entry.
                adapter.setActiveMode(
                    webView: webView,
                    expectedFrame: expectedFrame,
                    preferExpectedFrame: pageChanged,
                )
            }
        } else if isActive {
            // If we were in snapshot mode, transition back to active with the snapshot
            // held as a cover until WebKit paints the new content.
            if case .snapshot = adapter.displayMode {
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
        // Event blocking - changes based on layout mode, reader, etc.
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
