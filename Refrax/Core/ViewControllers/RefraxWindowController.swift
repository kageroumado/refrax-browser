import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Root controller for a Refrax browser window.
///
/// The page fills the window. Above it sit the floating tab layer, the tab canvas,
/// the window overlays (lenses, toasts, the tour), the Control Island, and the
/// File Island, each in its own hosting view over the window's content view.
///
/// ## State Management
///
/// Each window maintains its own ``WindowState`` for UI-specific concerns like
/// lens visibility and floating placements, while accessing shared resources
/// through environment-injected managers:
///
/// - ``TabManager``: Shared tabs and spaces across all windows
/// - ``HistoryManager``: Browsing history tracking
/// - ``BrowserSettings``: User preferences
/// - ``AutoFillState``: Password management
final class RefraxWindowController: NSWindowController, NSWindowDelegate, NSUserInterfaceValidations {
    // MARK: - Internal Properties (accessible to extensions)

    /// The window's content view controller: the page, with the floating layers above it.
    let rootViewController = NSViewController()
    let backgroundView: WindowBackgroundView
    var overlayView: NSView

    // MARK: - State & Dependencies

    let windowState: WindowState
    let tabManager: TabManager
    let historyManager: HistoryManager
    let bookmarksManager: BookmarksManager
    let siteSettingsManager: SiteSettingsManager
    let settings: BrowserSettings
    let autoFillState: AutoFillState
    let dialogState: DialogState
    let historyMaintenanceService: HistoryMaintenanceService
    let tabPreviewProvider: TabPreviewProvider
    let commandLensManager: CommandLensManager
    let tabSwitcherManager: TabSwitcherManager
    let tabCanvasManager: TabCanvasManager
    /// The window's view onto its space's table of slabs.
    let islandController: IslandController

    private(set) var environment: RefraxEnvironment!

    // MARK: Detail Tray

    var detailTrayContainer: NSView?
    var detailTrayGlassView: NSGlassEffectView?
    var detailTrayHideTask: Task<Void, any Error>?
    var isCursorInDetailTray = false

    /// The reading state decoded by AppKit restoration, applied once tabs load.
    var restoredReadingState: WindowReadingState?

    /// Tasks created for @Observable observations.
    ///
    /// These must be explicitly cancelled on window close since they hold
    /// strong references to the controller via closure captures.
    var observationTasks: [Task<Void, Never>] = []

    // MARK: - Screen Sharing Detection

    /// Observer for detecting when this window is being screen captured.
    ///
    /// Used to enable process audio tapping so external apps can capture
    /// WebKit audio during screen sharing.
    var windowSharingObserver: WindowSharingObserver?

    /// The size of the page area: the whole content view.
    var pageAreaSize: CGSize {
        window?.contentView?.bounds.size ?? .zero
    }

    /// Opens the tab canvas from a pinch or ⌃-scroll on the page.
    private var canvasPageGestures: CanvasPageGestures?

    // MARK: - Undo/Redo

    private var undoRedoMonitor: Any?

    // MARK: - Initialization

    override init(window: NSWindow?) {
        guard let window else { preconditionFailure() }

        let appDelegate = NSApplication.shared.typedDelegate
        let modelContainer = appDelegate.modelContainer

        self.overlayView = NSView()
        self.backgroundView = WindowBackgroundView()
        self.windowState = WindowState(settings: appDelegate.settings, browserState: appDelegate.browserState)
        self.tabManager = appDelegate.tabManager
        self.bookmarksManager = appDelegate.bookmarksManager
        self.siteSettingsManager = appDelegate.siteSettingsManager
        self.settings = appDelegate.settings
        self.autoFillState = appDelegate.autoFillState
        self.dialogState = appDelegate.dialogState
        self.historyManager = appDelegate.historyManager
        self.historyMaintenanceService = appDelegate.historyMaintenanceService
        self.tabPreviewProvider = TabPreviewProvider(
            tabManager: appDelegate.tabManager,
            windowState: windowState,
        )
        self.tabSwitcherManager = TabSwitcherManager(
            tabManager: appDelegate.tabManager,
            windowState: windowState,
            previewProvider: tabPreviewProvider,
        )
        self.tabCanvasManager = TabCanvasManager(
            tabManager: appDelegate.tabManager,
            windowState: windowState,
            pagePool: appDelegate.pagePool,
            groupManager: appDelegate.groupManager,
        )
        self.islandController = IslandController(
            windowState: windowState,
            tabManager: appDelegate.tabManager,
            groupManager: appDelegate.groupManager,
            canvas: tabCanvasManager,
            pagePool: appDelegate.pagePool,
        )
        let floatingTourManager = FloatingTourManager(windowState: windowState, canvas: tabCanvasManager, tabManager: appDelegate.tabManager)
        self.commandLensManager = CommandLensManager(
            tabManager: appDelegate.tabManager,
            historyManager: appDelegate.historyManager,
            windowState: windowState,
            browserSettings: appDelegate.settings,
            siteSettingsManager: appDelegate.siteSettingsManager,
            downloadManager: appDelegate.downloadManager,
            extensionManager: appDelegate.extensionManager,
            customSearchEngineManager: appDelegate.customSearchEngineManager,
            localNetworkSource: appDelegate.localNetworkDirectory,
            floatingTour: floatingTourManager,
        )
        super.init(window: window)

        windowState.window = window
        window.delegate = self

        self.environment = RefraxEnvironment(
            modelContainer: modelContainer,
            browserState: appDelegate.browserState,
            windowState: windowState,
            historyManager: historyManager,
            historyActivityManager: appDelegate.historyActivityManager,
            settings: settings,
            siteSettingsManager: siteSettingsManager,
            autoFillState: autoFillState,
            tabManager: tabManager,
            pagePool: appDelegate.pagePool,
            spaceManager: appDelegate.spaceManager,
            groupManager: appDelegate.groupManager,
            archiveManager: appDelegate.archiveManager,
            autoArchiveManager: appDelegate.autoArchiveManager,
            windowManager: appDelegate.windowManager,
            bookmarksManager: bookmarksManager,
            extensionManager: appDelegate.extensionManager,
            dialogState: dialogState,
            tabPreviewProvider: tabPreviewProvider,
            downloadManager: appDelegate.downloadManager,
            shelfManager: appDelegate.shelfManager,
            webInspectorManager: appDelegate.webInspectorManager,
            sharingCoordinator: appDelegate.sharingCoordinator,
            passwordsManager: appDelegate.passwordsManager,
            commandLensManager: commandLensManager,
            modifierKeysState: appDelegate.modifierKeysState,
            tabSwitcherManager: tabSwitcherManager,
            tabCanvasManager: tabCanvasManager,
            mediaControlsManager: MediaControlsManager(tabManager: appDelegate.tabManager, windowState: windowState),
            undoRedoManager: appDelegate.undoRedoManager,
            clipboardMonitor: appDelegate.clipboardMonitor,
            screenshotCoordinator: ScreenshotCoordinator(),
            recordingCoordinator: RecordingCoordinator(),
            pageReminderManager: appDelegate.pageReminderManager,
            favoritePreviewManager: appDelegate.favoritePreviewManager,
            cookieInspectorManager: appDelegate.cookieInspectorManager,
            translationManager: appDelegate.translationManager,
            offlineContentManager: appDelegate.offlineContentManager,
            tabHealthProvider: appDelegate.tabHealthProvider,
            processMemoryMonitor: appDelegate.processMemoryMonitor,
            visualFeedbackManager: appDelegate.visualFeedbackManager,
            humanInterventionManager: appDelegate.humanInterventionManager,
            customSearchEngineManager: appDelegate.customSearchEngineManager,
            appUpdateManager: appDelegate.appUpdateManager,
            floatingTourManager: floatingTourManager,
            engineRegistry: appDelegate.engineRegistry,
            islandController: islandController,
        )
        windowState.islandController = islandController
        islandController.start()

        setupRootView(window: window)

        guard let contentView = window.contentView else { preconditionFailure() }
        setupBackgroundView(contentView: contentView)
        setupDetailTrayContainer(contentView: contentView)
        setupFloatingTabsLayer(contentView: contentView)
        setupTabCanvasLayer(contentView: contentView)
        setupCanvasPageGestures(window: window)
        setupOverlayView(contentView: contentView)
        setupControlIslandLayer(contentView: contentView)
        setupFileIslandLayer(contentView: contentView)
        setupUndoRedoMonitor()

        observeWindowState()
        observeWebsiteColor()
        observeDetailTrayState()
        observeSpaceLockState()
        setupWindowSharingObserver()
        hideStandardWindowButtons()
        commandLensManager.setup()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Setup

    /// Makes the page the window's content, at the window's full size.
    private func setupRootView(window: NSWindow) {
        let rootView = NSView()
        let pageView = NSHostingView(rootView: MainContentView().refraxEnvironment(environment))
        pageView.sizingOptions = []
        pageView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(pageView)
        NSLayoutConstraint.activate([
            pageView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            pageView.topAnchor.constraint(equalTo: rootView.topAnchor),
            pageView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])
        rootViewController.view = rootView
        window.contentViewController = rootViewController
        window.contentMinSize = NSSize(width: Constants.Layout.contentMinSize, height: Constants.Layout.contentMinSize)
    }

    private func setupBackgroundView(contentView: NSView) {
        backgroundView.frame = contentView.bounds
        backgroundView.autoresizingMask = [.width, .height]

        contentView.addSubview(backgroundView, positioned: .below, relativeTo: nil)
    }

    private func setupFloatingTabsLayer(contentView: NSView) {
        let floatingView = FloatingTabsHostingView(rootView: IslandsLayer().refraxEnvironment(environment))
        floatingView.sizingOptions = []
        floatingView.onPointerDown = { [weak floatingView, weak tabCanvasManager, weak windowState, weak islandController] point in
            guard let floatingView, let tabCanvasManager, let windowState, let islandController else { return }
            if (windowState.controlIsland.hitRegions + windowState.fileIsland.hitRegions).contains(where: { $0.contains(point) }) {
                return
            }
            if let tab = tabCanvasManager.dockedTab(at: point, in: floatingView.bounds) {
                windowState.recordInteraction(with: tab.activePage.id)
                return
            }
            if islandController.hitRegions(in: floatingView.bounds).contains(where: { $0.contains(point) }) {
                return
            }
            if !windowState.controlIsland.tabInfo.isMenuPresented {
                tabCanvasManager.dismissFloatingTabs()
            }
        }
        floatingView.onSecondaryPointerDown = { _, _ in false }
        floatingView.hitRegions = { [weak floatingView, weak tabCanvasManager, weak islandController] in
            guard let floatingView, let tabCanvasManager, let islandController else { return [] }
            return islandController.hitRegions(in: floatingView.bounds) + tabCanvasManager.dockHitRegions(in: floatingView.bounds)
        }
        contentView.addSubview(floatingView)
        floatingView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            floatingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            floatingView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            floatingView.topAnchor.constraint(equalTo: contentView.topAnchor),
            floatingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    /// The tab canvas covers the whole window, above the floating layer and below Command Lens.
    private func setupTabCanvasLayer(contentView: NSView) {
        let canvasView = TransparentHostingView(rootView: TabCanvasLayer().refraxEnvironment(environment)) { [unowned self] in
            !tabCanvasManager.isActive
        }
        // The layer follows the window's size and must never set it: by default a
        // hosting view pins the window to its content, which is empty while closed.
        canvasView.sizingOptions = []
        contentView.addSubview(canvasView)
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            canvasView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            canvasView.topAnchor.constraint(equalTo: contentView.topAnchor),
            canvasView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    /// Page gestures reach the canvas only over a page at its normal size, with no lens up.
    private func setupCanvasPageGestures(window: NSWindow) {
        canvasPageGestures = CanvasPageGestures(window: window, canvas: tabCanvasManager, floatingEligible: { [unowned self] in
            !windowState.showsCommandLens && !windowState.isSpaceLocked
                && !tabSwitcherManager.isActive && window.attachedSheet == nil
        }, floatingContains: { [unowned self] point in
            guard let content = window.contentView else { return false }
            let local = content.convert(point, from: nil)
            let topLeft = CGPoint(x: local.x, y: content.isFlipped ? local.y : content.bounds.height - local.y)
            if tabCanvasManager.showsFloatingControls,
               (windowState.controlIsland.hitRegions + windowState.fileIsland.hitRegions).contains(where: { $0.contains(topLeft) }) {
                return true
            }
            return tabCanvasManager.floatingHitRegions(in: content.bounds).contains { $0.contains(topLeft) }
        }, floatingControlsContain: { [unowned self] point in
            guard let content = window.contentView, tabCanvasManager.showsFloatingControls else { return false }
            let local = content.convert(point, from: nil)
            let topLeft = CGPoint(x: local.x, y: content.isFlipped ? local.y : content.bounds.height - local.y)
            return (windowState.controlIsland.hitRegions + windowState.fileIsland.hitRegions).contains { $0.contains(topLeft) }
        }, floatingHasKeyboardFocus: { [unowned self] in
            guard let focused = window.firstResponder as? NSView else { return false }
            return tabCanvasManager.visibleFloatingTabs.contains { tab in
                guard let page = environment.pagePool.existingPage(for: tab.activePage), page.isInFloatingPreview else { return false }
                return focused === page.contentView || focused.isDescendant(of: page.contentView)
            }
        }) { [unowned self] point in
            guard !windowState.showsCommandLens,
                  tabCanvasManager.isLivePageAtNormalSize,
                  let pageFrame = tabCanvasManager.currentLivePageFrame()
            else { return false }
            return pageFrame.contains(point)
        }
        canvasPageGestures?.islands = islandController
        canvasPageGestures?.islandInput = IslandInput(islands: islandController)
    }

    private func setupOverlayView(contentView: NSView) {
        let overlay = TransparentHostingView(rootView: OverlayContainer().refraxEnvironment(environment)) { [unowned self] in
            !windowState.showsCommandLens
                && !tabSwitcherManager.isActive
                && windowState.lockedSpaceRequiringAuth == nil
                && !windowState.isHoveringOverlayNotification
                && environment.screenshotCoordinator.currentPreview == nil
                && environment.recordingCoordinator.currentPreview == nil
                && !environment.floatingTourManager.isActive
        }
        // The tour's spotlit targets stay reachable under the scrim.
        overlay.passThroughRegions = { [weak overlay, unowned self] in
            guard let overlay else { return [] }
            return environment.floatingTourManager.passThroughRegions(in: overlay.bounds)
        }
        // A tour step done on the page leaves the page every click outside the tour's card.
        overlay.capturedRegions = { [unowned self] in
            environment.floatingTourManager.capturedRegions
        }
        overlayView = overlay

        contentView.addSubview(overlayView)
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: contentView.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    /// Sets up observation of window screen sharing state to enable audio tap.
    ///
    /// When an external app (Discord, Zoom, etc.) captures this window, we start
    /// capturing WebKit.GPU audio and re-routing it through our process so
    /// ScreenCaptureKit can include it.
    private func setupWindowSharingObserver() {
        guard settings.isFeatureFlagEnabled("app.processAudioTap", default: false) else { return }
        guard let window else { return }

        // Create the observer
        windowSharingObserver = WindowSharingObserver(window: window)

        // Observe changes using Observations async sequence
        let task = Task { @MainActor [weak self] in
            guard let self, let observer = windowSharingObserver else { return }

            let sharingChanges = Observations { observer.isWindowBeingShared }

            for await isSharing in sharingChanges {
                handleWindowSharingStateChanged(isSharing: isSharing)
            }
        }
        observationTasks.append(task)
    }

    /// Handles changes in window sharing state.
    private func handleWindowSharingStateChanged(isSharing: Bool) {
        let appDelegate = NSApplication.shared.typedDelegate
        let processAudioTapManager = appDelegate.processAudioTapManager

        if isSharing {
            Logger.info("Window sharing started - enabling audio tap", category: Logger.webview)
            processAudioTapManager.beginWindowSharing()
        } else {
            Logger.info("Window sharing ended - disabling audio tap", category: Logger.webview)
            processAudioTapManager.endWindowSharing()
        }
    }

    // MARK: - Public Actions

    /// Opens the command lens (for new tab, search, etc.)
    func openCommandLens() {
        windowState.openCommandLens()
    }

    /// Opens the Command Lens beside the page card with the address in it (⌘L).
    func editAddress() {
        windowState.editAddress()
    }

    /// Stops loading the active page.
    func stopLoading() {
        windowState.activeWebPage?.stopLoading()
    }

    /// Reloads the focused page.
    func reloadPage() {
        _ = windowState.focusedWebPage?.reload()
    }

    /// Reloads the focused page without using cache.
    func reloadPageFromOrigin() {
        _ = windowState.focusedWebPage?.reload(fromOrigin: true)
    }

    /// Opens the next tab back in recency, the Recent list's order (⌘⇧]).
    func selectNextTab() {
        tabSwitcherManager.stepThroughRecent(by: 1)
    }

    /// Opens the previous, more recent tab in the Recent list's order (⌘⇧[).
    func selectPreviousTab() {
        tabSwitcherManager.stepThroughRecent(by: -1)
    }

    /// Opens a file panel to load local files in the browser.
    func openFilePanel() {
        guard let window else { return }

        Task { @MainActor in
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [
                .html, .webArchive, .pdf, .png, .jpeg, .gif, .webP, .svg,
                .bmp, .ico, .tiff, .plainText, .xml, .json,
            ]

            let response = await panel.beginSheetModal(for: window)
            guard response == .OK else { return }

            for (index, url) in panel.urls.enumerated() {
                tabManager.createTab(url: url, makeActive: index == 0)
            }
        }
    }

    /// Loads a URL in the active page
    func loadURL(_ url: URL) {
        if let activePageID = windowState.activePageID {
            tabManager.state.webPage(for: activePageID)?.load(url)
        } else {
            tabManager.createTab(url: url, makeActive: true)
        }
    }

    // MARK: - Window Delegate

    func windowShouldClose(_: NSWindow) -> Bool {
        tabManager.scheduleSave()
        return true
    }

    func windowWillClose(_: Notification) {
        NotificationCenter.default.removeObserver(self)
        removeUndoRedoMonitor()
        cancelAllObservationTasks()
    }

    /// Cancels all observation tasks when the window closes.
    ///
    /// This prevents Tasks from retaining the controller and continuing
    /// work after the window is gone.
    private func cancelAllObservationTasks() {
        for task in observationTasks {
            task.cancel()
        }
        observationTasks.removeAll()
    }

    func window(_: NSWindow, willEncodeRestorableState state: NSCoder) {
        encodeWindowState(to: state)
    }

    func window(_: NSWindow, didDecodeRestorableState state: NSCoder) {
        decodeWindowState(from: state)
    }

    // MARK: - NSUserInterfaceValidations

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(browserUndo(_:)):
            NSApplication.shared.typedDelegate.undoRedoManager.undoManager.canUndo
        case #selector(browserRedo(_:)):
            NSApplication.shared.typedDelegate.undoRedoManager.undoManager.canRedo
        default:
            true
        }
    }

    // MARK: - Undo/Redo

    @objc
    func browserUndo(_: Any?) {
        let undoRedoManager = NSApplication.shared.typedDelegate.undoRedoManager
        if undoRedoManager.undoManager.canUndo {
            undoRedoManager.undoManager.undo()
        }
    }

    @objc
    func browserRedo(_: Any?) {
        let undoRedoManager = NSApplication.shared.typedDelegate.undoRedoManager
        if undoRedoManager.undoManager.canRedo {
            undoRedoManager.undoManager.redo()
        }
    }

    func setupUndoRedoMonitor() {
        undoRedoMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.window === self.window,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
                  || event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift],
                  event.charactersIgnoringModifiers == "z"
            else {
                return event
            }

            let isRedo = event.modifierFlags.contains(.shift)
            let undoRedoManager = NSApplication.shared.typedDelegate.undoRedoManager

            if let textView = window?.firstResponder as? NSTextView,
               let undoManager = textView.undoManager {
                if isRedo, undoManager.canRedo {
                    return event
                }
                if !isRedo, undoManager.canUndo {
                    return event
                }
            }

            if let firstResponder = window?.firstResponder,
               let undoManager = firstResponder.undoManager {
                if isRedo, undoManager.canRedo {
                    return event
                }
                if !isRedo, undoManager.canUndo {
                    return event
                }
            }

            if isRedo {
                if undoRedoManager.undoManager.canRedo {
                    undoRedoManager.undoManager.redo()
                    return nil
                }
            } else {
                if undoRedoManager.undoManager.canUndo {
                    undoRedoManager.undoManager.undo()
                    return nil
                }
            }

            return event
        }
    }

    func removeUndoRedoMonitor() {
        if let monitor = undoRedoMonitor {
            NSEvent.removeMonitor(monitor)
            undoRedoMonitor = nil
        }
    }
}
