import Security
import SecurityInterface
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Pane Content Wrapper

/// Wraps PositionedAdapter with full WebViewContainer functionality.
///
/// This view combines the stable adapter architecture (position-based identity)
/// with all the browser chrome features: dialogs, overlays, link previews,
/// visibility tracking, and modifier key hints.
///
/// Architecture:
/// - PositionedAdapter handles the NSView lifecycle with constant identity
/// - This wrapper adds SwiftUI overlays and modifiers that need page context
/// - Lifecycle callbacks (visibility, history) are scoped to when page exists
struct PaneContentWrapper: View {
    let position: PanePosition
    let tabPage: TabPage?
    let webPage: WebPage?
    let frame: CGRect
    let isLayoutMode: Bool

    @Environment(DialogState.self) private var dialogState
    @Environment(WindowState.self) private var windowState
    @Environment(HistoryManager.self) private var historyManager
    @Environment(HistoryActivityManager.self) private var historyActivityManager
    @Environment(ReaderModeManager.self) private var readerModeManager
    @Environment(\.webViewForcedInactive) private var isForcedInactive

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

    private var hasContent: Bool {
        tabPage != nil && frame.width > 0 && frame.height > 0
    }

    /// Stable identifier for this window.
    private var windowID: ObjectIdentifier {
        ObjectIdentifier(windowState)
    }

    /// Whether reader mode is active for this page's tab.
    private var isReaderActive: Bool {
        guard let tabPage else { return false }
        return readerModeManager.isReaderActive(for: tabPage.id)
    }

    /// Whether the webView should ignore all events.
    ///
    /// Events are blocked during layout mode, space lock, reader mode,
    /// or when globally disabled.
    private var shouldIgnoreAllEvents: Bool {
        windowState.webViewsShouldIgnoreAllEvents
            || isLayoutMode
            || windowState.isSpaceLocked
            || isReaderActive
    }

    var body: some View {
        // Determine if this window should be the owner (have the active WebView).
        // Access ownerWindowID directly to ensure SwiftUI observes changes.
        // If forcedInactive is true, we never claim ownership.
        let ownerID = webPage?.ownerWindowID
        let isCurrentOwner = ownerID == windowID
        let isWindowKey = windowState.window?.isKeyWindow ?? false
        // When ownerID is nil, we should be active - we'll claim ownership via onChange.
        // This prevents the "empty frame" gap when another window releases ownership.
        let isOwner = !isForcedInactive && (isCurrentOwner || ownerID == nil)

        ZStack(alignment: .bottomLeading) {
            // The adapter - always rendered for position stability
            // isOwner determines active vs portal mode for multi-window coordination
            PositionedAdapter(
                page: webPage,
                isActive: isOwner,
                isSnapshotMode: isLayoutMode && isOwner,
                expectedFrame: frame,
                ignoresAllEvents: shouldIgnoreAllEvents,
                onMouseDown: { [weak windowState] in
                    guard let windowState, let tabPage else { return }
                    windowState.recordInteraction(with: tabPage.id)
                },
            )
            .webViewFindNavigator(isPresented: findNavigatorBinding)

            // Overlays only when we have content and not in layout mode
            if hasContent, !isLayoutMode, let webPage, let tabPage {
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
                    .onChange(of: windowState.sidebarOverlayTrailingEdge) { _, _ in
                        updateLinkPreviewOffset(containerMinX: geo.frame(in: .global).minX)
                    }
            }
        }
        .modifier(DialogModifiers(dialogState: dialogState))
        .modifier(PageOverlayModifiers(webPage: webPage, hasContent: hasContent, isLayoutMode: isLayoutMode))
        .onAppear {
            // Claim ownership if we're the key window or no owner exists.
            // Don't claim if forced inactive (e.g., docked view when separate window is open).
            // NOTE: webPage may be nil on initial appear if pool hasn't created it yet.
            // In that case, onChange(of: webPage?.id) will handle ownership claiming.
            if !isForcedInactive, !isCurrentOwner, webPage?.ownerWindowID == nil || isWindowKey {
                webPage?.claimOwnership(for: windowState)
            }

            // Register with activity manager for time tracking
            if let tabPage {
                historyActivityManager.registerPage(tabPage.id, windowID: windowID)
                if isWindowKey {
                    historyActivityManager.updateWindowKey(windowID: windowID, isKey: true)
                }
            }

            // Notify page of visibility (creates history entry if missing)
            if let webPage, let tabPage {
                webPage.onBecameVisible()
                webPage.webInspectorManager?.tabDidBecomeVisible(tabPage.id, webView: webPage.backingWebView)

                // Record interaction for address bar focus tracking
                windowState.recordInteraction(with: tabPage.id)

                // Set up link hover callback only if we're the owner.
                // This prevents non-owner windows from overwriting the callback.
                if isOwner {
                    setupLinkHoverCallback(for: webPage)
                }
            }

            // Initialize tray offset
            cachedTrayTrailingEdge = windowState.detailTrayTrailingEdge
        }
        .onDisappear { handleDisappear() }
        .onChange(of: webPage?.id) { oldValue, newValue in
            guard oldValue != newValue else { return }

            // Clear stale hover URL from previous page
            hoveredLinkURL = nil

            // Handle webPage becoming available after initial appear.
            // This is critical because WebPagePool creates pages lazily,
            // so webPage may be nil when onAppear first fires.
            guard let webPage, let tabPage else { return }

            if oldValue == nil {
                // First-time page creation: full lifecycle setup
                let isWindowKey = windowState.window?.isKeyWindow ?? false
                let isCurrentOwner = webPage.ownerWindowID == windowID

                // Claim ownership if we're the key window or no owner exists
                if !isForcedInactive, !isCurrentOwner, webPage.ownerWindowID == nil || isWindowKey {
                    webPage.claimOwnership(for: windowState)
                }

                // Register with activity manager for time tracking
                historyActivityManager.registerPage(tabPage.id, windowID: windowID)
                if isWindowKey {
                    historyActivityManager.updateWindowKey(windowID: windowID, isKey: true)
                }

                // Notify page of visibility
                webPage.onBecameVisible()
                webPage.webInspectorManager?.tabDidBecomeVisible(tabPage.id, webView: webPage.backingWebView)

                // Record interaction for address bar focus tracking
                windowState.recordInteraction(with: tabPage.id)

                // Initialize tray offset
                cachedTrayTrailingEdge = windowState.detailTrayTrailingEdge
            }

            // Set up link hover callback for the new page (both nil→page and page→page transitions)
            let ownerID = webPage.ownerWindowID
            let isCurrentOwner = ownerID == windowID
            let isWindowKey = windowState.window?.isKeyWindow ?? false
            let isOwner = !isForcedInactive && (isCurrentOwner || (ownerID == nil && isWindowKey))

            if isOwner {
                setupLinkHoverCallback(for: webPage)
            }
        }
        .task(id: tabPage?.id) {
            guard tabPage != nil else { return }
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
            guard !isForcedInactive, let webPage, newValue == nil, oldValue != nil else { return }
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

        // HTTP error page overlay (4xx, 5xx, and network error codes)
        if let errorCode = page.httpErrorCode, let failedURL = page.httpErrorURL {
            ErrorPageView(page: page, statusCode: errorCode, failedURL: failedURL)
        }

        // Deep link view for internal browser URLs
        if tabPage.url.isDeepLink, let deepLink = DeepLink(url: tabPage.url) {
            DeepLinkView(deepLink: deepLink)
        }

        // Reader mode overlay
        ReaderOverlayContainer(tabID: tabPage.id)

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

    private func handleDisappear() {
        guard let webPage, let tabPage else { return }

        webPage.webInspectorManager?.tabWillBecomeHidden(tabPage.id, webView: webPage.backingWebView)

        // Unregister from activity manager
        historyActivityManager.unregisterPage(tabPage.id, windowID: windowID)

        webPage.onBecameHidden()

        // Release ownership unless a reference pane window is open.
        // The separate window shares the same WindowState, so releasing here
        // would clear ownership needed by the separate window's view.
        if !windowState.hasReferencePaneWindow {
            webPage.releaseOwnership(for: windowState)
        }

        // Clean up link hover callback only if we set it
        if webPage.ownerWindowID == nil || webPage.ownerWindowID == windowID {
            webPage.onHoveredLinkChanged = nil
        }

        hoveredLinkURL = nil
    }

    private func handleWindowBecameKey(_ notification: Notification) {
        // Don't claim ownership if forced inactive
        guard !isForcedInactive,
              let webPage, let tabPage,
              let keyWindow = notification.object as? NSWindow,
              keyWindow === windowState.window else {
            return
        }

        // Claim ownership when our window becomes key
        webPage.claimOwnership(for: windowState)

        windowState.recordInteraction(with: tabPage.id)
        historyActivityManager.updateWindowKey(windowID: windowID, isKey: true)

        // Take over link hover callback now that we're the owner
        setupLinkHoverCallback(for: webPage)
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
    private func periodicLastSeenUpdate() async throws {
        guard let tabPage else { return }

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

private struct AlertModifier: ViewModifier {
    @Bindable var state: DialogState

    func body(content: Content) -> some View {
        content.alert(
            state.alert?.message ?? "",
            isPresented: isPresented,
        ) {
            Button("OK", action: dismiss)
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { state.alert != nil },
            set: { if !$0 { dismiss() } },
        )
    }

    private func dismiss() {
        guard let alert = state.alert else { return }
        alert.continuation.resume()
        state.alert = nil
    }
}

private struct ConfirmModifier: ViewModifier {
    @Bindable var state: DialogState

    func body(content: Content) -> some View {
        content.alert(
            state.confirm?.message ?? "",
            isPresented: isPresented,
        ) {
            Button("OK") { dismiss(result: .ok) }
            Button("Cancel", role: .cancel) { dismiss(result: .cancel) }
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { state.confirm != nil },
            set: { if !$0 { dismiss(result: .cancel) } },
        )
    }

    private func dismiss(result: WebPage.JavaScriptConfirmResult) {
        guard let confirm = state.confirm else { return }
        confirm.continuation.resume(returning: result)
        state.confirm = nil
    }
}

private struct PromptModifier: ViewModifier {
    @Bindable var state: DialogState

    func body(content: Content) -> some View {
        content.sheet(item: promptBinding) { info in
            PromptDialogView(info: info) { result in
                info.continuation.resume(returning: result)
                state.prompt = nil
            }
        }
    }

    private var promptBinding: Binding<DialogState.PromptInfo?> {
        Binding(
            get: { state.prompt },
            set: { state.prompt = $0 },
        )
    }
}

private struct PromptDialogView: View {
    let info: DialogState.PromptInfo
    let onComplete: (WebPage.JavaScriptPromptResult) -> Void

    @State private var text: String
    @State private var didComplete = false
    @Environment(\.dismiss) private var dismiss

    init(
        info: DialogState.PromptInfo,
        onComplete: @escaping (WebPage.JavaScriptPromptResult) -> Void,
    ) {
        self.info = info
        self.onComplete = onComplete
        _text = State(initialValue: info.defaultText ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(info.message)
                .font(.headline)

            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel") { complete(result: .cancel) }
                Button("OK") { complete(result: .ok(text)) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 360)
        .onDisappear {
            if !didComplete {
                complete(result: .cancel)
            }
        }
    }

    private func complete(result: WebPage.JavaScriptPromptResult) {
        guard !didComplete else { return }
        didComplete = true
        onComplete(result)
        dismiss()
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

    // The didEnd selector's first parameter is the sheet's *parent window*,
    // not the SFChooseIdentityPanel — the panel is accessed via its singleton.
    @objc func panelDidEnd(
        _: NSWindow,
        returnCode: Int,
        contextInfo: UnsafeMutableRawPointer?,
    ) {
        guard !didFire else { return }
        didFire = true

        nonisolated(unsafe) let chosen: SecIdentity?
        if returnCode == NSApplication.ModalResponse.OK.rawValue,
           let panel = SFChooseIdentityPanel.shared(),
           let picked = panel.identity()?.takeUnretainedValue()
        {
            // Match by CF reference identity against our retained candidates
            // so the returned SecIdentity stays alive past this callback.
            chosen = candidates.first { ($0 as AnyObject) === (picked as AnyObject) }
                ?? picked
        } else {
            chosen = nil
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
/// Applied to the outer view to handle JavaScript dialogs and file pickers.
private struct DialogModifiers: ViewModifier {
    @Bindable var dialogState: DialogState

    func body(content: Content) -> some View {
        content
            .modifier(AlertModifier(state: dialogState))
            .modifier(ConfirmModifier(state: dialogState))
            .modifier(PromptModifier(state: dialogState))
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
/// including the PositionedAdapter's CocoaWebViewAdapter. Instead, the `isEnabled`
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
        } else {
            content
        }
    }
}
