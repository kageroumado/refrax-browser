import Security
import SecurityInterface
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Pane Content Wrapper

/// One pane of a tab's page: its ``PaneWebViewAdapter`` with the browser chrome a page needs:
/// dialogs, overlays, link previews, visibility tracking, and modifier key hints.
///
/// The page view keys each pane by its tab page, so the wrapper lives as long as the page is
/// a pane of the shown tab. The adapter hosts the page's web view; this wrapper adds the
/// SwiftUI overlays and modifiers that need page context, and drives the page's lifecycle
/// (ownership, visibility, history) while its web page exists.
struct PaneContentWrapper: View {
    let tabPage: TabPage
    let webPage: WebPage?
    let frame: CGRect
    /// The pane's corners, clipped by the adapter's own layer so WebKit's layers round too.
    let cornerRadius: CGFloat
    let isLayoutMode: Bool
    /// A click landed in the pane.
    let onActivate: () -> Void

    @Environment(DialogState.self) private var dialogState
    @Environment(WindowState.self) private var windowState
    @Environment(HistoryManager.self) private var historyManager
    @Environment(HistoryActivityManager.self) private var historyActivityManager

    private enum Constants {
        static let linkPreviewPadding: CGFloat = 8
    }

    /// The URL currently being hovered over.
    @State private var hoveredLinkURL: URL?

    /// Leading padding for the link preview.
    /// Equals the default padding when no tray overlap, or the tray's trailing edge otherwise.
    @State private var linkPreviewLeadingOffset: CGFloat = Constants.linkPreviewPadding

    /// Cached trailing edge of the detail tray.
    /// Only updated when meaningful changes occur (> 1px), not on every animation frame.
    @State private var cachedTrayTrailingEdge: CGFloat = 0

    /// The page whose lifecycle this wrapper currently drives, and its tab page.
    ///
    /// The web page under one tab page can change while the pane stays (made after the pane
    /// appeared, or replaced across an extension's pages) without any `onDisappear`/`onAppear`;
    /// the outgoing page is remembered here so it can be hidden and released when the next
    /// one arrives.
    @State private var lifecyclePage: WebPage?
    @State private var lifecycleTabPageID: UUID?

    private var hasContent: Bool {
        frame.width > 0 && frame.height > 0
    }

    /// Stable identifier for this window.
    private var windowID: ObjectIdentifier {
        ObjectIdentifier(windowState)
    }

    /// Whether the webView should ignore all events.
    ///
    /// Events are blocked during layout mode, space lock, or when globally disabled.
    private var shouldIgnoreAllEvents: Bool {
        windowState.webViewsShouldIgnoreAllEvents
            || isLayoutMode
            || windowState.isSpaceLocked
    }

    var body: some View {
        // Determine if this window should be the owner (have the active WebView).
        // Access ownerWindowID directly to ensure SwiftUI observes changes.
        // If forcedInactive is true, we never claim ownership.
        let ownerID = webPage?.ownerWindowID
        let isCurrentOwner = ownerID == windowID
        // When ownerID is nil, we should be active - we'll claim ownership via onChange.
        // This prevents the "empty frame" gap when another window releases ownership.
        let isOwner = isCurrentOwner || ownerID == nil

        ZStack(alignment: .bottomLeading) {
            // The adapter - always rendered for position stability
            // isOwner determines active vs portal mode for multi-window coordination
            PaneWebViewAdapter(
                page: webPage,
                isActive: isOwner,
                isSnapshotMode: isLayoutMode && isOwner,
                expectedFrame: frame,
                cornerRadius: cornerRadius,
                ignoresAllEvents: shouldIgnoreAllEvents,
                onMouseDown: onActivate,
            )
            .webViewFindNavigator(isPresented: findNavigatorBinding)

            // A plug-in engine renders over the paused WebKit view it replaces.
            if hasContent, isOwner, let enginePage = webPage?.enginePage {
                EngineContentView(page: enginePage, owner: webPage)
                    .allowsHitTesting(!shouldIgnoreAllEvents)
            }

            // Overlays only when we have content and not in layout mode
            if hasContent, !isLayoutMode, let webPage {
                overlays(for: webPage, tabPage: tabPage)
            }
        }
        .background {
            // Invisible reader to track this container's position for link preview offset
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
            }
        }
        .modifier(DialogModifiers(dialogState: dialogState))
        .modifier(PageOverlayModifiers(webPage: webPage, hasContent: hasContent, isLayoutMode: isLayoutMode))
        .onAppear {
            beginLifecycle()
            cachedTrayTrailingEdge = windowState.detailTrayTrailingEdge
        }
        .onDisappear { endLifecycle() }
        .onChange(of: webPage?.id) { oldValue, newValue in
            // A page replaced under the same tab page, or made after the pane appeared,
            // arrives here rather than as onDisappear/onAppear: the outgoing page is hidden
            // and released, the incoming one claimed and shown.
            guard oldValue != newValue else { return }
            hoveredLinkURL = nil
            endLifecycle()
            beginLifecycle()
        }
        .task(id: tabPage.id) {
            try? await periodicLastSeenUpdate()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            handleWindowBecameKey(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            handleWindowResignedKey(notification)
        }
        .onChange(of: webPage?.ownerWindowID) { oldValue, newValue in
            // When ownership is released (becomes nil), immediately claim it.
            // This prevents the visual gap when another window closes and releases ownership.
            guard let webPage, newValue == nil, oldValue != nil else { return }
            webPage.claimOwnership(for: windowState)
        }
    }

    /// Binding for find navigator presentation.
    private var findNavigatorBinding: Binding<Bool> {
        guard let webPage else {
            return .constant(false)
        }
        return windowState[findNavigatorFor: webPage.id]
    }

    // MARK: - Overlays

    @ViewBuilder
    private func overlays(for page: WebPage, tabPage: TabPage) -> some View {
        // Crash error page (process terminated, auto-recovery suppressed)
        if let crashError = page.crashError {
            CrashPageView(page: page, crashError: crashError)
        }

        // A page Shields blocked from opening
        if let blockedURL = page.shieldsBlockedURL {
            ShieldsBlockedPageView(page: page, url: blockedURL)
        }

        // HTTP error page overlay (4xx, 5xx, and network error codes)
        if let errorCode = page.httpErrorCode, let failedURL = page.httpErrorURL {
            ErrorPageView(page: page, statusCode: errorCode, failedURL: failedURL)
        }

        // Deep link view for internal browser URLs
        if tabPage.url.isDeepLink, let deepLink = DeepLink(url: tabPage.url) {
            DeepLinkView(deepLink: deepLink)
        }

        // Link hover preview
        LinkHoverPreviewView(url: $hoveredLinkURL)
            .padding([.vertical, .trailing], Constants.linkPreviewPadding)
            .padding(.leading, linkPreviewLeadingOffset)
            .allowsHitTesting(false)

        // Modifier key hints (Option/Shift)
        ModifierKeyHints()
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Lifecycle

    /// Takes the current page for this window: ownership, activity registration,
    /// visibility, and the link-hover callback.
    private func beginLifecycle() {
        guard let webPage else { return }
        let isWindowKey = windowState.window?.isKeyWindow ?? false
        let ownerID = webPage.ownerWindowID

        // Claim when nobody owns the page, when this is the key window, or when no
        // window of ours is key (the app is in the background). Leaving a stale owner
        // in place puts the adapter into portal mode over a layer that is attached
        // nowhere, which renders as a blank pane.
        if ownerID != windowID, ownerID == nil || isWindowKey || NSApp.keyWindow == nil {
            webPage.claimOwnership(for: windowState)
        }

        historyActivityManager.registerPage(tabPage.id, windowID: windowID)
        if isWindowKey {
            historyActivityManager.updateWindowKey(windowID: windowID, isKey: true)
        }

        // Creates the history entry if missing and starts time tracking.
        webPage.onBecameVisible()
        webPage.inspectorPageDidBecomeVisible()

        focusIfActive(on: .appeared)

        // Only the owner installs the hover callback, so other windows never overwrite it.
        if webPage.ownerWindowID == windowID {
            setupLinkHoverCallback(for: webPage)
        }

        lifecyclePage = webPage
        lifecycleTabPageID = tabPage.id
    }

    /// Releases the page taken by `beginLifecycle()`.
    private func endLifecycle() {
        guard let page = lifecyclePage, let tabPageID = lifecycleTabPageID else { return }
        lifecyclePage = nil
        lifecycleTabPageID = nil

        page.inspectorPageWillBecomeHidden()
        historyActivityManager.unregisterPage(tabPageID, windowID: windowID)
        page.onBecameHidden()

        page.releaseOwnership(for: windowState)

        // Clean up link hover callback only if we set it
        if page.ownerWindowID == nil || page.ownerWindowID == windowID {
            page.onHoveredLinkChanged = nil
        }

        hoveredLinkURL = nil
    }

    private func handleWindowBecameKey(_ notification: Notification) {
        guard let webPage,
              let keyWindow = notification.object as? NSWindow,
              keyWindow === windowState.window else {
            return
        }

        // Claim ownership when our window becomes key
        webPage.claimOwnership(for: windowState)

        focusIfActive(on: .windowBecameKey)
        historyActivityManager.updateWindowKey(windowID: windowID, isKey: true)

        // Take over link hover callback now that we're the owner
        setupLinkHoverCallback(for: webPage)
    }

    /// Focuses this pane when ``PaneFocus`` says `event` gives it focus.
    private func focusIfActive(on event: PaneFocus.Event) {
        if PaneFocus.takesFocus(on: event, pageID: tabPage.id, activePageID: tabPage.tab?.activePage.id) {
            windowState.recordInteraction(with: tabPage.id)
        }
    }

    private func handleWindowResignedKey(_ notification: Notification) {
        guard let resignedWindow = notification.object as? NSWindow,
              resignedWindow === windowState.window else {
            return
        }
        historyActivityManager.updateWindowKey(windowID: windowID, isKey: false)
    }

    private func setupLinkHoverCallback(for page: WebPage) {
        page.onHoveredLinkChanged = { [weak windowState] url in
            guard let windowState else { return }
            if page.ownerWindowID == ObjectIdentifier(windowState) {
                hoveredLinkURL = url
            }
        }
    }

    /// Updates the link preview leading padding based on container position and overlay state.
    ///
    /// If the container's leading edge is covered by the detail tray,
    /// positions the preview just past the tray's trailing edge.
    private func updateLinkPreviewOffset(containerMinX: CGFloat, animated: Bool = true) {
        let obstruction = cachedTrayTrailingEdge

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
    private func periodicLastSeenUpdate() async throws {
        var ticksSinceTimeUpdate = 0
        while true {
            try await Task.sleep(for: .seconds(5))

            guard historyActivityManager.isPageActive(tabPage.id) else {
                ticksSinceTimeUpdate = 0
                continue
            }

            historyManager.updateLastSeen(for: tabPage.id)

            ticksSinceTimeUpdate += 1
            if ticksSinceTimeUpdate >= 3 {
                historyManager.addTimeSpent(for: tabPage.id, duration: 15)
                ticksSinceTimeUpdate = 0
            }
        }
    }
}

/// Presents extension permission prompts.
private struct ExtensionPermissionPromptModifier: ViewModifier {
    @Environment(ExtensionManager.self) private var extensionManager

    func body(content: Content) -> some View {
        @Bindable var promptManager = extensionManager.permissionPromptManager

        content
            .sheet(item: $promptManager.currentRequest) { request in
                ExtensionPermissionPromptView(request: request) {
                    promptManager.completeCurrentRequest()
                }
            }
    }
}

private struct FileInputModifier: ViewModifier {
    @Bindable var state: DialogState

    func body(content: Content) -> some View {
        content.onChange(of: state.fileInput?.id) { _, newValue in
            if newValue != nil {
                presentOpenPanel()
            }
        }
    }

    private func presentOpenPanel() {
        // Atomically take the file input — this modifier is applied per-pane,
        // so multiple instances observe the same DialogState. The first pane
        // to respond claims the file input; subsequent panes see nil and bail.
        guard let fileInput = state.fileInput else { return }
        state.fileInput = nil

        guard let window = NSApp.keyWindow else {
            fileInput.continuation.resume(returning: .cancel)
            return
        }

        let panel = NSOpenPanel()
        let parameters = fileInput.parameters

        let allowedTypes = parameters.allowedContentTypes
        if !allowedTypes.isEmpty, allowedTypes != [.item] {
            panel.allowedContentTypes = allowedTypes
        }

        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = false

        panel.beginSheetModal(for: window) { response in
            switch response {
            case .OK where !panel.urls.isEmpty:
                fileInput.continuation.resume(returning: .selected(panel.urls))
            default:
                fileInput.continuation.resume(returning: .cancel)
            }
        }
    }
}

private struct ClientCertificateModifier: ViewModifier {
    @Bindable var state: DialogState

    func body(content: Content) -> some View {
        content.onChange(of: state.clientCertificate?.id) { _, newValue in
            if newValue != nil {
                presentPanel()
            }
        }
    }

    private func presentPanel() {
        // Atomically take the request — this modifier is applied per-pane, so
        // multiple instances observe the same DialogState. The first pane to
        // respond claims it; subsequent panes see nil and bail.
        guard let info = state.clientCertificate else { return }
        state.clientCertificate = nil

        // Falls back through main → first visible — mTLS challenges can fire
        // during background loads when Refrax isn't the focused app.
        let hostWindow = NSApp.keyWindow
            ?? NSApp.mainWindow
            ?? NSApp.windows.first(where: { $0.isVisible && !$0.isMiniaturized })

        guard let window = hostWindow,
              let panel = SFChooseIdentityPanel.shared()
        else {
            info.continuation.resume(returning: nil)
            return
        }

        // SFChooseIdentityPanel uses target/action completion; the bridge keeps
        // itself alive (via contextInfo) until the sheet ends. It also retains
        // `info.identities` so the picked SecIdentity is guaranteed alive when
        // we resolve the continuation — `panel.identity()` returns a +0 ref
        // and Apple's docs warn that callers must retain it themselves.
        let bridge = ClientIdentityPanelBridge(
            continuation: info.continuation,
            candidates: info.identities,
        )
        let context = Unmanaged.passRetained(bridge).toOpaque()
        let identities = info.identities
        let host = info.host

        // Defer to the next runloop turn — calling beginSheet from inside a
        // SwiftUI view update can race with the window's sheet-presentation
        // machinery and silently no-op (no sheet appears, didEnd never fires).
        DispatchQueue.main.async {
            panel.setAlternateButtonTitle("Cancel")
            panel.beginSheet(
                for: window,
                modalDelegate: bridge,
                didEnd: #selector(ClientIdentityPanelBridge.panelDidEnd(_:returnCode:contextInfo:)),
                contextInfo: context,
                identities: identities,
                message: "Choose a certificate to authenticate yourself to “\(host)”:",
            )
        }
    }
}

private final class ClientIdentityPanelBridge: NSObject {
    private let continuation: CheckedContinuation<SecIdentity?, Never>
    private let candidates: [SecIdentity]
    private var didFire = false

    init(
        continuation: CheckedContinuation<SecIdentity?, Never>,
        candidates: [SecIdentity],
    ) {
        self.continuation = continuation
        self.candidates = candidates
    }

    /// The didEnd selector's first parameter is the sheet's *parent window*,
    /// not the SFChooseIdentityPanel — the panel is accessed via its singleton.
    @objc
    func panelDidEnd(
        _: NSWindow,
        returnCode: Int,
        contextInfo: UnsafeMutableRawPointer?,
    ) {
        guard !didFire else { return }
        didFire = true

        nonisolated(unsafe) let chosen: SecIdentity? = if returnCode == NSApplication.ModalResponse.OK.rawValue,
                                                          let panel = SFChooseIdentityPanel.shared(),
                                                          let picked = panel.identity()?.takeUnretainedValue() {
            // Match by CF reference identity against our retained candidates
            // so the returned SecIdentity stays alive past this callback.
            candidates.first { ($0 as AnyObject) === (picked as AnyObject) }
                ?? picked
        } else {
            nil
        }
        continuation.resume(returning: chosen)

        if let contextInfo {
            Unmanaged<ClientIdentityPanelBridge>.fromOpaque(contextInfo).release()
        }
    }
}

// MARK: - Composite Modifiers

/// Combines all dialog-related modifiers.
///
/// Applied to the outer view to handle file pickers and certificate choice. JavaScript
/// dialogs and permission requests belong to their page (`PagePromptModifier`).
private struct DialogModifiers: ViewModifier {
    @Bindable var dialogState: DialogState

    func body(content: Content) -> some View {
        content
            .modifier(FileInputModifier(state: dialogState))
            .modifier(ClientCertificateModifier(state: dialogState))
            .modifier(ExtensionPermissionPromptModifier())
    }
}

/// Combines page-specific overlay modifiers.
///
/// Applied conditionally when we have an active page.
///
/// **Important:** The `if let webPage` branch must only change when the page is
/// assigned/released (once per tab lifetime), NOT on every `isLayoutMode` toggle.
/// Using `if/else` that flips with `isLayoutMode` creates a `_ConditionalContent`
/// branch change, which causes SwiftUI to recreate all NSViews in the content tree —
/// including the PaneWebViewAdapter's CocoaWebViewAdapter. Instead, the `isEnabled`
/// flag on each modifier gates overlay visibility without changing the structural type.
private struct PageOverlayModifiers: ViewModifier {
    let webPage: WebPage?
    let hasContent: Bool
    let isLayoutMode: Bool

    func body(content: Content) -> some View {
        if let webPage {
            content
                .modifier(FocusBlurModifier(page: webPage, isEnabled: hasContent && !isLayoutMode))
                .modifier(TimeLimitModifier(page: webPage, isEnabled: hasContent && !isLayoutMode))
                .modifier(PagePromptModifier(prompts: webPage.prompts, isEnabled: !isLayoutMode))
        } else {
            content
        }
    }
}
