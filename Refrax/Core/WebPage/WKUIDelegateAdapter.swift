import AppKit
import Foundation
import WebKit

// MARK: - WKUIDelegateAdapter

/// UI delegate adapter that bridges `WKUIDelegate` to `BrowserDialogPresenter`.
///
/// This class implements `WKUIDelegate` and forwards JavaScript dialog events
/// to the configured `BrowserDialogPresenter`.
///
/// ## Design Notes
///
/// This adapter mirrors WebKit's `WKUIDelegateAdapter` to maintain API compatibility.
/// Key responsibilities:
/// - JavaScript dialogs (alert, confirm, prompt)
/// - File input handling
/// - Permission requests (camera, microphone, screen sharing, geolocation, device sensors)
/// - Context menu support (macOS)
/// - Scroll geometry change notifications
final class WKUIDelegateAdapter: NSObject, WKUIDelegatePrivate {
    // MARK: - Properties

    /// The dialog presenter that handles JavaScript dialogs.
    private let dialogPresenter: BrowserDialogPresenter

    /// Reference to the owning WebPage.
    weak var owner: WebPage?

    /// Reference to page pool for handling forced page closes and context menu actions.
    weak var pagePool: WebPagePool?

    #if os(macOS) && !targetEnvironment(macCatalyst)
        /// Context menu builder for enhanced right-click menus.
        ///
        /// Adds custom items (Open in New Tab, Save to Photos, data detection, etc.)
        /// while preserving WebKit's standard menu items.
        private let contextMenuBuilder = WebPageContextMenuBuilder()

        /// Cached hit test result from the last mouse move event.
        ///
        /// Updated continuously as the mouse moves over elements. Used by `LinkPreviewManager`
        /// to get native hit test data (URL, bounding box) without JavaScript.
        private(set) var lastHitTestResult: _WKHitTestResult?

        /// Cached hover URL for deduplication.
        ///
        /// Tracks the last URL passed to `handleMouseDidMoveOverLink` to avoid firing
        /// redundant callbacks at 30+ Hz when hovering over the same link.
        private var lastHoverURL: URL?
    #endif

    // MARK: - Initialization

    init(dialogPresenter: BrowserDialogPresenter) {
        self.dialogPresenter = dialogPresenter
        super.init()

        #if os(macOS) && !targetEnvironment(macCatalyst)
            setupContextMenuActions()
        #endif
    }

    #if os(macOS) && !targetEnvironment(macCatalyst)
        /// Wires up context menu action callbacks to use pagePool's managers.
        private func setupContextMenuActions() {
            contextMenuBuilder.onOpenInNewTab = { [weak self] url in
                guard let self,
                      let pagePool,
                      let tab = owner?.tabPage.tab,
                      let space = tab.space ?? pagePool.state.spaces.first
                else { return }
                // Pinned/live favorite tabs have stale position info — prepend instead
                let isContained = tab.isPinned || tab.isLiveFavorite
                pagePool.tabManager.createTab(
                    url: url,
                    in: space,
                    makeActive: true,
                    loadImmediately: true,
                    insertionStrategy: isContained ? .prepend : .afterActive,
                )
            }

            contextMenuBuilder.onRemindMe = { [weak self] in
                guard let self, let pagePool, let owner else { return }
                guard let pageURL = owner.url else { return }
                let pageTitle = owner.title
                pagePool.windowManager.activeWindowController?.windowState.showRemindMeSheet(
                    url: pageURL,
                    title: pageTitle,
                )
            }

            contextMenuBuilder.onInsertGIF = { [weak self] in
                guard let self, let pagePool, let owner else { return }
                pagePool.windowManager.activeWindowController?.windowState.showGifPicker(for: owner)
            }

            contextMenuBuilder.onSpeedReadSelection = { [weak self] text in
                guard let self, let pagePool else { return }
                pagePool.windowManager.activeWindowController?.windowState.showSpeedReader(for: text)
            }

            contextMenuBuilder.onDownloadFile = { [weak self] url in
                guard let self, let pagePool else { return }
                guard let downloadManager = pagePool.state.downloadManager else { return }
                let space = owner?.tabPage.tab?.space
                Task {
                    do {
                        _ = try await downloadManager.startDownload(
                            from: url,
                            originatingURL: owner?.url,
                            spaceID: space?.id,
                            spaceName: space?.name,
                        )
                    } catch {
                        Logger.error("Image download failed: \(error)", category: Logger.downloads)
                    }
                }
            }

            contextMenuBuilder.onSaveToPhotos = { [weak self] url, _ in
                guard let self, let pagePool else { return }
                guard let downloadManager = pagePool.state.downloadManager else { return }
                let space = owner?.tabPage.tab?.space
                Task {
                    do {
                        _ = try await downloadManager.startDownload(
                            from: url,
                            originatingURL: owner?.url,
                            spaceID: space?.id,
                            spaceName: space?.name,
                            saveToPhotos: true,
                            deleteAfterPhotosImport: true,
                        )
                    } catch {
                        Logger.error("Save to Photos download failed: \(error)", category: Logger.downloads)
                    }
                }
            }

            contextMenuBuilder.isYTDLPEnabled = { [weak self] in
                guard let self, let pagePool else { return true }
                return pagePool.state.settings.ytdlpEnabled
            }

            contextMenuBuilder.onYTDLPDownload = { [weak self] pageURL, mode in
                guard let self, let pagePool, let owner else { return }
                guard let downloadManager = pagePool.state.downloadManager else { return }
                let space = owner.tabPage.tab?.space
                let settings = pagePool.state.settings

                Task {
                    do {
                        _ = try await downloadManager.startYTDLPDownload(
                            url: pageURL,
                            mode: mode,
                            useCookies: settings.ytdlpUseCookies,
                            deleteAfterPhotosImport: settings.ytdlpDeleteAfterPhotosImport,
                            spaceID: space?.id,
                            spaceName: space?.name,
                        )
                    } catch {
                        Logger.error("yt-dlp download failed: \(error)", category: Logger.downloads)
                    }
                }
            }
        }
    #endif

    // MARK: - Dialog Presentation

    func webView(
        _: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
    ) async {
        await dialogPresenter.handleJavaScriptAlert(message: message, initiatedBy: .init(frame))
    }

    func webView(
        _: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
    ) async -> Bool {
        let result = await dialogPresenter.handleJavaScriptConfirm(message: message, initiatedBy: .init(frame))

        return switch result {
        case .ok: true
        case .cancel: false
        }
    }

    func webView(
        _: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
    ) async -> String? {
        let result = await dialogPresenter.handleJavaScriptPrompt(
            message: prompt,
            defaultText: defaultText,
            initiatedBy: .init(frame),
        )

        return switch result {
        case let .ok(value): value
        case .cancel: nil
        }
    }

    func webView(
        _: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
    ) async -> [URL]? {
        let result = await dialogPresenter.handleFileInputPrompt(parameters: parameters, initiatedBy: .init(frame))

        return switch result {
        case let .selected(value): value
        case .cancel: nil
        }
    }

    // MARK: - Permissions

    /// Resolves a permission using site settings and calls the decision handler.
    ///
    /// Consolidates the common guard/resolve/log/callback pattern used by
    /// screen sharing and geolocation permission requests.
    private func resolvePermission<Decision>(
        for origin: WKSecurityOrigin,
        permissionType: String,
        defaultDecision: Decision,
        resolve: (PermissionDecisionResolver, String) -> Decision,
        decisionHandler: @escaping (Decision) -> Void,
    ) {
        let domain = origin.host

        guard let siteSettingsManager = pagePool?.siteSettingsManager else {
            decisionHandler(defaultDecision)
            return
        }

        let resolver = PermissionDecisionResolver(siteSettingsManager: siteSettingsManager)
        let decision = resolve(resolver, domain)

        Logger.debug(
            "\(permissionType) permission for \(domain): \(decision)",
            category: Logger.tabs,
        )

        decisionHandler(decision)
    }

    func webView(
        _: WKWebView,
        requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
    ) async -> WKPermissionDecision {
        guard let owner else {
            return .prompt
        }

        return await owner.configuration.deviceSensorAuthorization.decisionHandler(
            .deviceOrientationAndMotion,
            .init(frame),
            origin,
        )
    }

    func webView(
        _ webView: WKWebView,
        decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
        initiatedBy frame: WKFrameInfo,
        type: WKMediaCaptureType,
    ) async -> WKPermissionDecision {
        guard let owner else {
            return .deny
        }

        // First check site settings
        let decision = await owner.configuration.deviceSensorAuthorization.decisionHandler(
            .mediaCapture(type),
            .init(frame),
            origin,
        )

        // If already decided (allow or deny), return immediately
        guard decision == .prompt else {
            return decision
        }

        // Settings say "ask" - show our custom permission dialog
        guard let window = webView.window else {
            // No window to present dialog - fall back to WebKit's native prompt
            return .prompt
        }

        let result = await MediaCapturePermissionAlert.present(
            for: type,
            origin: origin,
            in: window,
        )

        switch result {
        case .allowOnce:
            return .grant

        case .alwaysAllow:
            // Save to site settings for future visits
            saveMediaCapturePermission(type: type, domain: origin.host, allow: true)
            return .grant

        case .deny:
            return .deny
        }
    }

    /// Saves media capture permission to site settings.
    private func saveMediaCapturePermission(type: WKMediaCaptureType, domain: String, allow: Bool) {
        guard let siteSettingsManager = pagePool?.siteSettingsManager else { return }

        let settings = siteSettingsManager.settingsOrCreate(for: domain)
        let policy: PermissionPolicy = allow ? .allow : .deny

        switch type {
        case .camera:
            settings.cameraPermission = policy
        case .microphone:
            settings.microphonePermission = policy
        case .cameraAndMicrophone:
            settings.cameraPermission = policy
            settings.microphonePermission = policy
        @unknown default:
            break
        }

        siteSettingsManager.save(settings)
        Logger.info("Saved \(type) permission for \(domain): \(policy)", category: Logger.security)
    }

    /// Handles screen/window capture permission requests.
    ///
    /// Delegates to `PermissionDecisionResolver.screenSharingPermission(for:)` which:
    /// - Returns `.screenPrompt` for `.allow` or `.ask` (shows system picker)
    /// - Returns `.deny` for explicit deny
    ///
    /// The `withSystemAudio` parameter indicates whether the request includes
    /// system audio capture. This is logged for debugging but doesn't affect
    /// the permission decision.
    @objc(_webView:requestDisplayCapturePermissionForOrigin:initiatedByFrame:withSystemAudio:decisionHandler:)
    func _webView(
        _: WKWebView,
        requestDisplayCapturePermissionForOrigin origin: WKSecurityOrigin,
        initiatedByFrame _: WKFrameInfo,
        withSystemAudio: Bool,
        decisionHandler: @escaping (WKDisplayCapturePermissionDecision) -> Void,
    ) {
        resolvePermission(
            for: origin,
            permissionType: "Screen sharing (withAudio: \(withSystemAudio))",
            defaultDecision: .screenPrompt,
            resolve: { $0.screenSharingPermission(for: $1) },
            decisionHandler: decisionHandler,
        )
    }

    /// Handles geolocation permission requests.
    ///
    /// Delegates to `PermissionDecisionResolver.locationPermission(for:)`.
    @objc(_webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:)
    func _webView(
        _: WKWebView,
        requestGeolocationPermissionForOrigin origin: WKSecurityOrigin,
        initiatedByFrame _: WKFrameInfo,
        decisionHandler: @escaping (WKPermissionDecision) -> Void,
    ) {
        resolvePermission(
            for: origin,
            permissionType: "Geolocation",
            defaultDecision: .prompt,
            resolve: { $0.locationPermission(for: $1) },
            decisionHandler: decisionHandler,
        )
    }

    // MARK: - Context Menu Support

    /// Handles context menu requests from the web view.
    ///
    /// This private delegate method is called by WebKit to customize context menus.
    /// Fetches selected text via JavaScript since `hitTestResult.lookupText` only
    /// provides dictionary lookup text (word under cursor), not the full selection.
    @objc(_webView:getContextMenuFromProposedMenu:forElement:userInfo:completionHandler:)
    func _webView(
        _ webView: WKWebView,
        getContextMenuFromProposedMenu menu: NSMenu,
        forElement element: _WKContextMenuElementInfo,
        userInfo _: (any NSSecureCoding)?,
    ) async -> NSMenu? {
        // Get selected text via JavaScript (lookupText only gives dictionary lookup text).
        // Without-gesture: a gesture-forced evaluation here would strip the transient
        // activation the right-click just granted, breaking activation-gated menu actions.
        let selectedText = try? await webView.evaluateJavaScriptWithoutUserGesture("window.getSelection().toString()") as? String

        let hitTestResult = element.hitTestResult

        // Extract video URL from media URL when element type is video
        // _WKHitTestResult.absoluteMediaURL covers both <audio> and <video> elements
        // We use elementType to distinguish video from audio
        let isVideo = hitTestResult?.elementType == .video
        let videoURL: URL? = isVideo ? hitTestResult?.absoluteMediaURL : nil

        // For video elements on multi-video pages (timelines, feeds), extract the
        // enclosing post/tweet permalink so yt-dlp targets the specific video rather
        // than the whole page. Uses elementBoundingBox center to locate the video in
        // the DOM, then walks up to find the nearest article/post container.
        var videoContextURL: URL?
        if isVideo, let bbox = hitTestResult?.elementBoundingBox, !bbox.isEmpty {
            let cx = bbox.midX
            let cy = bbox.midY
            let js = """
            (() => {
                const el = document.elementFromPoint(\(cx), \(cy));
                if (!el) return null;
                const video = el.tagName === 'VIDEO' ? el : (el.closest('video') || el.querySelector('video'));
                if (!video) return null;
                const container = video.closest('article, [data-testid="tweet"], [data-testid="cellInnerDiv"], [data-test-pin-id], .GifPlayer');
                if (!container) return null;
                const link = container.querySelector('a[href*="/status/"], a[href*="/pin/"], a[href*="/reel/"], a[href*="/p/"], a[href*="/watch"]');
                return link?.href || null;
            })()
            """
            if let urlString = try? await webView.evaluateJavaScriptWithoutUserGesture(js) as? String {
                videoContextURL = URL(string: urlString)
            }
        }

        let info = WKContextMenuElementInfoAdapter(
            pageURL: webView.url,
            linkURL: hitTestResult?.absoluteLinkURL,
            imageURL: hitTestResult?.absoluteImageURL,
            videoURL: videoURL,
            videoContextURL: videoContextURL,
            selectedText: selectedText,
            isContentEditable: hitTestResult?.isContentEditable ?? false,
        )
        return contextMenuBuilder.buildMenu(proposedMenu: menu, elementInfo: info)
    }

    // MARK: - Scroll Geometry

    /// Notifies the owner of scroll geometry changes.
    ///
    /// This private delegate method is called by WebKit when scroll geometry changes.
    /// Updates the page's scrollOffsetY for observation-based features like edge sampling.
    ///
    /// Uses a 5px threshold to avoid triggering @Observable notifications at 60+ Hz
    /// during scroll. Small movements below the threshold are ignored.
    @objc(_webView:geometryDidChange:)
    func _webView(_: WKWebView!, geometryDidChange geometry: WKScrollGeometry) {
        let adapter = WKScrollGeometryAdapter(geometry)
        let newOffsetY = adapter.contentOffset.y
        // Only update if scroll offset changed by more than 5px to reduce observation noise
        if abs((owner?.scrollOffsetY ?? 0) - newOffsetY) > 5 {
            owner?.scrollOffsetY = newOffsetY
        }
        owner?.backingWebView.geometryDidChange(adapter)
    }

    // MARK: - Direct Data Save

    /// Saves web content that WebKit already holds in memory.
    ///
    /// The PDF viewer HUD's download button delivers the document through this
    /// private delegate method — no `WKDownload` is created, so the
    /// `didBecome download` interception in `WKNavigationDelegateAdapter`
    /// never sees it. WebKit drops the click silently when this selector is
    /// missing (`UIDelegate::UIClient::saveDataToFileInDownloadsFolder`).
    @objc(_webView:saveDataToFile:suggestedFilename:mimeType:originatingURL:)
    func _webView(
        _: WKWebView,
        saveDataToFile data: Data,
        suggestedFilename: String,
        mimeType: String,
        originatingURL: URL,
    ) {
        guard let downloadManager = pagePool?.state.downloadManager else {
            Logger.warning("DownloadManager unavailable, cannot save data", category: Logger.downloads)
            return
        }

        let space = owner?.tabPage.tab?.space
        do {
            _ = try downloadManager.saveCompletedData(
                data,
                suggestedFilename: suggestedFilename,
                mimeType: mimeType,
                sourceURL: originatingURL,
                originatingTitle: owner?.title,
                customDownloadPath: space?.customDownloadPath,
                spaceID: space?.id,
                spaceName: space?.name,
                colorTag: space?.downloadColorTag,
            )
        } catch {
            Logger.error("Failed to save data to file: \(error)", category: Logger.downloads)
        }
    }

    // MARK: - Mouse Tracking

    /// Notifies the owner when the mouse moves over an element.
    ///
    /// This private delegate method is called by WebKit when the mouse moves over
    /// different elements in the web view. Used to display link URL previews.
    ///
    /// The full hit test result is cached for use by `LinkPreviewManager` to get
    /// native hit test data (URL, bounding box) without JavaScript round-trips.
    ///
    /// Deduplicates callbacks by only firing when the URL actually changes,
    /// avoiding redundant notifications at 30+ Hz during mouse movement.
    func _webView(
        _: WKWebView,
        mouseDidMoveOverElement hitTestResult: _WKHitTestResult,
        with _: NSEvent.ModifierFlags,
        userInfo _: (any NSSecureCoding)?,
    ) {
        lastHitTestResult = hitTestResult
        let newURL = hitTestResult.absoluteLinkURL
        guard newURL != lastHoverURL else { return }
        lastHoverURL = newURL
        owner?.handleMouseDidMoveOverLink(newURL)
    }

    // MARK: - Window Creation

    func webView(
        _: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures,
    ) -> WKWebView? {
        guard let owner, let pagePool,
              pagePool.state.settings.isFeatureFlagEnabled("app.realPopupWebViews", default: true)
        else {
            if owner == nil || pagePool == nil {
                Logger.warning("Cannot create popup: missing owner or page pool", category: Logger.navigation)
            }
            return nil
        }

        guard let popupPage = pagePool.createPopupPage(
            opener: owner,
            configuration: configuration,
            navigationAction: navigationAction,
            windowFeatures: windowFeatures,
        ) else {
            Logger.warning("Popup creation failed", category: Logger.navigation)
            return nil
        }

        return popupPage.backingWebView
    }

    func webViewDidClose(_: WKWebView) {
        // Called when WebKit decides to close the page. This happens when:
        // 1. JavaScript calls window.close() on a page it opened
        // 2. WebKit's tryClose() IPC times out (hung web process)
        //
        // For case 2, we need to force-close the tab since the normal close flow
        // was blocked by an unresponsive process.
        guard let pageID = owner?.tabPage.id, let pagePool else { return }
        pagePool.handleWebViewClosed(for: pageID)
    }

    // MARK: - Fullscreen Support

    /// Callback when the web view enters fullscreen.
    var onDidEnterFullscreen: ((WKWebView) -> Void)?

    /// Callback when the web view exits fullscreen.
    var onDidExitFullscreen: ((WKWebView) -> Void)?

    /// Called when the web view enters fullscreen mode.
    ///
    /// This private delegate method is called by WebKit when the web view
    /// enters fullscreen (after the fullscreen window is visible).
    @objc(_webViewDidEnterFullscreen:)
    func _webViewDidEnterFullscreen(_ webView: WKWebView) {
        onDidEnterFullscreen?(webView)
    }

    /// Called when the web view exits fullscreen mode.
    ///
    /// This private delegate method is called by WebKit when the web view
    /// exits fullscreen (after restoring to the original location).
    @objc(_webViewDidExitFullscreen:)
    func _webViewDidExitFullscreen(_ webView: WKWebView) {
        onDidExitFullscreen?(webView)
    }
}

// MARK: - WKContextMenuElementInfoAdapter

/// Adapter for context menu element information.
///
/// Provides a stable interface for accessing element information without
/// depending on private WebKit types.
struct WKContextMenuElementInfoAdapter: Sendable {
    /// The URL of the page where the context menu was triggered.
    let pageURL: URL?

    /// The URL of the activated link, if any.
    let linkURL: URL?

    /// The URL of an image at the click location, if any.
    let imageURL: URL?

    /// The URL of a video at the click location, if any.
    ///
    /// May be a blob URL for HLS/MSE streams (not directly downloadable).
    let videoURL: URL?

    /// The permalink of the post/tweet containing the right-clicked video.
    ///
    /// Extracted from the DOM by walking up from the video element to find
    /// the enclosing article/post and its permalink. This is the URL that
    /// should be passed to yt-dlp for multi-video pages (timelines, feeds).
    /// `nil` when not right-clicking on a video or when no post link is found.
    let videoContextURL: URL?

    /// The selected text in the web view, if any.
    let selectedText: String?

    /// Whether the click target is in an editable region.
    ///
    /// `true` for `<input>`, `<textarea>`, `contenteditable` elements,
    /// or documents with `designMode="on"`.
    let isContentEditable: Bool

    init(
        pageURL: URL? = nil,
        linkURL: URL? = nil,
        imageURL: URL? = nil,
        videoURL: URL? = nil,
        videoContextURL: URL? = nil,
        selectedText: String? = nil,
        isContentEditable: Bool = false,
    ) {
        self.pageURL = pageURL
        self.linkURL = linkURL
        self.imageURL = imageURL
        self.videoURL = videoURL
        self.videoContextURL = videoContextURL
        self.selectedText = selectedText
        self.isContentEditable = isContentEditable
    }
}
