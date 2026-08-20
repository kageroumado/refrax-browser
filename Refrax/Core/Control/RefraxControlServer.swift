import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import OSLog
import RefraxProtocol
import SwiftUI
import WebKit

/// Routes incoming control requests from the CLI to the appropriate browser managers.
///
/// This is the server-side counterpart to the `refrax-ctl` CLI tool. It receives
/// decoded ``ControlRequest`` values, dispatches them to the correct manager, and
/// returns ``ControlResponse`` values.
///
/// All routing runs on `@MainActor` since it accesses UI state (windows, tabs, web views).
/// The ``decodeAndHandle(_:)`` entry point is `nonisolated` so it can be called from the
/// socket host's background threads; it hops to `@MainActor` internally for the route call.
@MainActor
final class RefraxControlServer {
    // MARK: - Dependencies

    private unowned let windowManager: WindowManager
    private unowned let tabManager: TabManager
    private unowned let spaceManager: SpaceManager
    private unowned let pagePool: WebPagePool
    private unowned let browserState: BrowserState
    private unowned let referencePaneManager: ReferencePaneManager
    private unowned let groupManager: TabGroupManager
    private unowned let undoRedoManager: UndoRedoManager
    private unowned let bookmarksManager: BookmarksManager
    private unowned let historyManager: HistoryManager
    private unowned let siteSettingsManager: SiteSettingsManager
    private unowned let webInspectorManager: WebInspectorManager
    private unowned let visualFeedbackManager: VisualFeedbackManager
    private unowned let browserSettings: BrowserSettings
    private unowned let humanInterventionManager: HumanInterventionManager

    private lazy var programInterpreter = ProgramInterpreter(controlServer: self, visualFeedback: visualFeedbackManager, humanIntervention: humanInterventionManager)

    /// When a program execution is suspended for human intervention,
    /// we store the Task handle so `resumeProgram` can await its completion.
    private var pendingExecTask: Task<CTL.ExecResultInfo, Never>?

    private static let logger = OSLog(subsystem: Constants.App.bundleID, category: "control")

    // MARK: - Initialization

    init(
        windowManager: WindowManager,
        tabManager: TabManager,
        spaceManager: SpaceManager,
        pagePool: WebPagePool,
        browserState: BrowserState,
        referencePaneManager: ReferencePaneManager,
        groupManager: TabGroupManager,
        undoRedoManager: UndoRedoManager,
        bookmarksManager: BookmarksManager,
        historyManager: HistoryManager,
        siteSettingsManager: SiteSettingsManager,
        webInspectorManager: WebInspectorManager,
        visualFeedbackManager: VisualFeedbackManager,
        browserSettings: BrowserSettings,
        humanInterventionManager: HumanInterventionManager,
    ) {
        self.windowManager = windowManager
        self.tabManager = tabManager
        self.spaceManager = spaceManager
        self.pagePool = pagePool
        self.browserState = browserState
        self.referencePaneManager = referencePaneManager
        self.groupManager = groupManager
        self.undoRedoManager = undoRedoManager
        self.bookmarksManager = bookmarksManager
        self.historyManager = historyManager
        self.siteSettingsManager = siteSettingsManager
        self.webInspectorManager = webInspectorManager
        self.visualFeedbackManager = visualFeedbackManager
        self.browserSettings = browserSettings
        self.humanInterventionManager = humanInterventionManager
    }

    // MARK: - Entry Point

    /// Decodes a JSON request and routes it, returning a JSON response.
    ///
    /// Called from ``RefraxControlHost``'s background socket threads. The call
    /// automatically hops to `@MainActor` since this class is main-actor-isolated.
    func decodeAndHandle(_ data: Data) async -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        do {
            let request = try JSONDecoder().decode(ControlRequest.self, from: data)
            let response = await route(request)
            return (try? encoder.encode(response))
                ?? encodeError(encoder: encoder, code: "encode_failed", message: "Failed to encode response")
        } catch {
            return encodeError(encoder: encoder, code: "decode_failed", message: error.localizedDescription)
        }
    }

    private func encodeError(encoder: JSONEncoder, code: String, message: String) -> Data {
        let response = ControlResponse.error(CTL.ErrorInfo(code: code, message: message))
        return (try? encoder.encode(response)) ?? Data("{}".utf8)
    }

    // MARK: - Routing

    func route(_ request: ControlRequest) async -> ControlResponse {
        do {
            return try await routeThrows(request)
        } catch let error as ControlError {
            return .error(CTL.ErrorInfo(code: error.errorCode, message: error.localizedDescription))
        } catch {
            return .error(CTL.ErrorInfo(code: "internal", message: error.localizedDescription))
        }
    }

    private func routeThrows(_ request: ControlRequest) async throws -> ControlResponse {
        switch request {
        case .ping:
            handlePing()
        case .health:
            handleHealth()
        case .state:
            handleState()
        case let .screenshot(params):
            try await handleScreenshot(params)
        case let .pageContent(params):
            try await handlePageContent(params)
        case let .click(params):
            try await handleClick(params)
        case let .type(params):
            try await handleType(params)
        case let .scroll(params):
            try await handleScroll(params)
        case let .navigate(params):
            handleNavigate(params)
        case let .navigateAndWait(params):
            try await handleNavigateAndWait(params)
        case let .tabList(params):
            handleTabList(params)
        case let .tabGet(params):
            try handleTabGet(params)
        case let .tabOpen(params):
            handleTabOpen(params)
        case let .tabClose(params):
            try handleTabClose(params)
        case let .tabActivate(params):
            try handleTabActivate(params)
        case .spaceList:
            handleSpaceList()
        case let .spaceSwitch(params):
            handleSpaceSwitch(params)
        case let .windowResize(params):
            handleWindowResize(params)
        case let .windowMove(params):
            handleWindowMove(params)
        case .windowCenter:
            handleWindowCenter()
        case .windowInfo:
            handleWindowInfo()
        case .refPaneShow:
            handleRefPaneShow()
        case .refPaneHide:
            handleRefPaneHide()
        case .refPaneToggle:
            handleRefPaneToggle()
        case let .hotkey(params):
            handleHotkey(params)
        case .sidebarToggle:
            handleSidebarToggle()
        case .inspectorToggle:
            handleInspectorToggle()
        case .commandLens:
            handleCommandLens()
        case .addressLens:
            handleAddressLens()
        // UI Accessibility Tree
        case let .uiAXTree(params):
            handleUIAXTree(params)
        case let .uiAXClick(params):
            handleUIAXClick(params)
        // Tier 1A: Extended Tab Operations
        case let .tabPin(params):
            try handleTabPin(params)
        case let .tabDuplicate(params):
            try handleTabDuplicate(params)
        case let .tabRename(params):
            try handleTabRename(params)
        case let .tabMute(params):
            try handleTabMute(params)
        case let .tabGoBack(params):
            try handleTabGoBack(params)
        case let .tabGoForward(params):
            try handleTabGoForward(params)
        case .tabNext:
            handleTabNext()
        case .tabPrevious:
            handleTabPrevious()
        case let .tabDetail(params):
            try handleTabDetail(params)
        case let .tabCloseOthers(params):
            try handleTabCloseOthers(params)
        case .tabReopenClosed:
            handleTabReopenClosed()
        case .tabRecentlyClosed:
            handleTabRecentlyClosed()
        case let .tabMoveToSpace(params):
            try handleTabMoveToSpace(params)
        case let .tabMoveToGroup(params):
            try handleTabMoveToGroup(params)
        case let .tabRemoveFromGroup(params):
            try handleTabRemoveFromGroup(params)
        case let .tabMoveToRefPane(params):
            try handleTabMoveToRefPane(params)
        case let .tabReorder(params):
            try handleTabReorder(params)
        case let .tabMarkRead(params):
            try handleTabMarkRead(params)
        case let .tabMarkUnread(params):
            try handleTabMarkUnread(params)
        case let .tabCopyURL(params):
            try handleTabCopyURL(params)
        case let .tabReload(params):
            try handleTabReload(params)
        case let .tabIsLoading(params):
            try handleTabIsLoading(params)
        case let .tabURL(params):
            try handleTabURL(params)
        case let .tabWaitLoaded(params):
            try await handleTabWaitLoaded(params)
        // Tier 1B: Tab Group CRUD
        case let .groupList(params):
            handleGroupList(params)
        case let .groupCreate(params):
            try handleGroupCreate(params)
        case let .groupDelete(params):
            handleGroupDelete(params)
        case let .groupRename(params):
            handleGroupRename(params)
        case let .groupSetColor(params):
            handleGroupSetColor(params)
        case let .groupSetIcon(params):
            handleGroupSetIcon(params)
        case let .groupToggleCollapsed(params):
            handleGroupToggleCollapsed(params)
        // Tier 1C: Page Operations
        case let .pageZoomIn(params):
            try handlePageZoomIn(params)
        case let .pageZoomOut(params):
            try handlePageZoomOut(params)
        case let .pageZoomReset(params):
            try handlePageZoomReset(params)
        case let .pageFind(params):
            try await handlePageFind(params)
        case let .pageFindNext(params):
            try await handlePageFindNext(params)
        case let .pageFindPrevious(params):
            try await handlePageFindPrevious(params)
        case let .pageFindDismiss(params):
            try handlePageFindDismiss(params)
        case let .pageExecJS(params):
            try await handlePageExecJS(params)
        case let .pageSource(params):
            try await handlePageSource(params)
        case let .pageVideoViewer(params):
            try await handlePageVideoViewer(params)
        // Tier 1D: Reference Pane Extended
        case let .refPaneAddTab(params):
            handleRefPaneAddTab(params)
        case let .refPaneCloseTab(params):
            handleRefPaneCloseTab(params)
        case .refPaneListTabs:
            handleRefPaneListTabs()
        case let .refPaneActivateTab(params):
            handleRefPaneActivateTab(params)
        case let .refPaneMoveToMain(params):
            handleRefPaneMoveToMain(params)
        // Tier 1E: Visual Agent Features
        case let .visualHighlight(params):
            try await handleVisualHighlight(params)
        case let .visualCursor(params):
            handleVisualCursor(params)
        case let .visualClick(params):
            try await handleVisualClick(params)
        case let .visualScrollTo(params):
            try await handleVisualScrollTo(params)
        case .visualClear:
            handleVisualClear()
        // Tier 2A: Bookmarks
        case let .bookmarkList(params):
            handleBookmarkList(params)
        case let .bookmarkCreate(params):
            handleBookmarkCreate(params)
        case let .bookmarkDelete(params):
            handleBookmarkDelete(params)
        case let .bookmarkFavorite(params):
            handleBookmarkFavorite(params)
        case let .bookmarkUnfavorite(params):
            handleBookmarkUnfavorite(params)
        case .bookmarkFolderList:
            handleBookmarkFolderList()
        case let .bookmarkFolderCreate(params):
            try handleBookmarkFolderCreate(params)
        // Tier 2B: History
        case let .historyList(params):
            await handleHistoryList(params)
        case let .historySearch(params):
            await handleHistorySearch(params)
        case let .historyClear(params):
            handleHistoryClear(params)
        case let .historyFrequent(params):
            handleHistoryFrequent(params)
        // Tier 2C: Space CRUD
        case let .spaceCreate(params):
            handleSpaceCreate(params)
        case let .spaceUpdate(params):
            handleSpaceUpdate(params)
        case let .spaceDelete(params):
            handleSpaceDelete(params)
        // Tier 2D: Window Extended
        case .windowKeepOnTop:
            handleWindowKeepOnTop()
        case .windowAllDesktops:
            handleWindowAllDesktops()
        case .windowLockSize:
            handleWindowLockSize()
        case let .windowSetOpacity(params):
            handleWindowSetOpacity(params)
        case .windowFullScreen:
            handleWindowFullScreen()
        case .windowMinimize:
            handleWindowMinimize()
        // Tier 2E: Site Settings
        case let .siteSettingsGet(params):
            handleSiteSettingsGet(params)
        case let .siteSettingsSet(params):
            handleSiteSettingsSet(params)
        // Tier 2F: Developer Tools
        case let .devInspector(params):
            try handleDevInspector(params)
        case let .devConsole(params):
            try handleDevConsole(params)
        case let .devResources(params):
            try handleDevResources(params)
        case let .devProfiling(params):
            try handleDevProfiling(params)
        case let .devElementSelection(params):
            try handleDevElementSelection(params)
        case .devEmptyCaches:
            await handleDevEmptyCaches()
        case let .devConsoleLog(params):
            handleDevConsoleLog(params)
        case let .devNetworkLog(params):
            handleDevNetworkLog(params)
        case let .devCookies(params):
            try await handleDevCookies(params)
        case let .devStorage(params):
            try await handleDevStorage(params)
        // Tier 3: Interaction Enhancements
        case let .hover(params):
            try await handleHover(params)
        case let .formInput(params):
            try await handleFormInput(params)
        // Compound Commands
        case let .navigateAndRead(params):
            try await handleNavigateAndRead(params)
        case let .clickAndRead(params):
            try await handleClickAndRead(params)
        case let .fillForm(params):
            try await handleFillForm(params)
        case let .scrollAndRead(params):
            try await handleScrollAndRead(params)
        case let .findElements(params):
            try await handleFindElements(params)
        // Program Execution
        case let .execProgram(params):
            try await handleExecProgram(params)
        case let .resumeProgram(params):
            try await handleResumeProgram(params)
        // Cookie Consent
        case let .dismissCookies(params):
            try await handleDismissCookies(params)
        // Global Settings
        case let .settingsList(params):
            handleSettingsList(params)
        case let .settingsGet(params):
            try handleSettingsGet(params)
        case let .settingsSet(params):
            try handleSettingsSet(params)
        // Headless Fetch
        case let .fetch(params):
            try await handleFetch(params)
        case let .navigateNewTab(params):
            try await handleNavigateNewTab(params)
        }
    }

    // MARK: - State

    private func handleState() -> ControlResponse {
        let windowState = windowManager.activeWindowController?.windowState
        let activeTabID = windowState?.activeTabID
        let activeSpaceID = windowState?.activeSpaceID

        let tabs = browserState.spaces.flatMap { space in
            space.tabs.map { tab in
                buildTabInfo(tab, activeTabID: activeTabID)
            }
        }

        let spaces = browserState.spaces.map { space in
            buildSpaceInfo(space, activeSpaceID: activeSpaceID)
        }

        let info = CTL.BrowserStateInfo(
            tabs: tabs,
            spaces: spaces,
            activeTabID: activeTabID.map { "\($0)" },
            activeSpaceID: activeSpaceID.map { "\($0)" },
        )
        return .state(info)
    }

    private func handlePing() -> ControlResponse {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        return .ping(CTL.PingInfo(
            protocolVersion: ControlProtocolVersion.v1.rawValue,
            appVersion: appVersion,
        ))
    }

    private func handleHealth() -> ControlResponse {
        let tabCount = browserState.spaces.reduce(0) { $0 + $1.tabs.count }
        let windowCount = windowManager.windowControllers.count
        let spaceCount = browserState.spaces.count
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"

        // Memory usage via task_info
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        let memoryMB = result == KERN_SUCCESS ? Int(taskInfo.resident_size / (1_024 * 1_024)) : 0

        // Uptime
        let uptime = Int(ProcessInfo.processInfo.systemUptime)

        return .health(CTL.HealthInfo(
            appVersion: appVersion,
            protocolVersion: ControlProtocolVersion.v1.rawValue,
            tabCount: tabCount,
            windowCount: windowCount,
            spaceCount: spaceCount,
            memoryUsageMB: memoryMB,
            uptimeSeconds: uptime,
        ))
    }

    // MARK: - Screenshot

    private func handleScreenshot(_ params: ControlRequest.ScreenshotParams) async throws -> ControlResponse {
        guard let controller = windowManager.activeWindowController else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }

        let scaleFactor = NSScreen.main?.backingScaleFactor ?? 2.0
        let grid = params.grid ?? false
        let logical = params.logical ?? false

        switch params.mode {
        case .window:
            guard let window = controller.window else {
                return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
            }
            guard let data = await WindowScreenshotService.captureWindow(window) else {
                return .error(CTL.ErrorInfo(code: "capture_failed", message: "Window capture failed"))
            }
            let size = window.frame.size
            return buildScreenshotResponse(data: data, logicalSize: size, scaleFactor: scaleFactor, grid: grid, logical: logical)

        case .windowGlass:
            guard let window = controller.window else {
                return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
            }
            guard let data = await WindowScreenshotService.captureWindowComposited(window) else {
                return .error(CTL.ErrorInfo(
                    code: "capture_failed",
                    message: "Composited window capture failed (screen recording permission may be required)",
                ))
            }
            let size = window.frame.size
            return buildScreenshotResponse(data: data, logicalSize: size, scaleFactor: scaleFactor, grid: grid, logical: logical)

        case .visible, .full:
            let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)

            if let rectString = params.rect {
                let components = rectString.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                guard components.count == 4, components[2] > 0, components[3] > 0 else {
                    return .error(CTL.ErrorInfo(
                        code: "invalid_rect",
                        message: "Invalid rect '\(rectString)' — expected x,y,w,h in document coordinates with positive size",
                    ))
                }
                let rect = CGRect(x: components[0], y: components[1], width: components[2], height: components[3])
                let data = try await ScreenshotService.captureRegion(of: webPage, rect: rect)
                return buildScreenshotResponse(data: data, logicalSize: rect.size, scaleFactor: scaleFactor, grid: grid, logical: logical)
            }

            let mode: ScreenshotMode = params.mode == .full ? .fullPage : .visibleArea
            let data = try await ScreenshotService.takeScreenshot(of: webPage, mode: mode)
            let size = webPage.backingWebView.bounds.size
            return buildScreenshotResponse(data: data, logicalSize: size, scaleFactor: scaleFactor, grid: grid, logical: logical)
        }
    }

    /// Builds a screenshot response, applying optional grid overlay and logical downscaling.
    private func buildScreenshotResponse(
        data: Data,
        logicalSize: CGSize,
        scaleFactor: Double,
        grid: Bool,
        logical: Bool,
    ) -> ControlResponse {
        let logicalWidth = Int(logicalSize.width)
        let logicalHeight = Int(logicalSize.height)
        let pixelWidth = Int(logicalSize.width * scaleFactor)
        let pixelHeight = Int(logicalSize.height * scaleFactor)

        let finalData = applyScreenshotPostProcessing(
            data: data,
            logicalWidth: logicalWidth,
            logicalHeight: logicalHeight,
            scaleFactor: scaleFactor,
            grid: grid,
            logical: logical,
        )

        let outputWidth = logical ? logicalWidth : pixelWidth
        let outputHeight = logical ? logicalHeight : pixelHeight

        return .screenshot(CTL.ScreenshotInfo(
            data: finalData.base64EncodedString(),
            width: logicalWidth,
            height: logicalHeight,
            pixelWidth: outputWidth,
            pixelHeight: outputHeight,
            scaleFactor: scaleFactor,
        ))
    }

    /// Applies optional grid overlay and logical downscaling to screenshot data.
    private func applyScreenshotPostProcessing(
        data: Data,
        logicalWidth: Int,
        logicalHeight: Int,
        scaleFactor: Double,
        grid: Bool,
        logical: Bool,
    ) -> Data {
        guard grid || logical else { return data }

        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return data
        }

        // Work at pixel resolution for grid drawing, then optionally downscale
        let workWidth = cgImage.width
        let workHeight = cgImage.height

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: workWidth,
            height: workHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else {
            return data
        }

        // Draw original image
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: workWidth, height: workHeight))

        if grid {
            drawCoordinateGrid(
                in: ctx,
                pixelWidth: workWidth,
                pixelHeight: workHeight,
                scaleFactor: scaleFactor,
            )
        }

        guard let resultImage = ctx.makeImage() else { return data }

        if logical {
            // Downscale to logical dimensions
            guard let downscaleCtx = CGContext(
                data: nil,
                width: logicalWidth,
                height: logicalHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else {
                return data
            }
            downscaleCtx.interpolationQuality = .high
            downscaleCtx.draw(resultImage, in: CGRect(x: 0, y: 0, width: logicalWidth, height: logicalHeight))
            guard let downscaled = downscaleCtx.makeImage() else { return data }
            let rep = NSBitmapImageRep(cgImage: downscaled)
            return rep.representation(using: .png, properties: [:]) ?? data
        } else {
            let rep = NSBitmapImageRep(cgImage: resultImage)
            return rep.representation(using: .png, properties: [:]) ?? data
        }
    }

    /// Draws a coordinate grid overlay in logical pixel coordinates.
    private func drawCoordinateGrid(
        in ctx: CGContext,
        pixelWidth: Int,
        pixelHeight: Int,
        scaleFactor: Double,
    ) {
        let gridSpacing = 100.0

        ctx.setStrokeColor(CGColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.35))
        ctx.setLineWidth(1.0)

        // CGContext has origin at bottom-left; we need to draw with flipped Y
        // since logical (0,0) is top-left for web coordinates

        // Vertical lines (at logical X intervals)
        var logicalX = gridSpacing
        while logicalX * scaleFactor < Double(pixelWidth) {
            let px = logicalX * scaleFactor
            ctx.move(to: CGPoint(x: px, y: 0))
            ctx.addLine(to: CGPoint(x: px, y: Double(pixelHeight)))
            logicalX += gridSpacing
        }
        ctx.strokePath()

        // Horizontal lines (at logical Y intervals)
        var logicalY = gridSpacing
        while logicalY * scaleFactor < Double(pixelHeight) {
            // Flip Y: pixel Y from bottom = pixelHeight - logicalY * scaleFactor
            let py = Double(pixelHeight) - logicalY * scaleFactor
            ctx.move(to: CGPoint(x: 0, y: py))
            ctx.addLine(to: CGPoint(x: Double(pixelWidth), y: py))
            logicalY += gridSpacing
        }
        ctx.strokePath()

        // Draw coordinate labels at intersections
        let fontSize = max(10.0, 11.0 * scaleFactor)
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)

        logicalX = gridSpacing
        while logicalX * scaleFactor < Double(pixelWidth) {
            logicalY = gridSpacing
            while logicalY * scaleFactor < Double(pixelHeight) {
                let label = "\(Int(logicalX)),\(Int(logicalY))"
                let px = logicalX * scaleFactor + 3.0
                // Flip Y for drawing text
                let py = Double(pixelHeight) - logicalY * scaleFactor + 3.0

                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.6),
                ]
                let attrString = NSAttributedString(string: label, attributes: attributes)
                let line = CTLineCreateWithAttributedString(attrString)

                ctx.saveGState()
                ctx.textPosition = CGPoint(x: px, y: py)
                CTLineDraw(line, ctx)
                ctx.restoreGState()

                logicalY += gridSpacing
            }
            logicalX += gridSpacing
        }
    }

    // MARK: - Page Content

    private func handlePageContent(_ params: ControlRequest.PageContentParams) async throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)

        switch params.scope {
        case .viewport, .full, .mainContent:
            let webView = webPage.backingWebView
            let url = webPage.url ?? .blank
            let title = webPage.title

            if params.fresh == true {
                PageContentExtractor.clearCache(for: url)
            }

            let tree = try await PageContentExtractor.extract(from: webView, url: url, title: title)
            let scope: PageContentFormatter.Scope = switch params.scope {
            case .full: .full
            case .mainContent: .mainContent
            default: .viewport
            }
            let text = PageContentFormatter.format(tree, scope: scope)
            return .pageContent(text)

        case .html:
            let result = try await webPage.callJavaScript("return document.documentElement.outerHTML")
            let html = result as? String ?? ""
            return .pageContent(html)

        case .text:
            let result = try await webPage.callJavaScript("return document.body.innerText")
            let text = result as? String ?? ""
            return .pageContent(text)
        }
    }

    // MARK: - Click

    private func handleClick(_ params: ControlRequest.ClickParams) async throws -> ControlResponse {
        if let ref = params.ref {
            // Handle frame-prefixed refs (e.g., "f1:e3") — route through iframe JS injection
            if let frameRef = PageContentTree.parseFrameRef(ref) {
                return try await handleFrameClick(
                    frameRef: frameRef,
                    tabID: params.tabID,
                    pageID: params.pageID,
                )
            }

            let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
            let webView = webPage.backingWebView
            let url = webPage.url ?? .blank
            let title = webPage.title
            let tree = try await PageContentExtractor.extract(from: webView, url: url, title: title)

            guard let node = tree.findNode(byRef: ref) else {
                return .error(CTL.ErrorInfo(code: "not_found", message: "Element ref '\(ref)' not found"))
            }

            if let nativeID = node.nativeID {
                let interaction = _WKTextExtractionInteraction(action: .click)
                interaction.nodeIdentifier = nativeID
                if Self.supportsScrollToVisible { interaction.scrollToVisible = true }
                do {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                        webView._performInteraction(interaction) { result in
                            if let error = result.error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                        }
                    }
                } catch {
                    return .error(CTL.ErrorInfo(code: "interaction_failed", message: mapWebKitError(error)))
                }

                // Dispatch double-click or right-click events after the native click
                if params.doubleClick == true {
                    let x = node.rect.midX
                    let y = node.rect.midY
                    try await webPage.callJavaScript("""
                    var el = document.elementFromPoint(\(x), \(y));
                    if (el) { el.dispatchEvent(new MouseEvent('dblclick', {bubbles: true, clientX: \(x), clientY: \(y)})); }
                    """)
                } else if params.rightClick == true {
                    let x = node.rect.midX
                    let y = node.rect.midY
                    try await webPage.callJavaScript("""
                    var el = document.elementFromPoint(\(x), \(y));
                    if (el) { el.dispatchEvent(new MouseEvent('contextmenu', {bubbles: true, clientX: \(x), clientY: \(y)})); }
                    """)
                }
            } else {
                let centerX = node.rect.midX
                let centerY = node.rect.midY
                if params.rightClick == true {
                    try await webPage.callJavaScript("""
                    var el = document.elementFromPoint(\(centerX), \(centerY));
                    if (el) { el.dispatchEvent(new MouseEvent('contextmenu', {bubbles: true, clientX: \(centerX), clientY: \(centerY)})); }
                    """)
                } else if params.doubleClick == true {
                    try await webPage.callJavaScript("""
                    var el = document.elementFromPoint(\(centerX), \(centerY));
                    if (el) { el.click(); el.dispatchEvent(new MouseEvent('dblclick', {bubbles: true, clientX: \(centerX), clientY: \(centerY)})); }
                    """)
                } else {
                    try await webPage.callJavaScript("document.elementFromPoint(\(centerX), \(centerY))?.click()")
                }
            }

            return .actionResult(CTL.ActionResultInfo(success: true, message: "Clicked \(ref)"))
        }

        if let x = params.x, let y = params.y {
            let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
            if params.rightClick == true {
                try await webPage.callJavaScript("""
                var el = document.elementFromPoint(\(x), \(y));
                if (el) { el.dispatchEvent(new MouseEvent('contextmenu', {bubbles: true, clientX: \(x), clientY: \(y)})); }
                """)
            } else if params.doubleClick == true {
                try await webPage.callJavaScript("""
                var el = document.elementFromPoint(\(x), \(y));
                if (el) { el.click(); el.dispatchEvent(new MouseEvent('dblclick', {bubbles: true, clientX: \(x), clientY: \(y)})); }
                """)
            } else {
                // Native interaction: dispatches trusted events that grant real user
                // activation. A JS `el.click()` inside a gesture-forced evaluation
                // also works, but that evaluation strips the page's transient
                // activation when it completes, so activation-gated responses to
                // the click (fullscreen, popups, PiP) survive only if they run
                // synchronously. Fall back to the JS path if the native
                // interaction fails (e.g. point outside the visible bounds).
                let interaction = _WKTextExtractionInteraction(action: .click)
                interaction.location = CGPoint(x: x, y: y)
                do {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                        webPage.backingWebView._performInteraction(interaction) { result in
                            if let error = result.error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                        }
                    }
                } catch {
                    try await webPage.callJavaScript("document.elementFromPoint(\(x), \(y))?.click()")
                }
            }

            // Identify the element at the click position for feedback.
            // Without-gesture evaluation: a gesture-forced read here would strip
            // the transient activation the click just granted, breaking
            // activation-gated responses (fullscreen, popups, PiP).
            let hitInfo = try? await webPage.evaluateJavaScriptWithoutUserGesture("""
            (function() {
                var el = document.elementFromPoint(\(x), \(y));
                if (!el) return 'no element at position';
                var tag = el.tagName.toLowerCase();
                var text = (el.textContent || '').trim().substring(0, 50);
                return tag + (text ? ' "' + text + '"' : '');
            })()
            """)
            let hitDescription = (hitInfo as? String) ?? "unknown"
            return .actionResult(CTL.ActionResultInfo(success: true, message: "Clicked at (\(Int(x)), \(Int(y))) — hit: \(hitDescription)"))
        }

        return .error(CTL.ErrorInfo(code: "invalid_params", message: "Click requires either 'ref' or 'x'/'y' coordinates"))
    }

    // MARK: - Frame Interaction

    /// Resolved frame element with its page-space coordinates.
    private struct ResolvedFrameElement {
        let element: FrameElement
        let pageX: CGFloat
        let pageY: CGFloat
        let webPage: WebPage
    }

    enum FrameResolutionError: Error {
        case notFound(ControlResponse)
    }

    /// Resolves a frame-prefixed ref to its element and page-space coordinates.
    ///
    /// Looks up the frame origin, validates the element index, extracts the page
    /// content tree to find the iframe's position, then computes the element's
    /// center in page coordinates.
    private func resolveFrameElement(
        frameRef: (frameID: String, elementIndex: Int),
        tabID: String?,
        pageID: String?,
    ) async throws -> ResolvedFrameElement {
        let webPage = try resolveWebPage(tabID: tabID, pageID: pageID)

        guard let origin = FrameContentExtractor.shared.origin(forFrameID: frameRef.frameID) else {
            throw FrameResolutionError.notFound(.error(CTL.ErrorInfo(code: "not_found", message: "Frame '\(frameRef.frameID)' not found")))
        }

        guard let frameContent = FrameContentExtractor.shared.content(forOrigin: origin),
              frameRef.elementIndex < frameContent.elements.count
        else {
            throw FrameResolutionError.notFound(.error(CTL.ErrorInfo(
                code: "not_found",
                message: "Element index \(frameRef.elementIndex) not found in frame '\(frameRef.frameID)'",
            )))
        }

        let element = frameContent.elements[frameRef.elementIndex]
        let tree = try await PageContentExtractor.extract(
            from: webPage.backingWebView,
            url: webPage.url ?? .blank,
            title: webPage.title,
        )
        let iframeRect = findIframeRect(in: tree.root, origin: origin) ?? .zero

        return ResolvedFrameElement(
            element: element,
            pageX: iframeRect.origin.x + element.rect.midX,
            pageY: iframeRect.origin.y + element.rect.midY,
            webPage: webPage,
        )
    }

    /// Handles clicking an element inside a cross-origin iframe.
    ///
    /// Frame-prefixed refs (e.g., "f1:e3") identify elements extracted by the
    /// ``FrameContentExtractor`` from cross-origin iframes. Since native `_performInteraction`
    /// cannot reach into cross-origin frames, we use coordinate-based clicking through
    /// the iframe boundary.
    private func handleFrameClick(
        frameRef: (frameID: String, elementIndex: Int),
        tabID: String?,
        pageID: String?,
    ) async throws -> ControlResponse {
        let frame: ResolvedFrameElement
        do {
            frame = try await resolveFrameElement(frameRef: frameRef, tabID: tabID, pageID: pageID)
        } catch let FrameResolutionError.notFound(response) {
            return response
        }

        try await frame.webPage.callJavaScript("""
        (function() {
            var el = document.elementFromPoint(\(frame.pageX), \(frame.pageY));
            if (el) el.click();
        })()
        """)

        let label = frame.element.text.prefix(50)
        return .actionResult(CTL.ActionResultInfo(
            success: true,
            message: "Clicked frame element \(frameRef.frameID):e\(frameRef.elementIndex)"
                + (label.isEmpty ? "" : " \"\(label)\""),
        ))
    }

    /// Handles typing into an element inside a cross-origin iframe.
    private func handleFrameType(
        frameRef: (frameID: String, elementIndex: Int),
        text: String,
        tabID: String?,
        pageID: String?,
    ) async throws -> ControlResponse {
        let frame: ResolvedFrameElement
        do {
            frame = try await resolveFrameElement(frameRef: frameRef, tabID: tabID, pageID: pageID)
        } catch let FrameResolutionError.notFound(response) {
            return response
        }

        let escapedText = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        try await frame.webPage.callJavaScript("""
        (function() {
            var el = document.elementFromPoint(\(frame.pageX), \(frame.pageY));
            if (el) {
                el.click();
                el.focus();
                if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
                    el.value = '\(escapedText)';
                    el.dispatchEvent(new Event('input', {bubbles: true}));
                    el.dispatchEvent(new Event('change', {bubbles: true}));
                }
            }
        })()
        """)

        return .actionResult(CTL.ActionResultInfo(
            success: true,
            message: "Typed into frame element \(frameRef.frameID):e\(frameRef.elementIndex)",
        ))
    }

    /// Finds the bounding rect of an iframe node in the content tree by origin.
    private func findIframeRect(in node: PageContentNode, origin: String) -> CGRect? {
        if case let .iframe(iframeOrigin) = node.type, iframeOrigin == origin {
            return node.rect
        }
        for child in node.children {
            if let found = findIframeRect(in: child, origin: origin) {
                return found
            }
        }
        return nil
    }

    // MARK: - Type

    private func handleType(_ params: ControlRequest.TypeParams) async throws -> ControlResponse {
        // Handle frame-prefixed refs
        if let ref = params.elementRef, let frameRef = PageContentTree.parseFrameRef(ref) {
            return try await handleFrameType(
                frameRef: frameRef,
                text: params.text,
                tabID: params.tabID,
                pageID: params.pageID,
            )
        }

        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        let webView = webPage.backingWebView

        if let ref = params.elementRef {
            let url = webPage.url ?? .blank
            let title = webPage.title
            let tree = try await PageContentExtractor.extract(from: webView, url: url, title: title)

            guard let node = tree.findNode(byRef: ref) else {
                return .error(CTL.ErrorInfo(code: "not_found", message: "Element ref '\(ref)' not found"))
            }

            if let nativeID = node.nativeID {
                let focusInteraction = _WKTextExtractionInteraction(action: .click)
                focusInteraction.nodeIdentifier = nativeID
                if Self.supportsScrollToVisible { focusInteraction.scrollToVisible = true }
                do {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                        webView._performInteraction(focusInteraction) { result in
                            if let error = result.error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                        }
                    }
                } catch {
                    return .error(CTL.ErrorInfo(code: "interaction_failed", message: mapWebKitError(error)))
                }

                let typeInteraction = _WKTextExtractionInteraction(action: .textInput)
                typeInteraction.nodeIdentifier = nativeID
                if Self.supportsScrollToVisible { typeInteraction.scrollToVisible = true }
                typeInteraction.text = params.text
                do {
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                        webView._performInteraction(typeInteraction) { result in
                            if let error = result.error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                        }
                    }
                } catch {
                    return .error(CTL.ErrorInfo(code: "interaction_failed", message: mapWebKitError(error)))
                }
            } else {
                let centerX = node.rect.midX
                let centerY = node.rect.midY
                let escapedText = params.text.replacingOccurrences(of: "'", with: "\\'")
                try await webPage.callJavaScript("""
                var el = document.elementFromPoint(\(centerX), \(centerY));
                if (el) { el.focus(); document.execCommand('insertText', false, '\(escapedText)'); }
                """)
            }
        } else {
            let escapedText = params.text.replacingOccurrences(of: "'", with: "\\'")
            try await webPage.callJavaScript("document.execCommand('insertText', false, '\(escapedText)')")
        }

        return .actionResult(CTL.ActionResultInfo(success: true, message: "Typed \(params.text.count) characters"))
    }

    // MARK: - Scroll

    private func handleScroll(_ params: ControlRequest.ScrollParams) async throws -> ControlResponse {
        // Ref-based scroll: scroll an element into view
        if let ref = params.ref {
            let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
            let webView = webPage.backingWebView
            let url = webPage.url ?? .blank
            let title = webPage.title
            let tree = try await PageContentExtractor.extract(from: webView, url: url, title: title)

            guard let node = tree.findNode(byRef: ref) else {
                return .error(CTL.ErrorInfo(code: "not_found", message: "Element ref '\(ref)' not found"))
            }

            try await scrollElementIntoView(rect: node.rect, webPage: webPage)

            let rect = node.rect
            let message = "Scrolled to \(ref) at (\(Int(rect.origin.x)), \(Int(rect.origin.y)), \(Int(rect.width))x\(Int(rect.height)))"
            return .actionResult(CTL.ActionResultInfo(success: true, message: message))
        }

        // Direction-based scroll
        if let direction = params.direction {
            let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
            let amount = params.amount ?? 500

            let (dx, dy): (Int, Int) = switch direction.lowercased() {
            case "up": (0, -amount)
            case "down": (0, amount)
            case "left": (-amount, 0)
            case "right": (amount, 0)
            default: (0, amount)
            }

            try await webPage.callJavaScript("window.scrollBy(\(dx), \(dy))")
            return .actionResult(CTL.ActionResultInfo(success: true, message: "Scrolled \(direction)"))
        }

        return .error(CTL.ErrorInfo(code: "invalid_params", message: "Scroll requires either 'ref' or 'direction'"))
    }

    // MARK: - Navigate

    private func handleNavigate(_ params: ControlRequest.NavigateParams) -> ControlResponse {
        guard let url = URL(string: params.url) else {
            return .error(CTL.ErrorInfo(code: "invalid_url", message: "Invalid URL: \(params.url)"))
        }

        do {
            let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
            webPage.load(url)
            return .actionResult(CTL.ActionResultInfo(success: true, message: "Navigating to \(params.url)"))
        } catch let error as ControlError {
            return .error(CTL.ErrorInfo(code: error.errorCode, message: error.localizedDescription))
        } catch {
            return .error(CTL.ErrorInfo(code: "internal", message: error.localizedDescription))
        }
    }

    private func handleNavigateAndWait(_ params: ControlRequest.NavigateAndWaitParams) async throws -> ControlResponse {
        guard let url = URL(string: params.url) else {
            return .error(CTL.ErrorInfo(code: "invalid_url", message: "Invalid URL: \(params.url)"))
        }

        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        webPage.load(url)

        // Brief delay to let navigation start before polling
        try? await Task.sleep(for: .milliseconds(100))

        try await waitForPageLoad(webPage, timeout: params.timeout ?? 30)

        let finalURL = webPage.url?.absoluteString ?? params.url
        return .actionResult(CTL.ActionResultInfo(success: true, message: "Navigated to \(finalURL)"))
    }

    // MARK: - Tab Operations

    private func handleTabList(_ params: ControlRequest.TabListParams) -> ControlResponse {
        let activeTabID = windowManager.activeWindowController?.windowState.activeTabID
        var tabs: [CTL.TabInfo] = []

        if let spaceIDString = params.spaceID {
            guard let space = findSpace(byID: spaceIDString) else {
                return .error(CTL.ErrorInfo(code: "not_found", message: "Space not found: \(spaceIDString)"))
            }
            tabs = space.tabs.map { buildTabInfo($0, activeTabID: activeTabID) }
        } else {
            tabs = browserState.spaces.flatMap { space in
                space.tabs.map { buildTabInfo($0, activeTabID: activeTabID) }
            }
        }

        return .tabs(tabs)
    }

    private func handleTabGet(_ params: ControlRequest.TabGetParams) throws -> ControlResponse {
        let tab = try resolveTabRef(params.id)
        let activeTabID = windowManager.activeWindowController?.windowState.activeTabID
        return .tab(buildTabInfo(tab, activeTabID: activeTabID))
    }

    private func handleTabOpen(_ params: ControlRequest.TabOpenParams) -> ControlResponse {
        guard let url = URL(string: params.url) else {
            return .error(CTL.ErrorInfo(code: "invalid_url", message: "Invalid URL: \(params.url)"))
        }

        let space: Space?
        if let spaceIDString = params.spaceID {
            space = findSpace(byID: spaceIDString)
            if space == nil {
                return .error(CTL.ErrorInfo(code: "not_found", message: "Space not found: \(spaceIDString)"))
            }
        } else {
            space = windowManager.activeWindowController?.windowState.activeSpace
        }

        let activate = params.activate ?? true
        let tab = tabManager.createTab(url: url, in: space, makeActive: activate)
        let activeTabID = activate ? tab.id : windowManager.activeWindowController?.windowState.activeTabID
        return .tab(buildTabInfo(tab, activeTabID: activeTabID))
    }

    private func handleTabClose(_ params: ControlRequest.TabCloseParams) throws -> ControlResponse {
        let tab = try resolveTabRef(params.id)
        tabManager.closeTab(tab)
        return .ok("Tab closed")
    }

    private func handleTabActivate(_ params: ControlRequest.TabActivateParams) throws -> ControlResponse {
        let tab = try resolveTabRef(params.id)
        guard let windowState = windowManager.activeWindowController?.windowState else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        tabManager.setActiveTab(tab, in: windowState)
        return .ok("Tab activated")
    }

    // MARK: - Space Operations

    private func handleSpaceList() -> ControlResponse {
        let activeSpaceID = windowManager.activeWindowController?.windowState.activeSpaceID
        let spaces = browserState.spaces.map { buildSpaceInfo($0, activeSpaceID: activeSpaceID) }
        return .spaces(spaces)
    }

    private func handleSpaceSwitch(_ params: ControlRequest.SpaceSwitchParams) -> ControlResponse {
        guard let space = findSpace(byID: params.id) else {
            return .error(CTL.ErrorInfo(code: "not_found", message: "Space not found: \(params.id)"))
        }
        guard let windowState = windowManager.activeWindowController?.windowState else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        windowState.activeSpaceID = space.id
        return .ok("Switched to space '\(space.name)'")
    }

    // MARK: - Window Operations

    private func handleWindowResize(_ params: ControlRequest.WindowResizeParams) -> ControlResponse {
        guard let window = windowManager.activeWindowController?.window else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        var frame = window.frame
        frame.size = NSSize(width: params.width, height: params.height)
        window.setFrame(frame, display: true, animate: true)
        return .ok("Window resized to \(params.width)x\(params.height)")
    }

    private func handleWindowMove(_ params: ControlRequest.WindowMoveParams) -> ControlResponse {
        guard let window = windowManager.activeWindowController?.window else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        window.setFrameOrigin(NSPoint(x: params.x, y: params.y))
        return .ok("Window moved to (\(params.x), \(params.y))")
    }

    private func handleWindowCenter() -> ControlResponse {
        guard let window = windowManager.activeWindowController?.window else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        window.center()
        return .ok("Window centered")
    }

    private func handleWindowInfo() -> ControlResponse {
        guard let controller = windowManager.activeWindowController,
              let window = controller.window else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }

        let frame = window.frame
        let windowState = controller.windowState

        return .windowInfo(CTL.WindowInfoData(
            x: Int(frame.origin.x),
            y: Int(frame.origin.y),
            width: Int(frame.width),
            height: Int(frame.height),
            isSidebarCollapsed: windowState.isSidebarCollapsed,
            isInspectorCollapsed: windowState.isInspectorCollapsed,
            isReferencePaneVisible: !windowState.isInspectorCollapsed,
        ))
    }

    // MARK: - Reference Pane

    private func handleRefPaneShow() -> ControlResponse {
        guard let windowState = windowManager.activeWindowController?.windowState else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        if windowState.isInspectorCollapsed {
            windowState.toggleInspector()
        }
        return .ok("Reference pane shown")
    }

    private func handleRefPaneHide() -> ControlResponse {
        guard let windowState = windowManager.activeWindowController?.windowState else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        if !windowState.isInspectorCollapsed {
            windowState.toggleInspector()
        }
        return .ok("Reference pane hidden")
    }

    private func handleRefPaneToggle() -> ControlResponse {
        guard let windowState = windowManager.activeWindowController?.windowState else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        windowState.toggleInspector()
        let state = windowState.isInspectorCollapsed ? "hidden" : "shown"
        return .ok("Reference pane \(state)")
    }

    // MARK: - Hotkey

    private func handleHotkey(_ params: ControlRequest.HotkeyParams) -> ControlResponse {
        let components = params.keys.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        guard !components.isEmpty else {
            return .error(CTL.ErrorInfo(code: "invalid_params", message: "No keys specified"))
        }

        var flags = CGEventFlags()
        var keyCode: CGKeyCode?

        for component in components {
            switch component {
            case "cmd", "command": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "opt", "option", "alt": flags.insert(.maskAlternate)
            case "ctrl", "control": flags.insert(.maskControl)
            default:
                keyCode = virtualKeyCode(for: component)
                if keyCode == nil {
                    return .error(CTL.ErrorInfo(code: "invalid_key", message: "Unknown key: \(component)"))
                }
            }
        }

        guard let code = keyCode else {
            return .error(CTL.ErrorInfo(code: "invalid_params", message: "No key specified (only modifiers found)"))
        }

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else {
            return .error(CTL.ErrorInfo(code: "event_failed", message: "Failed to create key event"))
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        return .actionResult(CTL.ActionResultInfo(success: true, message: "Sent hotkey \(params.keys)"))
    }

    // MARK: - Sidebar / Inspector / Lens

    private func handleSidebarToggle() -> ControlResponse {
        guard let windowState = windowManager.activeWindowController?.windowState else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        windowState.toggleSidebar()
        let state = windowState.isSidebarCollapsed ? "collapsed" : "expanded"
        return .ok("Sidebar \(state)")
    }

    private func handleInspectorToggle() -> ControlResponse {
        guard let windowState = windowManager.activeWindowController?.windowState else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        windowState.toggleInspector()
        let state = windowState.isInspectorCollapsed ? "collapsed" : "expanded"
        return .ok("Inspector \(state)")
    }

    private func handleCommandLens() -> ControlResponse {
        guard let windowState = windowManager.activeWindowController?.windowState else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        windowState.openCommandLens()
        return .ok("Command lens opened")
    }

    private func handleAddressLens() -> ControlResponse {
        guard let windowState = windowManager.activeWindowController?.windowState else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        windowState.openAddressLens()
        return .ok("Address lens opened")
    }

    // MARK: - Accessibility Tree (AX API)

    /// Uses the macOS Accessibility API (AXUIElement) to traverse the real accessibility tree.
    /// SwiftUI's `.accessibilityIdentifier()` is only exposed through the AX API,
    /// not through the NSView hierarchy.
    private func handleUIAXTree(_ params: ControlRequest.UIAXTreeParams) -> ControlResponse {
        guard let window = windowManager.activeWindowController?.window else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }

        let appElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let windowElement: AXUIElement
        if let found = axFindWindow(app: appElement, windowNumber: window.windowNumber) {
            windowElement = found
        } else {
            return .error(CTL.ErrorInfo(code: "ax_error", message: "Could not find window in AX tree"))
        }

        let root: AXUIElement
        if let targetID = params.id {
            guard let found = axFindElement(byIdentifier: targetID, in: windowElement) else {
                return .error(CTL.ErrorInfo(
                    code: "not_found",
                    message: "No element with identifier '\(targetID)'",
                ))
            }
            root = found
        } else {
            root = windowElement
        }

        var output = ""
        axBuildTree(element: root, depth: 0, maxDepth: params.depth, indent: "", output: &output)
        if output.isEmpty {
            output = "(empty accessibility tree)\n"
        }
        return .javascript(output)
    }

    private func handleUIAXClick(_ params: ControlRequest.UIAXClickParams) -> ControlResponse {
        guard let window = windowManager.activeWindowController?.window else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }

        let appElement = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        guard let windowElement = axFindWindow(app: appElement, windowNumber: window.windowNumber) else {
            return .error(CTL.ErrorInfo(code: "ax_error", message: "Could not find window in AX tree"))
        }

        guard let element = axFindElement(byIdentifier: params.id, in: windowElement) else {
            return .error(CTL.ErrorInfo(
                code: "not_found",
                message: "No element with identifier '\(params.id)'",
            ))
        }

        let pressResult = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if pressResult == .success {
            return .ok("Clicked '\(params.id)' via AX press action")
        }

        // Fall back to synthetic click using element position
        if let pos = axGetPosition(element), let size = axGetSize(element) {
            let centerX = pos.x + size.width / 2
            let centerY = pos.y + size.height / 2
            let location = NSPoint(x: centerX, y: centerY)
            let timestamp = ProcessInfo.processInfo.systemUptime

            if let mouseDown = NSEvent.mouseEvent(
                with: .leftMouseDown, location: location, modifierFlags: [],
                timestamp: timestamp, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1.0,
            ) {
                window.sendEvent(mouseDown)
            }
            if let mouseUp = NSEvent.mouseEvent(
                with: .leftMouseUp, location: location, modifierFlags: [],
                timestamp: timestamp + 0.05, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 0.0,
            ) {
                window.sendEvent(mouseUp)
            }
            return .ok("Clicked '\(params.id)' via synthetic mouse event")
        }

        return .error(CTL.ErrorInfo(
            code: "click_failed",
            message: "Element '\(params.id)' does not support press action and has no position",
        ))
    }

    // MARK: AX API Helpers

    private func axFindWindow(app: AXUIElement, windowNumber: Int) -> AXUIElement? {
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement]
        else { return nil }

        // Match by window number or just return the first
        for win in windows {
            var numValue: CFTypeRef?
            // Try to match by position/title if window number isn't directly accessible
            if windows.count == 1 { return win }

            // AX doesn't directly expose windowNumber, but we can compare titles
            if AXUIElementCopyAttributeValue(win, "_AXWindowNumber" as CFString, &numValue) == .success,
               let num = numValue as? Int, num == windowNumber {
                return win
            }
        }
        return windows.first
    }

    private func axFindElement(byIdentifier identifier: String, in root: AXUIElement) -> AXUIElement? {
        if axGetIdentifier(root) == identifier {
            return root
        }
        for child in axGetChildren(root) {
            if let found = axFindElement(byIdentifier: identifier, in: child) {
                return found
            }
        }
        return nil
    }

    private func axGetChildren(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement]
        else { return [] }
        return children
    }

    private func axGetRole(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success,
              let role = value as? String
        else { return nil }
        return role.hasPrefix("AX") ? String(role.dropFirst(2)) : role
    }

    private func axGetIdentifier(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString, &value) == .success,
              let id = value as? String, !id.isEmpty
        else { return nil }
        return id
    }

    private func axGetLabel(_ element: AXUIElement) -> String? {
        // Try description first (maps to accessibilityLabel in SwiftUI), then title
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &value) == .success,
           let desc = value as? String, !desc.isEmpty {
            return desc
        }
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success,
           let title = value as? String, !title.isEmpty {
            return title
        }
        return nil
    }

    private func axGetValue(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let str = value as? String, !str.isEmpty
        else { return nil }
        return str
    }

    private func axGetPosition(_ element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success
        else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func axGetSize(_ element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success
        else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    private func axBuildTree(
        element: AXUIElement,
        depth: Int,
        maxDepth: Int?,
        indent: String,
        output: inout String,
    ) {
        if let max = maxDepth, depth >= max { return }

        let role = axGetRole(element)
        let id = axGetIdentifier(element)
        let label = axGetLabel(element)
        let value = axGetValue(element)

        let sizeStr = if let size = axGetSize(element) {
            "(\(Int(size.width))x\(Int(size.height)))"
        } else {
            ""
        }

        let hasInfo = id != nil || label != nil || role != nil
        if hasInfo {
            var line = indent
            line += "[\(role ?? "Element")]"
            if let id { line += " id=\"\(id)\"" }
            if let label { line += " \"\(label)\"" }
            if let value, value != label { line += " value=\"\(value)\"" }
            if !sizeStr.isEmpty { line += " \(sizeStr)" }
            output += line + "\n"
        }

        let childIndent = hasInfo ? indent + "  " : indent
        let nextDepth = hasInfo ? depth + 1 : depth
        for child in axGetChildren(element) {
            axBuildTree(
                element: child, depth: nextDepth,
                maxDepth: maxDepth, indent: childIndent, output: &output,
            )
        }
    }

    // MARK: - Tier 1A: Extended Tab Operations

    private func handleTabPin(_ params: ControlRequest.TabIDParams) throws -> ControlResponse {
        let tab = try resolveTabRef(params.id)
        tabManager.togglePinTab(tab)
        let state = tab.isPinned ? "pinned" : "unpinned"
        return .ok("Tab \(state)")
    }

    private func handleTabDuplicate(_ params: ControlRequest.TabIDParams) throws -> ControlResponse {
        let tab = try resolveTabRef(params.id)
        let newTab = tabManager.duplicateTab(tab)
        let activeTabID = windowManager.activeWindowController?.windowState.activeTabID
        return .tab(buildTabInfo(newTab, activeTabID: activeTabID))
    }

    private func handleTabRename(_ params: ControlRequest.TabRenameParams) throws -> ControlResponse {
        let tab = try resolveTabRef(params.id)
        let name = params.name ?? ""
        _ = tabManager.setCustomName(name, for: tab)
        if name.isEmpty {
            return .ok("Tab name cleared")
        }
        return .ok("Tab renamed to '\(name)'")
    }

    private func handleTabMute(_ params: ControlRequest.TabIDParams) throws -> ControlResponse {
        let tab = try resolveTabRef(params.id)
        guard let webPage = pagePool.page(for: tab.activePage) else {
            return .error(CTL.ErrorInfo(code: "no_web_page", message: "Tab has no active web page"))
        }
        webPage.toggleAudioMute()
        let state = webPage.isAudioMuted ? "muted" : "unmuted"
        return .ok("Tab \(state)")
    }

    private func handleTabGoBack(_ params: ControlRequest.OptionalTabIDParams) throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        guard webPage.canGoBack else {
            return .error(CTL.ErrorInfo(code: "no_history", message: "Cannot go back"))
        }
        webPage.goBack()
        return .ok("Navigated back")
    }

    private func handleTabGoForward(_ params: ControlRequest.OptionalTabIDParams) throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        guard webPage.canGoForward else {
            return .error(CTL.ErrorInfo(code: "no_history", message: "Cannot go forward"))
        }
        webPage.goForward()
        return .ok("Navigated forward")
    }

    private func handleTabNext() -> ControlResponse {
        tabManager.selectNextTab()
        return .ok("Switched to next tab")
    }

    private func handleTabPrevious() -> ControlResponse {
        tabManager.selectPreviousTab()
        return .ok("Switched to previous tab")
    }

    private func handleTabDetail(_ params: ControlRequest.OptionalTabIDParams) throws -> ControlResponse {
        let tab = try resolveTab(tabID: params.tabID)

        let webPage = pagePool.existingPage(for: tab.activePage)
        let activeTabID = windowManager.activeWindowController?.windowState.activeTabID

        let pageInfos = tab.sortedPages.map { page in
            let wp = pagePool.existingPage(for: page)
            return CTL.PageInfo(
                id: "\(page.id)",
                url: wp?.url?.absoluteString ?? page.url.absoluteString,
                title: wp?.title ?? page.title,
                position: page.position?.rawValue ?? "unknown",
                isActive: page.id == tab.activePage.id,
            )
        }

        let detail = CTL.TabDetailInfo(
            id: "\(tab.id)",
            title: tab.displayTitle,
            url: webPage?.url?.absoluteString ?? tab.activePage.url.absoluteString,
            isActive: tab.id == activeTabID,
            isLoading: webPage?.isLoading ?? false,
            isPinned: tab.isPinned,
            isUnread: tab.isUnread,
            customName: tab.customName,
            groupID: tab.groupID.map { "\($0)" },
            groupName: tab.group?.name,
            spaceID: tab.space.map { "\($0.id)" },
            isReferenceTab: tab.isReferenceTab,
            canGoBack: webPage?.canGoBack ?? false,
            canGoForward: webPage?.canGoForward ?? false,
            isMuted: webPage?.isAudioMuted ?? false,
            pageCount: tab.pages.count,
            pages: pageInfos,
        )
        return .tabDetail(detail)
    }

    private func handleTabCloseOthers(_ params: ControlRequest.TabIDParams) throws -> ControlResponse {
        let tab = try resolveTabRef(params.id)
        tabManager.closeOtherTabsInSpace(except: tab)
        return .ok("Closed other tabs")
    }

    private func handleTabReopenClosed() -> ControlResponse {
        guard !undoRedoManager.recentlyClosedTabs.isEmpty else {
            return .error(CTL.ErrorInfo(code: "no_closed_tabs", message: "No recently closed tabs"))
        }
        undoRedoManager.reopenLastClosedTab()
        return .ok("Reopened last closed tab")
    }

    private func handleTabRecentlyClosed() -> ControlResponse {
        let entries = undoRedoManager.recentlyClosedTabs.map { info in
            CTL.RecentlyClosedTabInfo(
                title: info.title,
                url: info.url.absoluteString,
                closedAt: ISO8601DateFormatter().string(from: info.closedAt),
            )
        }
        return .recentlyClosedTabs(entries)
    }

    private func handleTabMoveToSpace(_ params: ControlRequest.TabMoveToSpaceParams) throws -> ControlResponse {
        let tab = try resolveTabRef(params.id)
        guard let targetSpace = findSpace(byID: params.spaceID) else {
            return .error(CTL.ErrorInfo(code: "not_found", message: "Space not found: \(params.spaceID)"))
        }
        tabManager.moveTabs([tab], to: targetSpace)
        return .ok("Tab moved to space '\(targetSpace.name)'")
    }

    private func handleTabMoveToGroup(_ params: ControlRequest.TabMoveToGroupParams) throws -> ControlResponse {
        let tab = try resolveTabRef(params.id)
        guard let group = findGroup(byID: params.groupID) else {
            return .error(CTL.ErrorInfo(code: "not_found", message: "Group not found: \(params.groupID)"))
        }
        guard let space = tab.space else {
            return .error(CTL.ErrorInfo(code: "no_space", message: "Tab has no space"))
        }
        groupManager.moveTabToGroup(tab, group: group, in: space, spaceID: space.id)
        return .ok("Tab moved to group '\(group.name)'")
    }

    private func handleTabRemoveFromGroup(_ params: ControlRequest.TabIDParams) throws -> ControlResponse {
        let tab = try resolveTabRef(params.id)
        guard let space = tab.space else {
            return .error(CTL.ErrorInfo(code: "no_space", message: "Tab has no space"))
        }
        groupManager.removeTabFromGroup(tab, in: space, spaceID: space.id)
        return .ok("Tab removed from group")
    }

    private func handleTabMoveToRefPane(_ params: ControlRequest.TabIDParams) throws -> ControlResponse {
        let tab = try resolveTabRef(params.id)
        guard let windowState = windowManager.activeWindowController?.windowState else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        let success = referencePaneManager.moveTabToReferencePane(tab, in: windowState)
        if success {
            return .ok("Tab moved to reference pane")
        }
        return .error(CTL.ErrorInfo(code: "move_failed", message: "Failed to move tab to reference pane"))
    }

    private func handleTabReorder(_ params: ControlRequest.TabReorderParams) throws -> ControlResponse {
        let tab = try resolveTabRef(params.id)
        tabManager.moveTab(tab, to: params.index)
        return .ok("Tab moved to index \(params.index)")
    }

    private func handleTabMarkRead(_ params: ControlRequest.TabIDParams) throws -> ControlResponse {
        let tab = try resolveTabRef(params.id)
        tabManager.markAsRead(tab)
        return .ok("Tab marked as read")
    }

    private func handleTabMarkUnread(_ params: ControlRequest.TabIDParams) throws -> ControlResponse {
        let tab = try resolveTabRef(params.id)
        tabManager.markAsUnread(tab)
        return .ok("Tab marked as unread")
    }

    private func handleTabCopyURL(_ params: ControlRequest.TabCopyURLParams) throws -> ControlResponse {
        let tab = try resolveTabRef(params.id)
        let webPage = pagePool.page(for: tab.activePage)
        let urlString = webPage?.url?.absoluteString ?? tab.activePage.url.absoluteString

        let text: String = if params.markdown == true {
            "[\(tab.displayTitle)](\(urlString))"
        } else {
            urlString
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return .ok("URL copied to clipboard")
    }

    private func handleTabReload(_ params: ControlRequest.TabReloadParams) throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        let fromOrigin = params.fromOrigin ?? false
        _ = webPage.reload(fromOrigin: fromOrigin)
        let mode = fromOrigin ? "Reloading from origin" : "Reloading"
        return .ok(mode)
    }

    private func handleTabIsLoading(_ params: ControlRequest.OptionalTabIDParams) throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        return .ok(webPage.isLoading ? "true" : "false")
    }

    private func handleTabURL(_ params: ControlRequest.OptionalTabIDParams) throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        return .ok(webPage.url?.absoluteString ?? "about:blank")
    }

    private func handleTabWaitLoaded(_ params: ControlRequest.TabWaitLoadedParams) async throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)

        try await waitForPageLoad(webPage, timeout: params.timeout ?? 30)

        let finalURL = webPage.url?.absoluteString ?? "about:blank"
        return .actionResult(CTL.ActionResultInfo(success: true, message: "Page loaded: \(finalURL)"))
    }

    // MARK: - Tier 1B: Tab Group CRUD

    private func handleGroupList(_ params: ControlRequest.GroupListParams) -> ControlResponse {
        let groups: [TabGroup]
        if let spaceIDString = params.spaceID {
            guard let space = findSpace(byID: spaceIDString) else {
                return .error(CTL.ErrorInfo(code: "not_found", message: "Space not found: \(spaceIDString)"))
            }
            groups = groupManager.groups(in: space, spaceID: space.id)
        } else {
            groups = browserState.spaces.flatMap { space in
                groupManager.groups(in: space, spaceID: space.id)
            }
        }

        let infos = groups.map { buildGroupInfo($0) }
        return .groups(infos)
    }

    private func handleGroupCreate(_ params: ControlRequest.GroupCreateParams) throws -> ControlResponse {
        let space: Space
        if let spaceIDString = params.spaceID {
            guard let found = findSpace(byID: spaceIDString) else {
                return .error(CTL.ErrorInfo(code: "not_found", message: "Space not found: \(spaceIDString)"))
            }
            space = found
        } else {
            guard let activeSpace = windowManager.activeWindowController?.windowState.activeSpace else {
                return .error(CTL.ErrorInfo(code: "no_space", message: "No active space"))
            }
            space = activeSpace
        }

        let colorHex = parseColor(params.color ?? "blue").components.taggedString
        let group = try groupManager.createGroup(
            in: space,
            spaceID: space.id,
            name: params.name,
            color: colorHex,
            iconName: params.icon,
            startEditing: false,
        )
        return .group(buildGroupInfo(group))
    }

    private func handleGroupDelete(_ params: ControlRequest.GroupDeleteParams) -> ControlResponse {
        guard let group = findGroup(byID: params.id) else {
            return .error(CTL.ErrorInfo(code: "not_found", message: "Group not found: \(params.id)"))
        }
        guard let space = group.space else {
            return .error(CTL.ErrorInfo(code: "no_space", message: "Group has no space"))
        }
        let closeTabs = params.closeTabs ?? false
        groupManager.deleteGroup(group, in: space, spaceID: space.id, deleteContainedTabs: closeTabs)
        return .ok("Group deleted")
    }

    private func handleGroupRename(_ params: ControlRequest.GroupRenameParams) -> ControlResponse {
        guard let group = findGroup(byID: params.id) else {
            return .error(CTL.ErrorInfo(code: "not_found", message: "Group not found: \(params.id)"))
        }
        groupManager.renameGroup(group, to: params.name)
        return .ok("Group renamed to '\(params.name)'")
    }

    private func handleGroupSetColor(_ params: ControlRequest.GroupSetColorParams) -> ControlResponse {
        guard let group = findGroup(byID: params.id) else {
            return .error(CTL.ErrorInfo(code: "not_found", message: "Group not found: \(params.id)"))
        }
        let colorHex = parseColor(params.color).components.taggedString
        groupManager.updateGroupColor(group, to: colorHex)
        return .ok("Group color set to '\(params.color)'")
    }

    private func handleGroupSetIcon(_ params: ControlRequest.GroupSetIconParams) -> ControlResponse {
        guard let group = findGroup(byID: params.id) else {
            return .error(CTL.ErrorInfo(code: "not_found", message: "Group not found: \(params.id)"))
        }
        groupManager.updateGroupIcon(group, to: params.icon)
        return .ok("Group icon set to '\(params.icon)'")
    }

    private func handleGroupToggleCollapsed(_ params: ControlRequest.GroupToggleCollapsedParams) -> ControlResponse {
        guard let group = findGroup(byID: params.id) else {
            return .error(CTL.ErrorInfo(code: "not_found", message: "Group not found: \(params.id)"))
        }
        groupManager.toggleGroupCollapsed(group)
        let state = group.isCollapsed ? "collapsed" : "expanded"
        return .ok("Group \(state)")
    }

    // MARK: - Tier 1C: Page Operations

    private func handlePageZoomIn(_ params: ControlRequest.OptionalTabIDParams) throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        webPage.zoomIn()
        return .ok("Zoomed in")
    }

    private func handlePageZoomOut(_ params: ControlRequest.OptionalTabIDParams) throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        webPage.zoomOut()
        return .ok("Zoomed out")
    }

    private func handlePageZoomReset(_ params: ControlRequest.OptionalTabIDParams) throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        webPage.resetZoom()
        return .ok("Zoom reset")
    }

    private func handlePageFind(_ params: ControlRequest.PageFindParams) async throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        let escapedQuery = params.query.replacingOccurrences(of: "'", with: "\\'")
        try await webPage.callJavaScript("window.find('\(escapedQuery)')")
        return .ok("Find initiated for '\(params.query)'")
    }

    private func handlePageFindNext(_ params: ControlRequest.OptionalTabIDParams) async throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        try await webPage.callJavaScript("window.find('', false, false, true)")
        return .ok("Find next")
    }

    private func handlePageFindPrevious(_ params: ControlRequest.OptionalTabIDParams) async throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        try await webPage.callJavaScript("window.find('', false, true, true)")
        return .ok("Find previous")
    }

    private func handlePageFindDismiss(_ params: ControlRequest.OptionalTabIDParams) throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        webPage.backingWebView._hideFindUI()
        return .ok("Find dismissed")
    }

    private func handlePageExecJS(_ params: ControlRequest.PageExecJSParams) async throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)

        if params.noGesture == true {
            // Without-gesture evaluation takes a plain expression/program, not a
            // function body — no return-wrapping. Preserves the page's transient
            // user activation.
            do {
                let result = try await webPage.evaluateJavaScriptWithoutUserGesture(params.script)
                let resultString = result.map { "\($0)" } ?? "undefined"
                return .javascript(resultString)
            } catch let error as NSError where error.domain == "WKErrorDomain" {
                let jsMessage = error.userInfo["WKJavaScriptExceptionMessage"] as? String
                    ?? error.localizedDescription
                return .error(CTL.ErrorInfo(code: "javascript_error", message: jsMessage))
            }
        }

        // callAsyncJavaScript treats the string as a function body, so expressions
        // like "document.title" need an explicit `return` to produce a value.
        // Auto-wrap scripts that don't contain a return statement.
        let script = if params.script.contains("return ") || params.script.contains("return\n") {
            params.script
        } else {
            "return \(params.script)"
        }
        do {
            let result = try await webPage.callJavaScript(script)
            let resultString = result.map { "\($0)" } ?? "undefined"
            return .javascript(resultString)
        } catch let error as NSError where error.domain == "WKErrorDomain" {
            // Extract the actual JS exception message from WKError userInfo
            let jsMessage = error.userInfo["WKJavaScriptExceptionMessage"] as? String
                ?? error.localizedDescription
            let jsLine = error.userInfo["WKJavaScriptExceptionLineNumber"] as? Int
            let jsColumn = error.userInfo["WKJavaScriptExceptionColumnNumber"] as? Int
            var detail = jsMessage
            if let line = jsLine {
                detail += " (line \(line)"
                if let col = jsColumn { detail += ", col \(col)" }
                detail += ")"
            }
            return .error(CTL.ErrorInfo(code: "javascript_error", message: detail))
        }
    }

    private func handlePageVideoViewer(_ params: ControlRequest.PageVideoViewerParams) async throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)

        func statusLine() async -> String {
            await webPage.refreshPlaybackState()
            return "active: \(webPage.isInWindowVideoActive), "
                + "canToggle: \(webPage.canToggleInWindowVideo), "
                + "fullscreenState: \(webPage.fullscreenState), "
                + "mediaPlaying: \(webPage.isMediaPlaying), "
                + "inWindowFullscreen: \(webPage.inWindowFullscreenController.map { "\($0.isActive)" } ?? "client-off")"
        }

        switch params.action {
        case .status:
            return await .ok(statusLine())
        case .enter, .exit, .toggle:
            let before = await statusLine()
            switch params.action {
            case .enter: webPage.enterInWindowVideo()
            case .exit: webPage.exitInWindowVideo()
            case .toggle: webPage.toggleInWindowVideo()
            case .status: break
            }
            // The mode change round-trips through the web process; give it a moment
            // so the after-state reflects the result. The viewer needs an active
            // playback session (a video that has started playing) — without one the
            // SPI is a silent no-op and the state will not change.
            try? await Task.sleep(for: .milliseconds(400))
            let after = await statusLine()
            return .ok("Video viewer \(params.action.rawValue): before [\(before)] → after [\(after)]")
        }
    }

    private func handlePageSource(_ params: ControlRequest.OptionalTabIDParams) async throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        let result = try await webPage.callJavaScript("return document.documentElement.outerHTML")
        let html = result as? String ?? ""
        return .pageContent(html)
    }

    // MARK: - Tier 1D: Reference Pane Extended

    private func handleRefPaneAddTab(_ params: ControlRequest.RefPaneAddTabParams) -> ControlResponse {
        guard let url = URL(string: params.url) else {
            return .error(CTL.ErrorInfo(code: "invalid_url", message: "Invalid URL: \(params.url)"))
        }
        guard let windowState = windowManager.activeWindowController?.windowState,
              let space = windowState.activeSpace else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window or space"))
        }

        let title = params.title ?? "New Tab"
        guard let tab = referencePaneManager.addReferenceTab(url: url, title: title, in: space, windowState: windowState) else {
            return .error(CTL.ErrorInfo(code: "limit_reached", message: "Reference pane tab limit reached"))
        }

        let activeTabID = windowState.activeTabID
        return .tab(buildTabInfo(tab, activeTabID: activeTabID))
    }

    private func handleRefPaneCloseTab(_ params: ControlRequest.RefPaneCloseTabParams) -> ControlResponse {
        guard let tab = findReferenceTab(byID: params.id) else {
            return .error(CTL.ErrorInfo(code: "not_found", message: "Reference tab not found: \(params.id)"))
        }
        referencePaneManager.closeReferenceTab(tab)
        return .ok("Reference tab closed")
    }

    private func handleRefPaneListTabs() -> ControlResponse {
        guard let windowState = windowManager.activeWindowController?.windowState,
              let space = windowState.activeSpace else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window or space"))
        }

        let activeRefTabID = windowState.activeReferenceTabID
        let tabs = space.referenceTabs.map { tab in
            CTL.RefPaneTabInfo(
                id: "\(tab.id)",
                title: tab.displayTitle,
                url: pagePool.existingPage(for: tab.activePage)?.url?.absoluteString ?? tab.activePage.url.absoluteString,
                isActive: tab.id == activeRefTabID,
            )
        }
        return .refPaneTabs(tabs)
    }

    private func handleRefPaneActivateTab(_ params: ControlRequest.RefPaneActivateTabParams) -> ControlResponse {
        guard let tab = findReferenceTab(byID: params.id) else {
            return .error(CTL.ErrorInfo(code: "not_found", message: "Reference tab not found: \(params.id)"))
        }
        guard let windowState = windowManager.activeWindowController?.windowState else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        referencePaneManager.setActiveReferenceTab(tab, in: windowState)
        return .ok("Reference tab activated")
    }

    private func handleRefPaneMoveToMain(_ params: ControlRequest.RefPaneMoveToMainParams) -> ControlResponse {
        guard let tab = findReferenceTab(byID: params.id) else {
            return .error(CTL.ErrorInfo(code: "not_found", message: "Reference tab not found: \(params.id)"))
        }
        guard let space = tab.space else {
            return .error(CTL.ErrorInfo(code: "no_space", message: "Tab has no space"))
        }
        let insertionIndex = space.mainTabs.count
        let success = referencePaneManager.moveReferenceTabToMainArea(tab, insertionIndex: insertionIndex) { _ in }
        if success {
            return .ok("Reference tab moved to main area")
        }
        return .error(CTL.ErrorInfo(code: "move_failed", message: "Failed to move reference tab to main area"))
    }

    // MARK: - Tier 1E: Visual Agent Features

    private func handleVisualHighlight(_ params: ControlRequest.VisualHighlightParams) async throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: nil, pageID: nil)
        let webView = webPage.backingWebView
        let url = webPage.url ?? .blank
        let title = webPage.title
        let tree = try await PageContentExtractor.extract(from: webView, url: url, title: title)

        guard let node = tree.findNode(byRef: params.ref) else {
            return .error(CTL.ErrorInfo(code: "not_found", message: "Element ref '\(params.ref)' not found"))
        }

        let style: HighlightStyle = switch params.style?.lowercased() {
        case "reading": .reading
        case "acting", "aboutToAct": .aboutToAct
        default: .standard
        }

        visualFeedbackManager.activate()
        visualFeedbackManager.highlightElement(rect: node.rect, style: style)
        return .ok("Highlighted element '\(params.ref)'")
    }

    private func handleVisualCursor(_ params: ControlRequest.VisualCursorParams) -> ControlResponse {
        let point = CGPoint(x: params.x, y: params.y)
        guard let window = windowManager.activeWindowController?.window else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        let bounds = window.contentView?.bounds ?? window.frame
        visualFeedbackManager.activate()
        visualFeedbackManager.moveCursor(to: point, in: bounds)
        return .ok("Cursor moved to (\(Int(params.x)), \(Int(params.y)))")
    }

    private func handleVisualClick(_ params: ControlRequest.VisualClickParams) async throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: nil, pageID: nil)
        let webView = webPage.backingWebView
        let url = webPage.url ?? .blank
        let title = webPage.title
        let tree = try await PageContentExtractor.extract(from: webView, url: url, title: title)

        guard let node = tree.findNode(byRef: params.ref) else {
            return .error(CTL.ErrorInfo(code: "not_found", message: "Element ref '\(params.ref)' not found"))
        }

        visualFeedbackManager.activate()
        visualFeedbackManager.highlightElement(rect: node.rect, style: .aboutToAct)

        // Perform the click after visual feedback
        if let nativeID = node.nativeID {
            let interaction = _WKTextExtractionInteraction(action: .click)
            interaction.nodeIdentifier = nativeID
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                webView._performInteraction(interaction) { result in
                    if let error = result.error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } else {
            let centerX = node.rect.midX
            let centerY = node.rect.midY
            try await webPage.callJavaScript("document.elementFromPoint(\(centerX), \(centerY))?.click()")
        }

        return .actionResult(CTL.ActionResultInfo(success: true, message: "Visual click on '\(params.ref)'"))
    }

    private func handleVisualScrollTo(_ params: ControlRequest.VisualScrollToParams) async throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: nil, pageID: nil)

        if let ref = params.ref {
            let webView = webPage.backingWebView
            let url = webPage.url ?? .blank
            let title = webPage.title
            let tree = try await PageContentExtractor.extract(from: webView, url: url, title: title)

            guard let node = tree.findNode(byRef: ref) else {
                return .error(CTL.ErrorInfo(code: "not_found", message: "Element ref '\(ref)' not found"))
            }

            try await webPage.callJavaScript("window.scrollTo(0, \(node.rect.origin.y))")
            return .ok("Scrolled to element '\(ref)'")
        }

        if let y = params.y {
            try await webPage.callJavaScript("window.scrollTo(0, \(y))")
            return .ok("Scrolled to y=\(Int(y))")
        }

        return .error(CTL.ErrorInfo(code: "invalid_params", message: "scrollTo requires either 'ref' or 'y'"))
    }

    private func handleVisualClear() -> ControlResponse {
        visualFeedbackManager.clearHighlights()
        visualFeedbackManager.deactivate()
        return .ok("Visual feedback cleared")
    }

    // MARK: - Tier 2A: Bookmarks

    private func handleBookmarkList(_ params: ControlRequest.BookmarkListParams) -> ControlResponse {
        let bookmarks: [Bookmark]

        if let query = params.query {
            bookmarks = bookmarksManager.search(query: query)
        } else if let folderIDString = params.folderID, let folderID = UUID(uuidString: folderIDString) {
            if let folder = bookmarksManager.folder(for: folderID) {
                bookmarks = bookmarksManager.bookmarks(in: folder)
            } else {
                return .error(CTL.ErrorInfo(code: "not_found", message: "Folder not found: \(folderIDString)"))
            }
        } else {
            bookmarks = bookmarksManager.allBookmarks()
        }

        let infos = bookmarks.map { bookmark in
            CTL.BookmarkInfo(
                id: "\(bookmark.id)",
                title: bookmark.title,
                url: bookmark.url.absoluteString,
                folderID: bookmark.folderID.map { "\($0)" },
                isFavorite: bookmark.isFavorite,
                dateAdded: ISO8601DateFormatter().string(from: bookmark.createdAt),
            )
        }
        return .bookmarks(infos)
    }

    private func handleBookmarkCreate(_ params: ControlRequest.BookmarkCreateParams) -> ControlResponse {
        guard let url = URL(string: params.url) else {
            return .error(CTL.ErrorInfo(code: "invalid_url", message: "Invalid URL: \(params.url)"))
        }

        var folder: BookmarkFolder?
        if let folderIDString = params.folderID, let folderID = UUID(uuidString: folderIDString) {
            folder = bookmarksManager.folder(for: folderID)
            if folder == nil {
                return .error(CTL.ErrorInfo(code: "not_found", message: "Folder not found: \(folderIDString)"))
            }
        }

        let bookmark = bookmarksManager.createBookmark(
            url: url,
            title: params.title ?? url.host ?? url.absoluteString,
            folder: folder,
            isFavorite: params.favorite ?? false,
        )
        let info = CTL.BookmarkInfo(
            id: "\(bookmark.id)",
            title: bookmark.title,
            url: bookmark.url.absoluteString,
            folderID: bookmark.folderID.map { "\($0)" },
            isFavorite: bookmark.isFavorite,
            dateAdded: ISO8601DateFormatter().string(from: bookmark.createdAt),
        )
        return .bookmarks([info])
    }

    private func handleBookmarkDelete(_ params: ControlRequest.BookmarkDeleteParams) -> ControlResponse {
        guard let id = UUID(uuidString: params.id),
              let bookmark = bookmarksManager.bookmark(for: id) else {
            return .error(CTL.ErrorInfo(code: "not_found", message: "Bookmark not found: \(params.id)"))
        }
        bookmarksManager.deleteBookmark(bookmark)
        return .ok("Bookmark deleted")
    }

    private func handleBookmarkFavorite(_ params: ControlRequest.BookmarkFavoriteParams) -> ControlResponse {
        guard let id = UUID(uuidString: params.id),
              let bookmark = bookmarksManager.bookmark(for: id) else {
            return .error(CTL.ErrorInfo(code: "not_found", message: "Bookmark not found: \(params.id)"))
        }
        bookmarksManager.addToFavorites(bookmark)
        return .ok("Bookmark added to favorites")
    }

    private func handleBookmarkUnfavorite(_ params: ControlRequest.BookmarkUnfavoriteParams) -> ControlResponse {
        guard let id = UUID(uuidString: params.id),
              let bookmark = bookmarksManager.bookmark(for: id) else {
            return .error(CTL.ErrorInfo(code: "not_found", message: "Bookmark not found: \(params.id)"))
        }
        bookmarksManager.removeFromFavorites(bookmark)
        return .ok("Bookmark removed from favorites")
    }

    private func handleBookmarkFolderList() -> ControlResponse {
        let folders = bookmarksManager.rootFolders()
        let infos = folders.map { folder in
            CTL.BookmarkFolderInfo(
                id: "\(folder.id)",
                name: folder.name,
                parentID: folder.parentFolderID.map { "\($0)" },
                bookmarkCount: folder.bookmarks.count,
            )
        }
        return .bookmarkFolders(infos)
    }

    private func handleBookmarkFolderCreate(_ params: ControlRequest.BookmarkFolderCreateParams) throws -> ControlResponse {
        var parent: BookmarkFolder?
        if let parentIDString = params.parentID, let parentID = UUID(uuidString: parentIDString) {
            parent = bookmarksManager.folder(for: parentID)
            if parent == nil {
                return .error(CTL.ErrorInfo(code: "not_found", message: "Parent folder not found: \(parentIDString)"))
            }
        }

        let folder = try bookmarksManager.createFolder(name: params.name, parent: parent)
        let info = CTL.BookmarkFolderInfo(
            id: "\(folder.id)",
            name: folder.name,
            parentID: folder.parentFolderID.map { "\($0)" },
            bookmarkCount: 0,
        )
        return .bookmarkFolders([info])
    }

    // MARK: - Tier 2B: History

    private func handleHistoryList(_ params: ControlRequest.HistoryListParams) async -> ControlResponse {
        let entries: [HistoryEntryData] = if let domain = params.domain {
            await historyManager.entries(forDomain: domain)
        } else {
            await historyManager.mostVisited(limit: params.limit ?? 50)
        }

        let infos = entries.map { entry in
            CTL.HistoryEntryInfo(
                id: "\(entry.id)",
                title: entry.title ?? entry.url.absoluteString,
                url: entry.url.absoluteString,
                lastVisited: ISO8601DateFormatter().string(from: entry.visitedAt),
                visitCount: 1,
            )
        }
        return .historyEntries(infos)
    }

    private func handleHistorySearch(_ params: ControlRequest.HistorySearchParams) async -> ControlResponse {
        let entries = await historyManager.search(query: params.query, limit: params.limit ?? 50)

        let infos = entries.map { entry in
            CTL.HistoryEntryInfo(
                id: "\(entry.id)",
                title: entry.title ?? entry.url.absoluteString,
                url: entry.url.absoluteString,
                lastVisited: ISO8601DateFormatter().string(from: entry.visitedAt),
                visitCount: 1,
            )
        }
        return .historyEntries(infos)
    }

    private func handleHistoryClear(_ params: ControlRequest.HistoryClearParams) -> ControlResponse {
        if let domain = params.domain {
            historyManager.deleteEntries(forDomain: domain)
            return .ok("History cleared for domain '\(domain)'")
        }
        historyManager.clearAllHistory()
        return .ok("All history cleared")
    }

    private func handleHistoryFrequent(_ params: ControlRequest.HistoryFrequentParams) -> ControlResponse {
        let limit = params.limit ?? 10
        let destinations = historyManager.frequentDestinations.topDestinations(limit: limit)

        let infos = destinations.map { dest in
            CTL.HistoryEntryInfo(
                id: "\(dest.id)",
                title: dest.displayTitle,
                url: dest.url.absoluteString,
                lastVisited: ISO8601DateFormatter().string(from: dest.lastVisited),
                visitCount: dest.visitCount,
            )
        }
        return .historyEntries(infos)
    }

    // MARK: - Tier 2C: Space CRUD

    private func handleSpaceCreate(_ params: ControlRequest.SpaceCreateParams) -> ControlResponse {
        let color = parseColor(params.color)
        let space = spaceManager.createSpace(
            name: params.name,
            color: color,
            iconName: params.icon ?? "folder.fill",
        )
        let activeSpaceID = windowManager.activeWindowController?.windowState.activeSpaceID
        return .spaces([buildSpaceInfo(space, activeSpaceID: activeSpaceID)])
    }

    private func handleSpaceUpdate(_ params: ControlRequest.SpaceUpdateParams) -> ControlResponse {
        guard let space = findSpace(byID: params.id) else {
            return .error(CTL.ErrorInfo(code: "not_found", message: "Space not found: \(params.id)"))
        }
        let color: Color? = params.color != nil ? parseColor(params.color) : nil
        spaceManager.updateSpace(space, name: params.name, color: color)
        return .ok("Space updated")
    }

    private func handleSpaceDelete(_ params: ControlRequest.SpaceDeleteParams) -> ControlResponse {
        guard let space = findSpace(byID: params.id) else {
            return .error(CTL.ErrorInfo(code: "not_found", message: "Space not found: \(params.id)"))
        }
        guard browserState.spaces.count > 1 else {
            return .error(CTL.ErrorInfo(code: "last_space", message: "Cannot delete the last space"))
        }
        let windowState = windowManager.activeWindowController?.windowState
        spaceManager.deleteSpace(space, closeTabs: true, windowState: windowState)
        return .ok("Space deleted")
    }

    // MARK: - Tier 2D: Window Extended

    private func handleWindowKeepOnTop() -> ControlResponse {
        guard let window = windowManager.activeWindowController?.window else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        let isOnTop = window.level == .floating
        window.level = isOnTop ? .normal : .floating
        let state = isOnTop ? "normal" : "floating"
        return .ok("Window level set to \(state)")
    }

    private func handleWindowAllDesktops() -> ControlResponse {
        guard let window = windowManager.activeWindowController?.window else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        let isOnAll = window.collectionBehavior.contains(.canJoinAllSpaces)
        if isOnAll {
            window.collectionBehavior.remove(.canJoinAllSpaces)
        } else {
            window.collectionBehavior.insert(.canJoinAllSpaces)
        }
        let state = isOnAll ? "current desktop" : "all desktops"
        return .ok("Window visible on \(state)")
    }

    private func handleWindowLockSize() -> ControlResponse {
        guard let window = windowManager.activeWindowController?.window else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        let isResizable = window.styleMask.contains(.resizable)
        if isResizable {
            window.styleMask.remove(.resizable)
        } else {
            window.styleMask.insert(.resizable)
        }
        let state = isResizable ? "locked" : "unlocked"
        return .ok("Window size \(state)")
    }

    private func handleWindowSetOpacity(_ params: ControlRequest.WindowSetOpacityParams) -> ControlResponse {
        guard let window = windowManager.activeWindowController?.window else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        let clamped = min(max(params.percent, 10), 100)
        window.alphaValue = CGFloat(clamped) / 100.0
        return .ok("Window opacity set to \(clamped)%")
    }

    private func handleWindowFullScreen() -> ControlResponse {
        guard let window = windowManager.activeWindowController?.window else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        window.toggleFullScreen(nil)
        return .ok("Toggled full screen")
    }

    private func handleWindowMinimize() -> ControlResponse {
        guard let window = windowManager.activeWindowController?.window else {
            return .error(CTL.ErrorInfo(code: "no_window", message: "No active window"))
        }
        window.miniaturize(nil)
        return .ok("Window minimized")
    }

    // MARK: - Tier 2E: Site Settings

    private func handleSiteSettingsGet(_ params: ControlRequest.SiteSettingsGetParams) -> ControlResponse {
        let settings = siteSettingsManager.settings(for: params.domain)
        let info = CTL.SiteSettingsInfo(
            domain: params.domain,
            zoom: settings?.pageZoom,
            javascript: settings?.allowJavaScript,
            contentBlockers: settings?.enableContentBlockers,
        )
        return .siteSettings(info)
    }

    private func handleSiteSettingsSet(_ params: ControlRequest.SiteSettingsSetParams) -> ControlResponse {
        let settings = siteSettingsManager.settingsOrCreate(for: params.domain)
        if let zoom = params.zoom {
            settings.pageZoom = zoom
        }
        if let javascript = params.javascript {
            settings.allowJavaScript = javascript
        }
        if let contentBlockers = params.contentBlockers {
            settings.enableContentBlockers = contentBlockers
        }
        siteSettingsManager.save(settings)
        return .ok("Site settings updated for '\(params.domain)'")
    }

    // MARK: - Tier 2F: Developer Tools

    private func handleDevInspector(_ params: ControlRequest.DevInspectorParams) throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        let tabPageID = webPage.tabPage.id
        let webView = webPage.backingWebView
        let action = params.action?.lowercased() ?? "toggle"

        switch action {
        case "show", "open":
            let attached = params.side != "detached"
            webInspectorManager.showInspector(for: tabPageID, webView: webView, attached: attached)
        case "close", "hide":
            webInspectorManager.closeInspector(for: tabPageID, webView: webView)
        case "attach":
            let side: WebInspectorManager.AttachmentSide = params.side == "right" ? .right : .bottom
            webInspectorManager.attachInspector(for: tabPageID, webView: webView, side: side)
        case "detach":
            webInspectorManager.detachInspector(for: tabPageID, webView: webView)
        default:
            let attached = params.side != "detached"
            webInspectorManager.toggleInspector(for: tabPageID, webView: webView, attached: attached)
        }

        return .ok("Inspector \(action)")
    }

    private func handleDevConsole(_ params: ControlRequest.OptionalTabIDParams) throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        webInspectorManager.showJavaScriptConsole(for: webPage.tabPage.id, webView: webPage.backingWebView)
        return .ok("JavaScript console opened")
    }

    private func handleDevResources(_ params: ControlRequest.OptionalTabIDParams) throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        webInspectorManager.showPageResources(for: webPage.tabPage.id, webView: webPage.backingWebView)
        return .ok("Page resources opened")
    }

    private func handleDevProfiling(_ params: ControlRequest.OptionalTabIDParams) throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        webInspectorManager.togglePageProfiling(for: webPage.tabPage.id, webView: webPage.backingWebView)
        return .ok("Page profiling toggled")
    }

    private func handleDevElementSelection(_ params: ControlRequest.OptionalTabIDParams) throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        webInspectorManager.toggleElementSelection(for: webPage.tabPage.id, webView: webPage.backingWebView)
        return .ok("Element selection toggled")
    }

    private func handleDevEmptyCaches() async -> ControlResponse {
        // Empty all WebKit caches for all web views
        let dataTypes: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
        await WKWebsiteDataStore.default().removeData(ofTypes: dataTypes, modifiedSince: .distantPast)
        return .ok("Caches emptied")
    }

    private func handleDevConsoleLog(_: ControlRequest.DevConsoleLogParams) -> ControlResponse {
        // Console message capture not yet available via WebKit API
        .ok("Not yet implemented: console log capture requires WebKit inspector integration")
    }

    private func handleDevNetworkLog(_: ControlRequest.DevNetworkLogParams) -> ControlResponse {
        // Network log capture not yet available via WebKit API
        .ok("Not yet implemented: network log capture requires WebKit inspector integration")
    }

    private func handleDevCookies(_ params: ControlRequest.DevCookiesParams) async throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        let result = try await webPage.callJavaScript("return document.cookie")
        let cookieString = result as? String ?? ""

        guard !cookieString.isEmpty else {
            return .cookies([])
        }

        let cookies = cookieString.split(separator: ";").map { pair in
            let parts = pair.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
            let name = String(parts.first ?? "")
            let value = parts.count > 1 ? String(parts[1]) : ""
            return CTL.CookieInfo(
                name: name,
                value: value,
                domain: webPage.url?.host ?? "",
                path: "/",
                isSecure: false,
                isHTTPOnly: false,
                expiresDate: nil,
            )
        }
        return .cookies(cookies)
    }

    private func handleDevStorage(_ params: ControlRequest.DevStorageParams) async throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        let storageType = params.storageType?.lowercased() ?? "local"
        let storageObj = storageType == "session" ? "sessionStorage" : "localStorage"

        switch params.action?.lowercased() {
        case "set":
            guard let key = params.key, let value = params.value else {
                return .error(CTL.ErrorInfo(code: "invalid_params", message: "set requires 'key' and 'value'"))
            }
            let escapedKey = key.replacingOccurrences(of: "'", with: "\\'")
            let escapedValue = value.replacingOccurrences(of: "'", with: "\\'")
            try await webPage.callJavaScript("\(storageObj).setItem('\(escapedKey)', '\(escapedValue)')")
            return .ok("Storage item set")

        case "remove":
            guard let key = params.key else {
                return .error(CTL.ErrorInfo(code: "invalid_params", message: "remove requires 'key'"))
            }
            let escapedKey = key.replacingOccurrences(of: "'", with: "\\'")
            try await webPage.callJavaScript("\(storageObj).removeItem('\(escapedKey)')")
            return .ok("Storage item removed")

        case "clear":
            try await webPage.callJavaScript("\(storageObj).clear()")
            return .ok("Storage cleared")

        default:
            // List all storage entries
            let script = """
            var result = [];
            for (var i = 0; i < \(storageObj).length; i++) {
                var key = \(storageObj).key(i);
                result.push({key: key, value: \(storageObj).getItem(key)});
            }
            return JSON.stringify(result);
            """
            let resultString = try await webPage.callJavaScript(script) as? String ?? "[]"

            guard let data = resultString.data(using: .utf8),
                  let items = try? JSONDecoder().decode([[String: String]].self, from: data) else {
                return .storageEntries([])
            }

            let entries = items.map { item in
                CTL.StorageEntry(
                    key: item["key"] ?? "",
                    value: item["value"] ?? "",
                )
            }
            return .storageEntries(entries)
        }
    }

    // MARK: - Tier 3: Interaction Enhancements

    private func handleHover(_ params: ControlRequest.HoverParams) async throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)

        if let ref = params.ref {
            let webView = webPage.backingWebView
            let url = webPage.url ?? .blank
            let title = webPage.title
            let tree = try await PageContentExtractor.extract(from: webView, url: url, title: title)

            guard let node = tree.findNode(byRef: ref) else {
                return .error(CTL.ErrorInfo(code: "not_found", message: "Element ref '\(ref)' not found"))
            }

            try await scrollElementIntoView(rect: node.rect, webPage: webPage)

            let x = node.rect.midX
            let y = node.rect.midY
            try await webPage.callJavaScript("""
            var el = document.elementFromPoint(\(x), \(y));
            if (el) {
                el.dispatchEvent(new MouseEvent('mouseenter', {bubbles: false, clientX: \(x), clientY: \(y)}));
                el.dispatchEvent(new MouseEvent('mouseover', {bubbles: true, clientX: \(x), clientY: \(y)}));
            }
            """)
            return .actionResult(CTL.ActionResultInfo(success: true, message: "Hovered \(ref)"))
        }

        if let x = params.x, let y = params.y {
            try await webPage.callJavaScript("""
            var el = document.elementFromPoint(\(x), \(y));
            if (el) {
                el.dispatchEvent(new MouseEvent('mouseenter', {bubbles: false, clientX: \(x), clientY: \(y)}));
                el.dispatchEvent(new MouseEvent('mouseover', {bubbles: true, clientX: \(x), clientY: \(y)}));
            }
            """)
            return .actionResult(CTL.ActionResultInfo(success: true, message: "Hovered at (\(Int(x)), \(Int(y)))"))
        }

        return .error(CTL.ErrorInfo(code: "invalid_params", message: "Hover requires either 'ref' or 'x'/'y' coordinates"))
    }

    private func handleFormInput(_ params: ControlRequest.FormInputParams) async throws -> ControlResponse {
        // Handle frame-prefixed refs
        if let frameRef = PageContentTree.parseFrameRef(params.ref) {
            return try await handleFrameType(
                frameRef: frameRef,
                text: params.value,
                tabID: params.tabID,
                pageID: params.pageID,
            )
        }

        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        let webView = webPage.backingWebView
        let url = webPage.url ?? .blank
        let title = webPage.title
        let tree = try await PageContentExtractor.extract(from: webView, url: url, title: title)

        guard let node = tree.findNode(byRef: params.ref) else {
            return .error(CTL.ErrorInfo(code: "not_found", message: "Element ref '\(params.ref)' not found"))
        }

        // Scroll into view first
        try await scrollElementIntoView(rect: node.rect, webPage: webPage)

        let x = node.rect.midX
        let y = node.rect.midY
        let escapedValue = params.value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        // Use the native prototype setter to bypass React/framework value interceptors,
        // then dispatch input + change events so frameworks pick up the new value.
        try await webPage.callJavaScript("""
        var el = document.elementFromPoint(\(x), \(y));
        if (el) {
            if (el.type === 'checkbox' || el.type === 'radio') {
                el.checked = ('\(escapedValue)' === 'true' || '\(escapedValue)' === '1');
            } else if (el.tagName === 'SELECT') {
                el.value = '\(escapedValue)';
            } else {
                var nativeSetter = Object.getOwnPropertyDescriptor(
                    window.HTMLInputElement.prototype, 'value'
                )?.set || Object.getOwnPropertyDescriptor(
                    window.HTMLTextAreaElement.prototype, 'value'
                )?.set;
                if (nativeSetter) {
                    nativeSetter.call(el, '\(escapedValue)');
                } else {
                    el.value = '\(escapedValue)';
                }
            }
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
            el.blur();
        }
        """)
        return .actionResult(CTL.ActionResultInfo(success: true, message: "Set value on \(params.ref)"))
    }

    // MARK: - Helpers

    /// Polls until the web page finishes loading or the timeout expires.
    private func waitForPageLoad(_ webPage: WebPage, timeout: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(timeout)

        while webPage.isLoading {
            if ContinuousClock.now > deadline {
                throw ControlError.timeout("Wait timed out after \(timeout)s")
            }
            if Task.isCancelled { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Whether `_WKTextExtractionInteraction` supports the `scrollToVisible` property.
    /// Checked once at runtime since the property exists in WebKit source but may not
    /// have shipped in the current macOS version yet.
    private static let supportsScrollToVisible: Bool = {
        let probe = _WKTextExtractionInteraction(action: .click)
        return probe.responds(to: Selector(("setScrollToVisible:")))
    }()

    /// Scrolls an element into view using the element's viewport rect.
    /// Uses JavaScript `scrollIntoView` via `elementFromPoint` at the element's center.
    private func scrollElementIntoView(rect: CGRect, webPage: WebPage) async throws {
        let x = rect.midX
        let y = rect.midY
        try await webPage.callJavaScript("""
        var el = document.elementFromPoint(\(x), \(y));
        if (el) el.scrollIntoView({behavior: 'smooth', block: 'center', inline: 'center'});
        """)
    }

    /// Maps WebKit interaction errors to user-actionable messages.
    private func mapWebKitError(_ error: any Error) -> String {
        let nsError = error as NSError
        if nsError.domain == "WKErrorDomain" || nsError.domain == "WebKitErrorDomain" {
            switch nsError.code {
            case 1:
                return "Element not interactable — may be obscured, disabled, or in a cross-origin iframe"
            case 4:
                return "Element not found in page"
            default:
                return "WebKit error \(nsError.code): \(nsError.localizedDescription)"
            }
        }
        return error.localizedDescription
    }

    /// Builds a ``TabInfo`` from a ``Tab`` model.
    private func buildTabInfo(_ tab: Tab, activeTabID: Tab.ID?) -> CTL.TabInfo {
        let webPage = pagePool.existingPage(for: tab.activePage)
        return CTL.TabInfo(
            id: "\(tab.id)",
            title: tab.displayTitle,
            url: webPage?.url?.absoluteString ?? tab.activePage.url.absoluteString,
            isActive: tab.id == activeTabID,
            spaceID: tab.space.map { "\($0.id)" },
            isLoading: webPage?.isLoading ?? false,
            isPinned: tab.isPinned,
            isUnread: tab.isUnread,
            customName: tab.customName,
            groupID: tab.groupID.map { "\($0)" },
            pageCount: tab.pages.count,
        )
    }

    /// Builds a ``SpaceInfo`` from a ``Space`` model.
    private func buildSpaceInfo(_ space: Space, activeSpaceID: Space.ID?) -> CTL.SpaceInfo {
        CTL.SpaceInfo(
            id: "\(space.id)",
            name: space.name,
            tabCount: space.tabs.count,
            isActive: space.id == activeSpaceID,
        )
    }

    /// Resolves a ``WebPage`` from optional tab ID and page ID strings.
    ///
    /// Resolution priority:
    /// 1. If `pageID` is provided, resolves directly to that page.
    /// 2. If only `tabID` is provided, resolves the tab. Errors if the tab has multiple pages.
    /// 3. If neither is provided, uses the active tab. Errors if it has multiple pages.
    private func resolveWebPage(tabID: String?, pageID: String?) throws -> WebPage {
        // Direct page resolution takes priority
        if let pageID {
            guard let tabPage = findTabPage(byID: pageID) else {
                throw ControlError.pageNotFound(pageID)
            }
            guard let webPage = pagePool.page(for: tabPage) else {
                throw ControlError.noWebPage
            }
            return webPage
        }

        // Resolve tab (supports flexible refs: index, title, URL, special tokens)
        let tab = try resolveTab(tabID: tabID)

        // Multi-page guard: error if tab has multiple pages and no pageID specified
        if tab.pages.count > 1 {
            let pageDescriptions = tab.sortedPages.map { page in
                (id: "\(page.id)", position: page.position?.rawValue ?? "unknown", url: page.url.absoluteString)
            }
            throw ControlError.ambiguousPage(tabID: "\(tab.id)", pages: pageDescriptions)
        }

        guard let webPage = pagePool.page(for: tab.activePage) else {
            throw ControlError.noWebPage
        }

        return webPage
    }

    /// Resolves a tab reference string to a ``Tab``.
    ///
    /// Supports multiple reference formats:
    /// - UUID string: exact match by ID
    /// - `"active"`: the currently active tab
    /// - `"first"`, `"last"`: position in the current space
    /// - `"next"`, `"prev"`/`"previous"`: relative to the active tab
    /// - Numeric string (e.g. `"3"`): 1-based index in the current space
    /// - `"title:..."`: case-insensitive substring match on tab title
    /// - `"url:..."`: case-insensitive substring match on tab URL
    /// - Any other string: fuzzy match against both title and URL
    private func resolveTabRef(_ ref: String) throws -> Tab {
        let allTabs = browserState.spaces.flatMap(\.tabs)
        let activeSpace = windowManager.activeWindowController?.windowState.activeSpace
        let spaceTabs = activeSpace?.tabs ?? []

        // 1. Special keywords
        switch ref.lowercased() {
        case "active":
            guard let tab = windowManager.activeWindowController?.windowState.activeTab else {
                throw ControlError.noActiveTab
            }
            return tab

        case "first":
            guard let tab = spaceTabs.first else { throw ControlError.noTabs }
            return tab

        case "last":
            guard let tab = spaceTabs.last else { throw ControlError.noTabs }
            return tab

        case "next":
            guard let activeTab = windowManager.activeWindowController?.windowState.activeTab else {
                throw ControlError.noActiveTab
            }
            guard let idx = spaceTabs.firstIndex(where: { $0.id == activeTab.id }),
                  idx + 1 < spaceTabs.count
            else {
                throw ControlError.tabNotFound("next (no tab after active)")
            }
            return spaceTabs[idx + 1]

        case "prev", "previous":
            guard let activeTab = windowManager.activeWindowController?.windowState.activeTab else {
                throw ControlError.noActiveTab
            }
            guard let idx = spaceTabs.firstIndex(where: { $0.id == activeTab.id }),
                  idx > 0
            else {
                throw ControlError.tabNotFound("previous (no tab before active)")
            }
            return spaceTabs[idx - 1]

        default:
            break
        }

        // 2. UUID match (exact)
        if let tab = allTabs.first(where: { ref == "\($0.id)" }) {
            return tab
        }

        // 3. 1-based index in current space
        if let index = Int(ref) {
            let zeroIndex = index - 1
            guard zeroIndex >= 0, zeroIndex < spaceTabs.count else {
                throw ControlError.tabNotFound("\(ref) (index out of range, space has \(spaceTabs.count) tabs)")
            }
            return spaceTabs[zeroIndex]
        }

        // 4. Prefix-based matching
        if ref.lowercased().hasPrefix("title:") {
            let query = String(ref.dropFirst(6))
            let matches = allTabs.filter { $0.activePage.title.localizedCaseInsensitiveContains(query) }
            return try uniqueMatch(matches, ref: ref)
        }

        if ref.lowercased().hasPrefix("url:") {
            let query = String(ref.dropFirst(4))
            let matches = allTabs.filter { $0.activePage.url.absoluteString.localizedCaseInsensitiveContains(query) }
            return try uniqueMatch(matches, ref: ref)
        }

        // 5. Fuzzy match on title or URL
        let matches = allTabs.filter {
            $0.activePage.title.localizedCaseInsensitiveContains(ref) ||
                $0.activePage.url.absoluteString.localizedCaseInsensitiveContains(ref)
        }
        return try uniqueMatch(matches, ref: ref)
    }

    /// Returns the single match or throws an appropriate error.
    private func uniqueMatch(_ matches: [Tab], ref: String) throws -> Tab {
        if matches.count == 1 { return matches[0] }
        if matches.isEmpty { throw ControlError.tabNotFound(ref) }
        throw ControlError.ambiguousTabRef(
            ref: ref,
            matches: matches.map { (id: "\($0.id)", title: $0.activePage.title, url: $0.activePage.url.absoluteString) },
        )
    }

    /// Legacy compatibility — wraps resolveTabRef for simple ID lookups.
    private func findTab(byID stringID: String) -> Tab? {
        try? resolveTabRef(stringID)
    }

    /// Finds a tab page by its string ID representation across all tabs in all spaces.
    private func findTabPage(byID stringID: String) -> TabPage? {
        for space in browserState.spaces {
            for tab in space.tabs {
                if let page = tab.pages.first(where: { stringID == "\($0.id)" }) {
                    return page
                }
            }
        }
        return nil
    }

    /// Finds a space by its string ID representation.
    private func findSpace(byID stringID: String) -> Space? {
        browserState.spaces.first { stringID == "\($0.id)" }
    }

    /// Finds a tab group by its string ID representation across all spaces.
    private func findGroup(byID stringID: String) -> TabGroup? {
        guard let uuid = UUID(uuidString: stringID) else { return nil }
        for space in browserState.spaces {
            let groups = groupManager.groups(in: space, spaceID: space.id)
            if let group = groups.first(where: { $0.id == uuid }) {
                return group
            }
        }
        return nil
    }

    /// Finds a reference tab by its string ID representation across all spaces.
    private func findReferenceTab(byID stringID: String) -> Tab? {
        browserState.spaces.flatMap(\.referenceTabs).first { stringID == "\($0.id)" }
    }

    /// Builds a ``GroupInfo`` from a ``TabGroup`` model.
    private func buildGroupInfo(_ group: TabGroup) -> CTL.GroupInfo {
        CTL.GroupInfo(
            id: "\(group.id)",
            name: group.name,
            color: group.colorString,
            iconName: group.iconName,
            spaceID: group.space.map { "\($0.id)" },
            tabCount: group.tabCount,
            isCollapsed: group.isCollapsed,
        )
    }

    /// Resolves a ``TabPage`` from optional tab ID and page ID strings.
    ///
    /// Uses the same resolution logic as ``resolveWebPage(tabID:pageID:)`` but returns
    /// the ``TabPage`` instead of a ``WebPage``. Used by dev tool handlers that need
    /// the page identity without requiring an active web page.
    private func resolveTabPage(tabID: String?, pageID: String?) throws -> TabPage {
        if let pageID {
            guard let tabPage = findTabPage(byID: pageID) else {
                throw ControlError.pageNotFound(pageID)
            }
            return tabPage
        }

        // Resolve tab (supports flexible refs)
        let tab = try resolveTab(tabID: tabID)

        if tab.pages.count > 1 {
            let pageDescriptions = tab.sortedPages.map { page in
                (id: "\(page.id)", position: page.position?.rawValue ?? "unknown", url: page.url.absoluteString)
            }
            throw ControlError.ambiguousPage(tabID: "\(tab.id)", pages: pageDescriptions)
        }

        return tab.activePage
    }

    /// Resolves a ``Tab`` from an optional tab ref string, falling back to the active tab.
    private func resolveTab(tabID: String?) throws -> Tab {
        if let tabIDString = tabID {
            return try resolveTabRef(tabIDString)
        }
        guard let tab = windowManager.activeWindowController?.windowState.activeTab else {
            throw ControlError.noActiveTab
        }
        return tab
    }

    /// Parses a color string (palette name, hex, or system name) into a SwiftUI Color.
    private func parseColor(_ string: String?) -> Color {
        guard let string, !string.isEmpty else { return .steel }
        // Try palette name or tagged/hex format
        let resolved = Color.resolveStoredColor(string)
        if resolved != .steel || string == GroupColor.steel.rawValue {
            return resolved
        }
        // Common named colors (for CLI convenience)
        switch string.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "pink": return .pink
        case "gray", "grey": return .gray
        case "brown": return .brown
        case "cyan", "teal": return .teal
        case "indigo": return .indigo
        case "mint": return .mint
        default: return .steel
        }
    }

    /// Maps a key name to a virtual key code.
    private func virtualKeyCode(for name: String) -> CGKeyCode? {
        switch name {
        case "a": CGKeyCode(kVK_ANSI_A)
        case "b": CGKeyCode(kVK_ANSI_B)
        case "c": CGKeyCode(kVK_ANSI_C)
        case "d": CGKeyCode(kVK_ANSI_D)
        case "e": CGKeyCode(kVK_ANSI_E)
        case "f": CGKeyCode(kVK_ANSI_F)
        case "g": CGKeyCode(kVK_ANSI_G)
        case "h": CGKeyCode(kVK_ANSI_H)
        case "i": CGKeyCode(kVK_ANSI_I)
        case "j": CGKeyCode(kVK_ANSI_J)
        case "k": CGKeyCode(kVK_ANSI_K)
        case "l": CGKeyCode(kVK_ANSI_L)
        case "m": CGKeyCode(kVK_ANSI_M)
        case "n": CGKeyCode(kVK_ANSI_N)
        case "o": CGKeyCode(kVK_ANSI_O)
        case "p": CGKeyCode(kVK_ANSI_P)
        case "q": CGKeyCode(kVK_ANSI_Q)
        case "r": CGKeyCode(kVK_ANSI_R)
        case "s": CGKeyCode(kVK_ANSI_S)
        case "t": CGKeyCode(kVK_ANSI_T)
        case "u": CGKeyCode(kVK_ANSI_U)
        case "v": CGKeyCode(kVK_ANSI_V)
        case "w": CGKeyCode(kVK_ANSI_W)
        case "x": CGKeyCode(kVK_ANSI_X)
        case "y": CGKeyCode(kVK_ANSI_Y)
        case "z": CGKeyCode(kVK_ANSI_Z)
        case "0": CGKeyCode(kVK_ANSI_0)
        case "1": CGKeyCode(kVK_ANSI_1)
        case "2": CGKeyCode(kVK_ANSI_2)
        case "3": CGKeyCode(kVK_ANSI_3)
        case "4": CGKeyCode(kVK_ANSI_4)
        case "5": CGKeyCode(kVK_ANSI_5)
        case "6": CGKeyCode(kVK_ANSI_6)
        case "7": CGKeyCode(kVK_ANSI_7)
        case "8": CGKeyCode(kVK_ANSI_8)
        case "9": CGKeyCode(kVK_ANSI_9)
        case "escape", "esc": CGKeyCode(kVK_Escape)
        case "return", "enter": CGKeyCode(kVK_Return)
        case "tab": CGKeyCode(kVK_Tab)
        case "space": CGKeyCode(kVK_Space)
        case "delete", "backspace": CGKeyCode(kVK_Delete)
        case "forwarddelete": CGKeyCode(kVK_ForwardDelete)
        case "up": CGKeyCode(kVK_UpArrow)
        case "down": CGKeyCode(kVK_DownArrow)
        case "left": CGKeyCode(kVK_LeftArrow)
        case "right": CGKeyCode(kVK_RightArrow)
        case "home": CGKeyCode(kVK_Home)
        case "end": CGKeyCode(kVK_End)
        case "pageup": CGKeyCode(kVK_PageUp)
        case "pagedown": CGKeyCode(kVK_PageDown)
        case "f1": CGKeyCode(kVK_F1)
        case "f2": CGKeyCode(kVK_F2)
        case "f3": CGKeyCode(kVK_F3)
        case "f4": CGKeyCode(kVK_F4)
        case "f5": CGKeyCode(kVK_F5)
        case "f6": CGKeyCode(kVK_F6)
        case "f7": CGKeyCode(kVK_F7)
        case "f8": CGKeyCode(kVK_F8)
        case "f9": CGKeyCode(kVK_F9)
        case "f10": CGKeyCode(kVK_F10)
        case "f11": CGKeyCode(kVK_F11)
        case "f12": CGKeyCode(kVK_F12)
        case "-", "minus": CGKeyCode(kVK_ANSI_Minus)
        case "=", "equal", "equals": CGKeyCode(kVK_ANSI_Equal)
        case "[", "leftbracket": CGKeyCode(kVK_ANSI_LeftBracket)
        case "]", "rightbracket": CGKeyCode(kVK_ANSI_RightBracket)
        case "\\", "backslash": CGKeyCode(kVK_ANSI_Backslash)
        case ";", "semicolon": CGKeyCode(kVK_ANSI_Semicolon)
        case "'", "quote": CGKeyCode(kVK_ANSI_Quote)
        case ",", "comma": CGKeyCode(kVK_ANSI_Comma)
        case ".", "period": CGKeyCode(kVK_ANSI_Period)
        case "/", "slash": CGKeyCode(kVK_ANSI_Slash)
        case "`", "grave": CGKeyCode(kVK_ANSI_Grave)
        default: nil
        }
    }
}

// MARK: - Compound Commands

extension RefraxControlServer {
    private func handleNavigateAndRead(_ params: ControlRequest.NavigateAndReadParams) async throws -> ControlResponse {
        guard let url = URL(string: params.url) else {
            throw ControlError.invalidURL(params.url)
        }

        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        webPage.load(url)

        try? await Task.sleep(for: .milliseconds(100))
        try await waitForPageLoad(webPage, timeout: params.timeout ?? 30)

        return try await extractPageContent(webPage: webPage, scope: params.scope)
    }

    private func handleClickAndRead(_ params: ControlRequest.ClickAndReadParams) async throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        let webView = webPage.backingWebView
        let url = webPage.url ?? .blank
        let title = webPage.title

        // Resolve click target and perform click
        if let ref = params.ref {
            try await performClick(ref: ref, webPage: webPage, webView: webView, url: url, title: title)
        } else if let fuzzyText = params.fuzzyText {
            let resolved = try await resolveFuzzyText(fuzzyText, webView: webView, url: url, title: title)
            try await performClick(ref: resolved.ref, webPage: webPage, webView: webView, url: url, title: title)
        } else if let x = params.x, let y = params.y {
            try await webPage.callJavaScript("document.elementFromPoint(\(x), \(y))?.click()")
        } else {
            throw ControlError.invalidParams("clickAndRead requires 'ref', 'fuzzyText', or 'x'/'y' coordinates")
        }

        // Wait for navigation if requested
        if params.waitForNavigation == true {
            try? await Task.sleep(for: .milliseconds(200))
            try await waitForPageLoad(webPage, timeout: params.timeout ?? 30)
        } else {
            // Brief delay for DOM updates after click
            try? await Task.sleep(for: .milliseconds(300))
        }

        return try await extractPageContent(webPage: webPage, scope: params.scope)
    }

    private func handleFillForm(_ params: ControlRequest.FillFormParams) async throws -> ControlResponse {
        for (index, field) in params.fields.enumerated() {
            let formParams = ControlRequest.FormInputParams(
                ref: field.ref,
                value: field.value,
                tabID: params.tabID,
                pageID: params.pageID,
            )
            let result = try await handleFormInput(formParams)

            // Check for error responses from handleFormInput (it returns .error for not_found)
            if case let .error(info) = result {
                throw ControlError.fieldNotFound(index: index, ref: field.ref, message: info.message)
            }
        }

        if let submitRef = params.submitRef {
            let clickParams = ControlRequest.ClickParams(ref: submitRef, tabID: params.tabID, pageID: params.pageID)
            let result = try await handleClick(clickParams)
            if case let .error(info) = result {
                throw ControlError.elementNotFound(ref: submitRef, message: info.message)
            }
        }

        return .actionResult(CTL.ActionResultInfo(
            success: true,
            message: "Filled \(params.fields.count) field(s)\(params.submitRef != nil ? " and submitted" : "")",
        ))
    }

    private func handleScrollAndRead(_ params: ControlRequest.ScrollAndReadParams) async throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)

        if let ref = params.ref {
            // Scroll element into view — reuse existing scroll handler logic
            let scrollParams = ControlRequest.ScrollParams(ref: ref, tabID: params.tabID, pageID: params.pageID)
            let result = try await handleScroll(scrollParams)
            if case let .error(info) = result {
                throw ControlError.elementNotFound(ref: ref, message: info.message)
            }
        } else {
            let direction = params.direction ?? "down"
            let amount = params.amount ?? 500
            let scrollParams = ControlRequest.ScrollParams(
                direction: direction,
                amount: amount,
                tabID: params.tabID,
                pageID: params.pageID,
            )
            _ = try await handleScroll(scrollParams)
        }

        // Brief delay for scroll to settle
        try? await Task.sleep(for: .milliseconds(150))

        return try await extractPageContent(webPage: webPage, scope: params.scope)
    }

    private func handleFindElements(_ params: ControlRequest.FindElementsParams) async throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        let webView = webPage.backingWebView
        let url = webPage.url ?? .blank
        let title = webPage.title
        let tree = try await PageContentExtractor.extract(from: webView, url: url, title: title)

        let limit = params.limit ?? 10
        var results: [CTL.FoundElementInfo] = []
        collectMatchingNodes(node: tree.root, params: params, limit: limit, results: &results)

        return .foundElements(results)
    }

    // MARK: - Program Execution

    private func handleExecProgram(_ params: ControlRequest.ExecProgramParams) async throws -> ControlResponse {
        let execTask = Task { @MainActor in
            await programInterpreter.execute(
                program: params.program,
                timeout: TimeInterval(params.timeout ?? 60),
                verbose: params.verbose ?? false,
                dryRun: params.dryRun ?? false,
                tabID: params.tabID,
                pageID: params.pageID,
                policy: params.policy,
            )
        }
        return await awaitExecTaskOrHumanRequest(execTask)
    }

    private func handleResumeProgram(_ params: ControlRequest.ResumeProgramParams) async throws -> ControlResponse {
        guard let execTask = pendingExecTask else {
            return .ok("Resumed (no pending program)")
        }
        humanInterventionManager.resolve(token: params.token)
        return await awaitExecTaskOrHumanRequest(execTask)
    }

    /// Races a program execution task against a potential human intervention request.
    ///
    /// Sets up a callback on the interpreter so that if `request_human` fires before
    /// the task completes, we return `.humanRequested` early and store the task for
    /// later resumption. Otherwise returns the final `.execResult`.
    private func awaitExecTaskOrHumanRequest(_ execTask: Task<CTL.ExecResultInfo, Never>) async -> ControlResponse {
        var humanRequestContinuation: CheckedContinuation<CTL.HumanRequestInfo?, Never>?

        programInterpreter.onHumanRequest = { token, description in
            humanRequestContinuation?.resume(returning: CTL.HumanRequestInfo(token: token, description: description))
            humanRequestContinuation = nil
        }

        let humanRequest: CTL.HumanRequestInfo? = await withCheckedContinuation { continuation in
            humanRequestContinuation = continuation

            Task { @MainActor in
                _ = await execTask.value
                humanRequestContinuation?.resume(returning: nil)
                humanRequestContinuation = nil
            }
        }

        programInterpreter.onHumanRequest = nil

        if let humanRequest {
            pendingExecTask = execTask
            return .humanRequested(humanRequest)
        }

        pendingExecTask = nil
        return await .execResult(execTask.value)
    }

    // MARK: - Cookie Consent

    private func handleDismissCookies(_ params: ControlRequest.DismissCookiesParams) async throws -> ControlResponse {
        let webPage = try resolveWebPage(tabID: params.tabID, pageID: params.pageID)
        let result = try await CMPDetector.dismiss(on: webPage, acceptAll: params.acceptAll ?? false)

        if result.success {
            PageContentExtractor.clearAllCaches()
        }

        let prefix = "\(result.cmpType.rawValue): "
        return .actionResult(CTL.ActionResultInfo(
            success: result.success,
            message: "\(prefix)\(result.message)",
        ))
    }

    // MARK: - Headless Fetch

    private func handleFetch(_ params: ControlRequest.FetchParams) async throws -> ControlResponse {
        guard let url = URL(string: params.url) else {
            throw ControlError.invalidURL(params.url)
        }

        let timeout = params.timeout ?? 30
        let scope = params.scope ?? .viewport

        let content = try await HeadlessFetcher.fetch(
            url: url,
            scope: scope,
            timeoutSeconds: timeout,
            configuration: browserState.webPageConfiguration
        )

        return .pageContent(content)
    }

    private func handleNavigateNewTab(_ params: ControlRequest.NavigateNewTabParams) async throws -> ControlResponse {
        guard let url = URL(string: params.url) else {
            throw ControlError.invalidURL(params.url)
        }

        let space: Space?
        if let spaceIDString = params.spaceID {
            space = findSpace(byID: spaceIDString)
            if space == nil {
                return .error(CTL.ErrorInfo(code: "not_found", message: "Space not found: \(spaceIDString)"))
            }
        } else {
            space = windowManager.activeWindowController?.windowState.activeSpace
        }

        let activate = params.activate ?? true
        let tab = tabManager.createTab(url: url, in: space, makeActive: activate)
        let activeTabID = activate ? tab.id : windowManager.activeWindowController?.windowState.activeTabID

        let shouldWait = params.wait ?? (params.scope != nil)
        guard shouldWait else {
            return .tab(buildTabInfo(tab, activeTabID: activeTabID))
        }

        let webPage = try resolveWebPage(tabID: tab.id.uuidString, pageID: nil)

        try? await Task.sleep(for: .milliseconds(100))
        try await waitForPageLoad(webPage, timeout: params.timeout ?? 30)

        guard params.scope != nil else {
            return .tab(buildTabInfo(tab, activeTabID: activeTabID))
        }

        return try await extractPageContent(webPage: webPage, scope: params.scope)
    }

    // MARK: - Compound Command Helpers

    /// Extracts page content and returns a `.pageContent` response.
    private func extractPageContent(
        webPage: WebPage,
        scope: ControlRequest.PageContentParams.Scope?,
    ) async throws -> ControlResponse {
        let webView = webPage.backingWebView
        let url = webPage.url ?? .blank
        let title = webPage.title
        let tree = try await PageContentExtractor.extract(from: webView, url: url, title: title)
        let formatterScope: PageContentFormatter.Scope = switch scope {
        case .full: .full
        case .mainContent: .mainContent
        default: .viewport
        }
        let text = PageContentFormatter.format(tree, scope: formatterScope)
        return .pageContent(text)
    }

    /// Performs a click on an element by ref, extracting content tree and using native interaction.
    private func performClick(ref: String, webPage: WebPage, webView: WKWebView, url: URL, title: String) async throws {
        let tree = try await PageContentExtractor.extract(from: webView, url: url, title: title)

        guard let node = tree.findNode(byRef: ref) else {
            throw ControlError.elementNotFound(ref: ref, message: "Element ref '\(ref)' not found")
        }

        if let nativeID = node.nativeID {
            let interaction = _WKTextExtractionInteraction(action: .click)
            interaction.nodeIdentifier = nativeID
            if Self.supportsScrollToVisible { interaction.scrollToVisible = true }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                webView._performInteraction(interaction) { result in
                    if let error = result.error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } else {
            try await webPage.callJavaScript("document.elementFromPoint(\(node.rect.midX), \(node.rect.midY))?.click()")
        }
    }

    /// Resolves fuzzy text to a single interactive element ref by matching visible text content.
    private func resolveFuzzyText(
        _ fuzzyText: String,
        webView: WKWebView,
        url: URL,
        title: String,
    ) async throws -> (ref: String, nativeID: String?) {
        let tree = try await PageContentExtractor.extract(from: webView, url: url, title: title)
        let searchText = fuzzyText.lowercased()
        var matches: [(ref: String, nativeID: String?, text: String)] = []

        collectFuzzyMatches(node: tree.root, searchText: searchText, matches: &matches)

        switch matches.count {
        case 0:
            throw ControlError.fuzzyNotFound(fuzzyText)
        case 1:
            return (ref: matches[0].ref, nativeID: matches[0].nativeID)
        default:
            throw ControlError.fuzzyAmbiguous(
                text: fuzzyText,
                candidates: matches.prefix(5).map { (ref: $0.ref, text: $0.text) },
            )
        }
    }

    /// Recursively collects interactive nodes whose visible text contains the search text.
    private func collectFuzzyMatches(
        node: PageContentNode,
        searchText: String,
        matches: inout [(ref: String, nativeID: String?, text: String)],
    ) {
        if let ref = node.ref, node.isInteractive {
            let visibleText = collectVisibleText(from: node).lowercased()
            if visibleText.contains(searchText) {
                let displayText = collectVisibleText(from: node, maxLength: 80).lowercased()
                matches.append((ref: ref, nativeID: node.nativeID, text: displayText))
            }
        }
        for child in node.children {
            collectFuzzyMatches(node: child, searchText: searchText, matches: &matches)
        }
    }

    /// Extracts human-readable visible text from a node and its children.
    /// When `maxLength` is provided, truncates the result with "..." suffix.
    private func collectVisibleText(from node: PageContentNode, maxLength: Int? = nil) -> String {
        let text: String = switch node.type {
        case let .text(content):
            content.trimmingCharacters(in: .whitespacesAndNewlines)
        case let .formControl(_, label, _, _):
            if !label.isEmpty {
                label
            } else {
                childText(of: node, maxLength: maxLength)
            }
        case let .image(alt):
            alt ?? ""
        default:
            if let name = node.name, !name.isEmpty {
                name
            } else {
                childText(of: node, maxLength: maxLength)
            }
        }
        if let maxLength, text.count > maxLength {
            return String(text.prefix(maxLength)) + "..."
        }
        return text
    }

    /// Collects text from child nodes, joining with spaces.
    /// When `maxLength` is provided, stops accumulating once the limit is reached.
    private func childText(of node: PageContentNode, maxLength: Int? = nil) -> String {
        var parts: [String] = []
        var length = 0
        for child in node.children {
            let part = collectVisibleText(from: child, maxLength: maxLength.map { $0 - length })
            if part.isEmpty { continue }
            parts.append(part)
            length += part.count + 1
            if let maxLength, length >= maxLength { break }
        }
        return parts.joined(separator: " ")
    }

    /// Recursively collects nodes matching all provided predicates for `findElements`.
    private func collectMatchingNodes(
        node: PageContentNode,
        params: ControlRequest.FindElementsParams,
        limit: Int,
        results: inout [CTL.FoundElementInfo],
    ) {
        guard results.count < limit else { return }

        // Only consider nodes with refs (interactive elements)
        if let ref = node.ref {
            var matches = true

            if let textFilter = params.text, matches {
                let visibleText = collectVisibleText(from: node).lowercased()
                matches = visibleText.contains(textFilter.lowercased())
            }

            if let roleFilter = params.role, matches {
                let nodeRole = node.ariaAttributes["role"] ?? node.role
                matches = nodeRole == roleFilter
            }

            if let tagFilter = params.tag, matches {
                matches = tagForNodeType(node.type).lowercased() == tagFilter.lowercased()
            }

            if matches {
                let text = collectVisibleText(from: node, maxLength: 80)
                let href: String? = if case let .link(url) = node.type { url } else { nil }
                let inputType: String? = if case let .formControl(controlType, _, _, _) = node.type { controlType } else { nil }

                results.append(CTL.FoundElementInfo(
                    ref: ref,
                    text: text,
                    tag: tagForNodeType(node.type),
                    role: node.ariaAttributes["role"] ?? node.role,
                    href: href,
                    inputType: inputType,
                    rect: node.rect,
                ))
            }
        }

        for child in node.children {
            collectMatchingNodes(node: child, params: params, limit: limit, results: &results)
        }
    }

    /// Maps a `NodeType` to its HTML-like tag string for `findElements`.
    private func tagForNodeType(_ type: PageContentNode.NodeType) -> String {
        switch type {
        case .root: "root"
        case .overlay: "div"
        case .navigation: "nav"
        case .section: "section"
        case .article: "article"
        case .list: "ul"
        case .listItem: "li"
        case .blockquote: "blockquote"
        case .button: "button"
        case .canvas: "canvas"
        case .form: "form"
        case .generic: "div"
        case .text: "span"
        case .link: "a"
        case .image: "img"
        case .formControl: "input"
        case .select: "select"
        case .iframe: "iframe"
        case .scrollable: "div"
        case .contentEditable: "div"
        }
    }
}

// MARK: - Errors

extension RefraxControlServer {
    enum ControlError: LocalizedError {
        case tabNotFound(String)
        case pageNotFound(String)
        case ambiguousPage(tabID: String, pages: [(id: String, position: String, url: String)])
        case ambiguousTabRef(ref: String, matches: [(id: String, title: String, url: String)])
        case noActiveTab
        case noWebPage
        case noTabs
        case timeout(String)
        case invalidURL(String)
        case invalidParams(String)
        case elementNotFound(ref: String, message: String)
        case fieldNotFound(index: Int, ref: String, message: String)
        case fuzzyNotFound(String)
        case fuzzyAmbiguous(text: String, candidates: [(ref: String, text: String)])

        var errorDescription: String? {
            switch self {
            case let .tabNotFound(id): "Tab not found: \(id)"
            case let .pageNotFound(id): "Page not found: \(id)"
            case let .ambiguousPage(tabID, pages):
                "Tab \(tabID) has \(pages.count) pages. Use --page to target a specific page:\n" +
                    pages.map { "  \($0.id) (\($0.position), \($0.url))" }.joined(separator: "\n")
            case let .ambiguousTabRef(ref, matches):
                "'\(ref)' matches \(matches.count) tabs. Be more specific or use an ID:\n" +
                    matches.prefix(5).map { "  \($0.id) — \($0.title) (\($0.url))" }.joined(separator: "\n")
            case .noActiveTab: "No active tab"
            case .noWebPage: "Tab has no active web page"
            case .noTabs: "No tabs in current space"
            case let .timeout(message): message
            case let .invalidURL(url): "Invalid URL: \(url)"
            case let .invalidParams(message): message
            case let .elementNotFound(ref, message): "Element '\(ref)': \(message)"
            case let .fieldNotFound(index, ref, message): "Field \(index) (ref '\(ref)'): \(message)"
            case let .fuzzyNotFound(text): "No interactive element found matching '\(text)'"
            case let .fuzzyAmbiguous(text, candidates):
                "'\(text)' matches \(candidates.count) elements. Be more specific:\n" +
                    candidates.map { "  \($0.ref) — \"\($0.text)\"" }.joined(separator: "\n")
            }
        }

        var errorCode: String {
            switch self {
            case .tabNotFound: "not_found"
            case .pageNotFound: "not_found"
            case .ambiguousPage: "ambiguous_page"
            case .ambiguousTabRef: "ambiguous_ref"
            case .noActiveTab: "no_active_tab"
            case .noWebPage: "no_web_page"
            case .noTabs: "no_tabs"
            case .timeout: "timeout"
            case .invalidURL: "invalid_url"
            case .invalidParams: "invalid_params"
            case .elementNotFound: "not_found"
            case .fieldNotFound: "not_found"
            case .fuzzyNotFound: "not_found"
            case .fuzzyAmbiguous: "ambiguous_ref"
            }
        }
    }

    // MARK: - Global Settings

    private func handleSettingsList(_ params: ControlRequest.SettingsListParams) -> ControlResponse {
        let filterCategory = params.category.flatMap { SettingsCategory(rawValue: $0) }

        let entries = BrowserSettingKey.allCases
            .filter { key in
                guard let category = filterCategory else { return true }
                return key.metadata.category == category
            }
            .map { key in
                CTL.SettingEntryInfo(
                    key: key.rawValue,
                    displayName: key.metadata.displayName,
                    value: key.displayValue(in: browserSettings),
                    category: key.metadata.category.rawValue,
                )
            }

        return .settingsEntries(entries)
    }

    private func handleSettingsGet(_ params: ControlRequest.SettingsGetParams) throws -> ControlResponse {
        guard let key = BrowserSettingKey(rawValue: params.key) else {
            return .error(CTL.ErrorInfo(code: "invalid_key", message: "Unknown setting key: \(params.key)"))
        }

        let entry = CTL.SettingEntryInfo(
            key: key.rawValue,
            displayName: key.metadata.displayName,
            value: key.displayValue(in: browserSettings),
            category: key.metadata.category.rawValue,
        )

        return .settingsEntries([entry])
    }

    private func handleSettingsSet(_ params: ControlRequest.SettingsSetParams) throws -> ControlResponse {
        guard let key = BrowserSettingKey(rawValue: params.key) else {
            return .error(CTL.ErrorInfo(code: "invalid_key", message: "Unknown setting key: \(params.key)"))
        }

        let value = params.value.lowercased()

        switch key.metadata.valueKind {
        case .toggle:
            switch value {
            case "on", "true", "yes", "1":
                key.setValue(.bool(true), in: browserSettings)
            case "off", "false", "no", "0":
                key.setValue(.bool(false), in: browserSettings)
            case "toggle":
                key.toggle(in: browserSettings)
            default:
                return .error(CTL.ErrorInfo(
                    code: "invalid_value",
                    message: "Invalid value '\(params.value)' for toggle setting. Use on/off/toggle.",
                ))
            }
        case .picker:
            key.setValue(.string(params.value), in: browserSettings)
        case .navigateOnly:
            return .error(CTL.ErrorInfo(
                code: "not_settable",
                message: "Setting '\(params.key)' cannot be set via CLI.",
            ))
        }

        return .ok("Set \(key.metadata.displayName) to \(key.displayValue(in: browserSettings))")
    }
}
