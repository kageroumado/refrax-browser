import SwiftUI
import WebKit

/// Container view for rendering web content with browser chrome integration.
///
/// Use `WebViewContainer` instead of `WebView` directly when displaying tab content.
/// This container provides:
///
/// - **Visibility tracking**: Signals ``WebPage`` for accurate time-spent metrics
/// - **Dialog handling**: JavaScript alerts, confirms, and file pickers
/// - **Browser behaviors**: Find-in-page, link previews, gestures, text selection
/// - **Deep link routing**: Renders native views for internal browser URLs
/// - **Multi-window support**: Automatic portal mode for non-owner windows
///
/// ## Usage
///
/// ```swift
/// WebViewContainer(page: webPage)
///     .environment(windowState)
/// ```
///
/// The container automatically notifies the page when content becomes visible
/// or hidden, enabling accurate browsing time tracking in history.
///
/// ## Multi-Window Behavior
///
/// When the same page is displayed in multiple windows, only one window (the "owner")
/// gets the interactive WebView. Other windows receive a read-only portal mirror.
/// Ownership transfers when a window becomes key while displaying the page.
struct WebViewContainer: View {
    /// The WebPage managing this web content.
    let page: WebPage

    @Environment(WindowState.self) private var windowState
    @Environment(HistoryManager.self) private var historyManager
    @Environment(HistoryActivityManager.self) private var historyActivityManager
    @Environment(ReaderModeManager.self) private var readerModeManager
    @Environment(\.webViewForcedInactive) private var isForcedInactive
    @Environment(\.webViewOwnershipID) private var customOwnershipID

    /// The URL currently being hovered over, displayed in the link preview overlay.
    @State private var hoveredLinkURL: URL?

    /// Leading padding for the link preview.
    /// Equals the default padding when no tray overlap, or the tray's trailing edge otherwise.
    @State private var linkPreviewLeadingOffset: CGFloat = Constants.linkPreviewPadding

    /// Cached trailing edge of the detail tray.
    /// Only updated when meaningful changes occur (> 1px), not on every animation frame.
    @State private var cachedTrayTrailingEdge: CGFloat = 0

    private enum Constants {
        static let linkPreviewPadding: CGFloat = 8
    }

    /// Stable identifier for this window, used for ownership tracking.
    ///
    /// Uses custom ownership ID if provided (for reflected windows that manage
    /// ownership via their controller), otherwise uses the WindowState's ID.
    private var windowID: ObjectIdentifier {
        customOwnershipID ?? ObjectIdentifier(windowState)
    }

    /// Whether a custom ownership ID is being used.
    private var usesCustomOwnershipID: Bool {
        customOwnershipID != nil
    }

    /// Whether reader mode is active for this page's tab.
    ///
    /// When reader mode is active, the main WKWebView's mouse events are blocked
    /// to prevent hover effects and cursor changes from bleeding through the overlay.
    private var isReaderActive: Bool {
        readerModeManager.isReaderActive(for: page.tabPage.id)
    }

    var body: some View {
        // Determine if this window should be the owner (have the active WebView).
        // Access ownerWindowID directly to ensure SwiftUI observes changes.
        // If forcedInactive is true, we never claim ownership.
        let ownerID = page.ownerWindowID
        let isCurrentOwner = ownerID == windowID
        let isWindowKey = windowState.window?.isKeyWindow ?? false
        let isOwner = !isForcedInactive && (isCurrentOwner || (ownerID == nil && isWindowKey))

        ZStack(alignment: .bottomLeading) {
            content(isOwner: isOwner)

            // Reader mode overlay - slides up from bottom when active
            ReaderOverlayContainer(tabID: page.tabPage.id)

            LinkHoverPreviewView(url: $hoveredLinkURL)
                .padding([.vertical, .trailing], Constants.linkPreviewPadding)
                .padding(.leading, linkPreviewLeadingOffset)
                .allowsHitTesting(false)

            // Modifier key hints overlay - shows when Option or Shift is held
            ModifierKeyHints()
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .background {
            // Invisible reader to track this container's position
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        cachedTrayTrailingEdge = windowState.detailTrayTrailingEdge
                        updateLinkPreviewOffset(containerMinX: geo.frame(in: .global).minX, animated: false)
                    }
                    .onChange(of: windowState.detailTrayTrailingEdge) { _, newValue in
                        // Only update when change is significant (> 1px) to avoid per-frame updates during animation
                        guard abs(cachedTrayTrailingEdge - newValue) > 1 else { return }
                        cachedTrayTrailingEdge = newValue
                        updateLinkPreviewOffset(containerMinX: geo.frame(in: .global).minX)
                    }
                    .onChange(of: windowState.sidebarOverlayTrailingEdge) { _, _ in
                        updateLinkPreviewOffset(containerMinX: geo.frame(in: .global).minX)
                    }
            }
        }
        .onAppear {
            // Claim ownership if we're the key window or no owner exists
            // Don't claim if forced inactive (e.g., docked view when separate window is open)
            if !isForcedInactive, !isCurrentOwner, page.ownerWindowID == nil || isWindowKey {
                claimOwnership()
            }

            // Skip history tracking for custom ownership ID (reflected windows).
            // The page is still tracked in its original tab location.
            if !usesCustomOwnershipID {
                // Register with activity manager for time tracking
                historyActivityManager.registerPage(page.tabPage.id, windowID: windowID)
                if isWindowKey {
                    historyActivityManager.updateWindowKey(windowID: windowID, isKey: true)
                }

                // Notify page of visibility (creates history entry if missing)
                page.onBecameVisible()
                page.webInspectorManager?.tabDidBecomeVisible(page.tabPage.id, webView: page.backingWebView)

                // Record interaction for address bar focus tracking
                windowState.recordInteraction(with: page.tabPage.id)
            }

            // Set up link hover callback only if we're the owner.
            // This prevents non-owner windows from overwriting the callback.
            if isOwner {
                setupLinkHoverCallback()
            }
        }
        .onDisappear {
            // Skip history tracking for custom ownership ID (reflected windows).
            if !usesCustomOwnershipID {
                page.webInspectorManager?.tabWillBecomeHidden(page.tabPage.id, webView: page.backingWebView)

                // Unregister from activity manager
                historyActivityManager.unregisterPage(page.tabPage.id, windowID: windowID)

                page.onBecameHidden()
            }

            // Don't release ownership if a reference pane window is open (when using WindowState).
            // The separate window shares the same WindowState, so releasing here
            // would clear ownership needed by the separate window's WebViewContainer.
            // For custom ownership IDs (reflected windows), always release.
            if usesCustomOwnershipID || !windowState.hasReferencePaneWindow {
                releaseOwnership()
            }

            // Clean up link hover callback only if we set it
            if page.ownerWindowID == nil || page.ownerWindowID == windowID {
                page.onHoveredLinkChanged = nil
            }
        }
        .task(id: page.tabPage.id) {
            // Skip periodic updates for custom ownership ID (reflected windows).
            // The page is still tracked in its original tab location.
            guard !usesCustomOwnershipID else { return }
            try? await periodicLastSeenUpdate()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            handleWindowBecameKey(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            handleWindowResignedKey(notification)
        }
    }

    /// Handles window becoming key - claims ownership if this is our window.
    ///
    /// This triggers a change to `page.ownerWindowID` which SwiftUI observes,
    /// causing both windows to re-evaluate their `isOwner` state. Also updates
    /// the activity manager so time tracking gating is accurate.
    private func handleWindowBecameKey(_ notification: Notification) {
        // When using a custom ownership ID (reflected windows), the controller
        // manages key-window ownership swaps via its own windowDidBecomeKey.
        // We must NOT respond here because windowState.window points to the MAIN
        // window — so this handler would fire when the main window becomes key,
        // incorrectly re-stealing ownership back to the reflected window.
        guard !usesCustomOwnershipID else { return }

        guard !isForcedInactive,
              let keyWindow = notification.object as? NSWindow,
              keyWindow === windowState.window else {
            return
        }
        claimOwnership()
        windowState.recordInteraction(with: page.tabPage.id)

        // Update activity manager with key window state
        historyActivityManager.updateWindowKey(windowID: windowID, isKey: true)

        // Take over link hover callback now that we're the owner
        setupLinkHoverCallback()
    }

    /// Handles window resigning key - updates activity manager for time tracking gating.
    private func handleWindowResignedKey(_ notification: Notification) {
        // Skip for reflected windows — controller manages its own lifecycle.
        guard !usesCustomOwnershipID else { return }

        guard let resignedWindow = notification.object as? NSWindow,
              resignedWindow === windowState.window else {
            return
        }
        historyActivityManager.updateWindowKey(windowID: windowID, isKey: false)
    }

    // MARK: - Ownership Helpers

    /// Claims ownership of the WebPage for this window.
    ///
    /// For custom ownership IDs (reflected windows), uses the custom ID.
    /// Otherwise uses the WindowState's ID.
    private func claimOwnership() {
        if let customID = customOwnershipID {
            page.claimOwnership(id: customID)
        } else {
            page.claimOwnership(for: windowState)
        }
    }

    /// Releases ownership of the WebPage.
    ///
    /// For custom ownership IDs, releases using the custom ID.
    /// Otherwise releases using the WindowState's ID.
    private func releaseOwnership() {
        if let customID = customOwnershipID {
            page.releaseOwnership(id: customID)
        } else {
            page.releaseOwnership(for: windowState)
        }
    }

    /// Sets up the link hover callback for this window.
    ///
    /// Only updates `hoveredLinkURL` if this window is still the owner,
    /// preventing stale callbacks from overwriting the current owner's state.
    private func setupLinkHoverCallback() {
        page.onHoveredLinkChanged = { [weak windowState] url in
            guard let windowState else { return }
            if page.ownerWindowID == ObjectIdentifier(windowState) {
                hoveredLinkURL = url
            }
        }
    }

    /// Updates the link preview leading padding based on container position and overlay state.
    ///
    /// If the container's leading edge is covered by the sidebar overlay or detail tray,
    /// positions the preview just past the obstruction's trailing edge.
    private func updateLinkPreviewOffset(containerMinX: CGFloat, animated: Bool = true) {
        // Use the greater of sidebar overlay and detail tray trailing edges.
        // When the tray is visible, it's already positioned past the sidebar overlay,
        // so max() naturally picks the outermost obstruction.
        let obstruction = max(windowState.sidebarOverlayTrailingEdge, cachedTrayTrailingEdge)

        let newOffset: CGFloat = if obstruction > 0, containerMinX < obstruction {
            obstruction - containerMinX + Constants.linkPreviewPadding
        } else {
            Constants.linkPreviewPadding
        }

        withAnimation(animated ? .easeOut(duration: 0.25) : nil) {
            linkPreviewLeadingOffset = newOffset
        }
    }

    /// Periodically updates history tracking while the page is visible.
    ///
    /// Runs while the view is visible, performing two functions:
    /// - Every 5 seconds: Updates `lastSeenAt` for crash recovery
    /// - Every 15 seconds: Adds incremental time-spent for granular tracking
    ///
    /// Both operations are gated on `historyActivityManager.canTrackTime` to ensure
    /// time is only tracked when the app is active and the system is not sleeping.
    private func periodicLastSeenUpdate() async throws {
        var ticksSinceTimeUpdate = 0
        while true {
            try await Task.sleep(for: .seconds(5))

            // Only update when actively tracking time
            guard historyActivityManager.isPageActive(page.tabPage.id) else {
                ticksSinceTimeUpdate = 0
                continue
            }

            // Update lastSeenAt every 5 seconds for crash recovery
            historyManager.updateLastSeen(for: page.tabPage.id)

            // Add time-spent every 15 seconds (3 ticks) for granular tracking
            ticksSinceTimeUpdate += 1
            if ticksSinceTimeUpdate >= 3 {
                historyManager.addTimeSpent(for: page.tabPage.id, duration: 15)
                ticksSinceTimeUpdate = 0
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(isOwner: Bool) -> some View {
        if let crashError = page.crashError {
            CrashPageView(page: page, crashError: crashError)
        } else if let errorCode = page.httpErrorCode, let failedURL = page.httpErrorURL {
            ErrorPageView(page: page, statusCode: errorCode, failedURL: failedURL)
        } else if let url = page.deepLinkURL, let deepLink = DeepLink(url: url) {
            // Show deep link view for internal browser pages (SSL errors, etc.)
            DeepLinkView(deepLink: deepLink)
        } else {
            configuredWebView(isOwner: isOwner)
        }
    }

    /// WebView with browser behaviors and dialog handling attached.
    private func configuredWebView(isOwner: Bool) -> some View {
        let shouldIgnore = windowState.webViewsShouldIgnoreAllEvents
            || windowState.isInLayoutMode
            || windowState.isSpaceLocked
            || isReaderActive
        
        return WebView(page)
            .webViewIsActive(isOwner)
            .webViewOnMouseDown {
                windowState.recordInteraction(with: page.tabPage.id)
            }
            .webViewIgnoresAllEvents(shouldIgnore)
            .modifier(BrowserBehaviorsModifier(
                findNavigatorPresented: windowState[findNavigatorFor: page.id],
            ))
            .modifier(FocusBlurModifier(page: page))
            .modifier(TimeLimitModifier(page: page))
    }
}
