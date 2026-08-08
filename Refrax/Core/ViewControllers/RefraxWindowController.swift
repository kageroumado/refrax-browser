import AppKit
import Combine
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Root view for a Refrax browser window.
///
/// Presents a three-column layout with sidebar (vertical tabs), main content area,
/// and optional inspector panel. Overlays include lenses for quick actions and
/// the hover-activated sidebar overlay when collapsed.
///
/// ## Layout Architecture
///
/// Uses `NSSplitViewController` to manage three resizable columns:
///
/// - **Sidebar**: Vertical tab list, spaces, and navigation controls
/// - **Content**: Primary web view showing the active tab's page
/// - **Inspector**: Reference pane for side-by-side browsing (collapsible)
///
/// ## State Management
///
/// Each window maintains its own ``WindowState`` for UI-specific concerns like
/// lens visibility and panel collapse, while accessing shared resources through
/// environment-injected managers:
///
/// - ``TabManager``: Shared tabs and spaces across all windows
/// - ``HistoryManager``: Browsing history tracking
/// - ``BrowserSettings``: User preferences
/// - ``AutoFillState``: Password management
final class RefraxWindowController: NSWindowController, NSWindowDelegate, NSUserInterfaceValidations {
    // MARK: - Internal Properties (accessible to extensions)

    let splitViewController: RefraxSplitViewController
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
    let tabPreviewManager: TabPreviewManager
    let commandLensManager: CommandLensManager
    let tabSwitcherManager: TabSwitcherManager
    let sidebarManagers: SidebarManagers

    private(set) var environment: RefraxEnvironment!
    var sidebarTrackingView: SidebarHoverTrackingView?
    var trackingViewWidthConstraint: NSLayoutConstraint?
    var lastCollapsedThickness: CGFloat = 300

    // MARK: Detail Tray

    var detailTrayContainer: NSView?
    var detailTrayGlassView: NSGlassEffectView?
    var detailTrayLeadingConstraint: NSLayoutConstraint?
    var detailTrayHideTask: Task<Void, any Error>?
    var isCursorInDetailTray = false

    /// AppKit container for the sidebar overlay, animated via layer transforms.
    var sidebarOverlayContainer: SidebarOverlayContainerView?

    /// Whether the cursor is currently inside the sidebar overlay.
    var isCursorInSidebarOverlay = false

    /// Glass effect view that provides the Liquid Glass appearance for the overlay.
    var sidebarOverlayGlassView: NSGlassEffectView?

    /// Width constraint for the sidebar overlay container, updated when sidebar is resized.
    var sidebarOverlayWidthConstraint: NSLayoutConstraint?

    // MARK: Compact Sidebar Edge Extension

    /// Background view that displays sampled colors from the webview edge in compact mode.
    var edgeExtensionBackgroundView: EdgeExtensionBackgroundView?

    /// Sampler that extracts colors from the webview's left edge for the background.
    let edgeSampler = WebViewEdgeSampler()

    /// Whether the sidebar overlay is currently visible.
    var isSidebarOverlayVisible: Bool {
        guard let container = sidebarOverlayContainer else { return false }
        return !container.isHidden
    }

    /// Flag to prevent observer reactions during restoration
    var isRestoringState = false

    /// Flag to prevent frame observer feedback during programmatic inspector updates
    var isUpdatingInspectorProgrammatically = false

    /// State machine for sidebar overlay animation
    var isAnimatingToVisible = false
    var isOverlayTriggered = false
    var hideTask: Task<Void, any Error>?

    /// Task for tutorial peek animation
    var tutorialPeekTask: Task<Void, any Error>?

    /// Whether the tutorial peek animation is currently showing.
    var isTutorialPeekActive = false

    /// Generation counter for overlay/chrome animations.
    ///
    /// Incremented each time a new animation sequence starts. Used to ensure only
    /// the most recent animation's completion handler takes effect, preventing
    /// race conditions where an earlier animation might "win" over a later one.
    var overlayAnimationGeneration: UInt = 0

    /// Task for sidebar expansion completion detection
    var sidebarExpansionTask: Task<Void, any Error>?

    /// Flag indicating we're doing a smooth overlay-to-sidebar transition.
    var isTransitioningFromOverlay = false

    /// Flag indicating we're handling collapse animation ourselves.
    var isAnimatingCollapse = false

    /// Guards against rapid sidebar toggle presses during in-flight animations.
    ///
    /// Set at the start of any sidebar state transition (toggle, collapse,
    /// expand-from-overlay) and cleared in the completion handler. When set,
    /// `toggleSidebar()` returns early to prevent overlapping animations.
    var isAnimatingSidebarTransition = false

    var cancellables = Set<AnyCancellable>()

    /// Tasks created for @Observable observations.
    ///
    /// These must be explicitly cancelled on window close since they hold
    /// strong references to the controller via closure captures.
    var observationTasks: [Task<Void, Never>] = []

    // MARK: - Sidebar Tracking

    var splitViewSidebarTrackingAdapter: OverlaySidebarTrackingAdapter?
    var originalTrafficLightOrigins: [NSWindow.ButtonType: CGPoint] = [:]
    var originalTrafficLightGroupFrame: CGRect?

    // MARK: - Compact Mode Traffic Lights

    /// Glass platter behind traffic lights in compact sidebar mode (iPadOS style)
    var compactTrafficLightPlatter: NSView?

    /// Tracking area for hover detection on compact traffic lights
    var compactTrafficLightTrackingArea: NSTrackingArea?

    /// Whether the compact traffic lights are currently hovered (expanded)
    var isCompactTrafficLightsHovered = false

    /// Whether compact traffic light mode is currently active
    var isCompactTrafficLightModeActive = false

    /// Task for verifying the cursor is still over the compact traffic lights.
    ///
    /// NSTrackingArea can miss `mouseExited` events when the cursor moves very
    /// fast over a small tracking rect. This task runs after the expand animation
    /// completes to catch that case.
    var compactTrafficLightHoverCheckTask: Task<Void, Never>?

    // MARK: - Screen Sharing Detection

    /// Observer for detecting when this window is being screen captured.
    ///
    /// Used to enable process audio tapping so external apps can capture
    /// WebKit audio during screen sharing.
    var windowSharingObserver: WindowSharingObserver?

    var themeFrame: NSThemeFrame? {
        window?.contentView?.superview as? NSThemeFrame
    }

    var toolbarView: NSToolbarView? {
        window?.toolbar?._toolbarView
    }

    var sidebarTrackingSeparatorItem: NSToolbarItem? {
        window?.toolbar?.items.first { $0.itemIdentifier == .sidebarTrackingSeparator }
    }

    var titlebarContainerView: NSTitlebarContainerView? {
        themeFrame?.titlebarContainerView
    }

    var titlebarView: NSTitlebarView? {
        themeFrame?.titlebarView
    }

    /// The divider offset that AppKit adds to the sidebar frame width.
    let sidebarDividerOffset: CGFloat = 8.0

    /// Tracks the last divider position we set on the toolbar view.
    var lastToolbarDividerPosition: CGFloat?

    /// The toolbar item identifiers that should move with the sidebar.
    let sidebarToolbarItemIdentifiers: Set<NSToolbarItem.Identifier> = [
        .toggleSidebar, .toggleLayoutMode, .toggleInspector,
    ]

    /// Tracks whether we're in fullscreen mode for proper edge reveal behavior
    var isInFullscreen = false

    // MARK: - Undo/Redo

    private var undoRedoMonitor: Any?

    // MARK: - Initialization

    override init(window: NSWindow?) {
        guard let window else { preconditionFailure() }

        let appDelegate = NSApplication.shared.typedDelegate
        let modelContainer = appDelegate.modelContainer

        self.splitViewController = RefraxSplitViewController()
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
        self.tabPreviewManager = TabPreviewManager(
            previewProvider: tabPreviewProvider,
            browserSettings: settings,
        )
        self.commandLensManager = CommandLensManager(
            tabManager: appDelegate.tabManager,
            historyManager: appDelegate.historyManager,
            windowState: windowState,
            browserSettings: appDelegate.settings,
            siteSettingsManager: appDelegate.siteSettingsManager,
            downloadManager: appDelegate.downloadManager,
            referencePaneManager: appDelegate.referencePaneManager,
            agentChatManager: appDelegate.agentChatManager,
            extensionManager: appDelegate.extensionManager,
            customSearchEngineManager: appDelegate.customSearchEngineManager,
        )
        self.tabSwitcherManager = TabSwitcherManager(
            tabManager: appDelegate.tabManager,
            windowState: windowState,
            previewProvider: tabPreviewProvider,
        )
        self.sidebarManagers = SidebarManagers(
            tabManager: appDelegate.tabManager,
            bookmarksManager: appDelegate.bookmarksManager,
            windowState: windowState,
            groupManager: appDelegate.groupManager,
            undoRedoManager: appDelegate.undoRedoManager,
            settings: appDelegate.settings,
        )

        // Configure shelf manager with download dependencies
        sidebarManagers.shelfManager.configure(
            downloadManager: appDelegate.downloadManager,
            dataStore: .default(),
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
            referencePaneManager: appDelegate.referencePaneManager,
            archiveManager: appDelegate.archiveManager,
            autoArchiveManager: appDelegate.autoArchiveManager,
            windowManager: appDelegate.windowManager,
            bookmarksManager: bookmarksManager,
            extensionManager: appDelegate.extensionManager,
            dialogState: dialogState,
            tabPreviewProvider: tabPreviewProvider,
            tabPreviewManager: tabPreviewManager,
            downloadManager: appDelegate.downloadManager,
            webInspectorManager: appDelegate.webInspectorManager,
            sharingCoordinator: appDelegate.sharingCoordinator,
            passwordsManager: appDelegate.passwordsManager,
            commandLensManager: commandLensManager,
            modifierKeysState: appDelegate.modifierKeysState,
            tabSwitcherManager: tabSwitcherManager,
            sidebarManagers: sidebarManagers,
            cellEnvironment: SidebarCellEnvironment(
                layoutManager: sidebarManagers.layoutManager,
                dragCoordinator: sidebarManagers.dragCoordinator,
                selectionManager: sidebarManagers.selectionManager,
                tabManager: tabManager,
                windowState: windowState,
                browserState: appDelegate.browserState,
                dependencyContainer: sidebarManagers.dependencyContainer,
                geometryState: sidebarManagers.geometryState,
                modifierKeysState: appDelegate.modifierKeysState,
                tabPreviewManager: tabPreviewManager,
                pagePool: appDelegate.pagePool,
                historyManager: historyManager,
                groupManager: appDelegate.groupManager,
                filterManager: sidebarManagers.filterManager,
                settings: settings,
                mediaControlsManager: sidebarManagers.mediaControlsManager,
                autoArchiveManager: appDelegate.autoArchiveManager,
                windowManager: appDelegate.windowManager,
            ),
            readerModeManager: appDelegate.readerModeManager,
            undoRedoManager: appDelegate.undoRedoManager,
            calendarManager: appDelegate.calendarManager,
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
            agentChatManager: appDelegate.agentChatManager,
            visualFeedbackManager: appDelegate.visualFeedbackManager,
            thoughtStreamStore: appDelegate.thoughtStreamStore,
            humanInterventionManager: appDelegate.humanInterventionManager,
            customSearchEngineManager: appDelegate.customSearchEngineManager,
            appUpdateManager: appDelegate.appUpdateManager,
            guidedTourManager: GuidedTourManager(),
        )

        setupSplitViewController(window: window)

        guard let contentView = window.contentView else { preconditionFailure() }
        setupBackgroundView(contentView: contentView)
        // Detail tray added before sidebar overlay so it renders below the overlay sidebar.
        setupDetailTrayContainer(contentView: contentView)
        setupSidebarOverlayContainer(contentView: contentView)
        setupEdgeExtensionBackground(contentView: contentView)
        setupOverlayView(contentView: contentView)
        setupSidebarTrackingRegion(contentView: contentView)
        setupToolbar(window: window)
        setupSidebarTrackingAdapters()
        setupUndoRedoMonitor()

        observeSidebarState()
        observeInspectorState()
        observeSidebarMode()
        observeWindowState()
        observeWebsiteColor()
        observeDetailTrayState()
        observeActiveTabForEdgeSampling()
        observeSpaceLockState()
        setupWindowSharingObserver()
        commandLensManager.setup()

        // To run drag simulation tests, uncomment the following:
        // #if DEBUG
        // DragSimulator.shared.runTestSequence(
        //     dragCoordinator: sidebarManagers.dragCoordinator,
        //     layoutManager: sidebarManagers.layoutManager,
        //     delay: 3.0
        // )
        // #endif
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Setup

    private func setupSplitViewController(window: NSWindow) {
        splitViewController.splitView.isVertical = true

        splitViewController.onToggleSidebar = { [weak self] in
            self?.toggleSidebar(nil)
        }
        splitViewController.onToggleInspector = { [weak self] in
            self?.toggleInspector()
        }

        let sidebarVC = NSHostingController(rootView: SidebarContentView().refraxEnvironment(environment))
        let contentVC = NSHostingController(rootView: MainContentView().refraxEnvironment(environment))
        let inspectorVC = NSHostingController(rootView: ReferencePaneContentView().refraxEnvironment(environment))

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        let contentItem = NSSplitViewItem(viewController: contentVC)
        let inspectorItem = NSSplitViewItem(inspectorWithViewController: inspectorVC)

        sidebarItem.minimumThickness = Constants.Layout.sidebarMinWidth
        sidebarItem.maximumThickness = Constants.Layout.sidebarMaxWidth
        sidebarItem.canCollapse = true
        sidebarItem.revealsOnEdgeHoverInFullscreen = false

        contentItem.minimumThickness = 400

        inspectorItem.isCollapsed = true
        inspectorItem.minimumThickness = Constants.Layout.inspectorMinWidth
        inspectorItem.maximumThickness = Constants.Layout.inspectorMaxWidth
        inspectorItem.canCollapse = true

        splitViewController.insertSplitViewItem(sidebarItem, at: 0)
        splitViewController.insertSplitViewItem(contentItem, at: 1)
        splitViewController.insertSplitViewItem(inspectorItem, at: 2)

        window.contentViewController = splitViewController

        NSLayoutConstraint.activate([
            splitViewController.view.heightAnchor.constraint(greaterThanOrEqualToConstant: 400),
        ])

        // Set default thicknesses (restoration will override if applicable)
        sidebarItem.preferredThicknessFraction = 0
        inspectorItem.preferredThicknessFraction = 0

        // Set divider positions using window's content rect (avoids forcing layout)
        let contentWidth = window.contentLayoutRect.width
        splitViewController.splitView.setPosition(Constants.Layout.sidebarDefaultWidth, ofDividerAt: 0)
        splitViewController.splitView.setPosition(
            contentWidth - Constants.Layout.inspectorDefaultWidth,
            ofDividerAt: 1,
        )

        windowState.sidebarThickness = Constants.Layout.sidebarDefaultWidth
        windowState.referencePaneDockedWidth = Constants.Layout.inspectorDefaultWidth
        lastCollapsedThickness = Constants.Layout.sidebarDefaultWidth

        // Start with inspector collapsed to prevent the frame observer from saving
        // an incorrect width before window restoration runs
        inspectorItem.isCollapsed = true
        windowState.isInspectorCollapsed = true

        // To run performance profiling, uncomment the following:
        // schedulePerformanceTest()

        // DEBUG: Run drag overlay mode test (uncomment to test)
        // scheduleDragOverlayTest()
    }

    private func setupBackgroundView(contentView: NSView) {
        backgroundView.frame = contentView.bounds
        backgroundView.autoresizingMask = [.width, .height]

        contentView.addSubview(backgroundView, positioned: .below, relativeTo: nil)
    }

    private func setupOverlayView(contentView: NSView) {
        overlayView = TransparentHostingView(rootView: OverlayContainer().refraxEnvironment(environment)) { [unowned self] in
            !windowState.showsCommandLens
                && !windowState.showsAddressLens
                && !windowState.showsCompactAddressBar
                && windowState.lockedSpaceRequiringAuth == nil
                && !windowState.isHoveringOverlayNotification
                && environment.screenshotCoordinator.currentPreview == nil
                && environment.recordingCoordinator.currentPreview == nil
        }

        contentView.addSubview(overlayView)
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: contentView.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    /// Sets up the AppKit-animated sidebar overlay container.
    ///
    /// ## Layout Structure
    ///
    /// The overlay mimics the real sidebar's visual appearance with proper padding
    /// so rounded corners are visible and the detail tray positions correctly.
    ///
    /// ```
    /// Window edge (x=0)
    /// │
    /// │←────────── Container (sidebarWidth + padding) ──────────→│
    /// │ padding │←──────── Glass (sidebarWidth) ────────────────→│
    /// │   8px   │ SwiftUI content (sidebarThickness)             │
    /// │         │                                                │
    ///
    /// When hidden (translated left by containerWidth):
    /// │←── Container ──→│ Window edge
    ///          Glass ───→│
    /// (entirely off-screen)
    /// ```
    ///
    /// The glass has `padding` inset on the left so rounded corners are visible,
    /// and fills to the container's trailing edge. Container width = sidebarWidth + padding.
    /// Translation when hidden = -containerWidth to fully hide the glass off-screen.
    private func setupSidebarOverlayContainer(contentView: NSView) {
        let padding = Constants.SidebarAnimation.glassEffectPadding
        let sidebarWidth = windowState.sidebarThickness
        let containerWidth = sidebarWidth + padding

        let container = SidebarOverlayContainerView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Track cursor presence to conditionally block WebKit mouse events
        container.onCursorPresenceChanged = { [weak self] isInside in
            guard let self else { return }
            isCursorInSidebarOverlay = isInside
            updateOverlayEventBlocking()
        }

        guard let glassViewClass = NSClassFromString("NSContainerConcentricGlassEffectView") as? NSGlassEffectView.Type else {
            setupSidebarOverlayContainerFallback(contentView: contentView)
            return
        }
        let glassView = glassViewClass.init()
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.cornerRadius = Constants.SidebarAnimation.glassCornerRadius
        glassView.setValue(20.0, forKey: "concentricMinimumCornerRadius")

        let sidebarView = SidebarOverlayContent()
            .refraxEnvironment(environment)

        let hostingView = NSHostingView(rootView: sidebarView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        glassView.contentView = hostingView
        container.addSubview(glassView)

        // Glass inset from left by padding (for rounded corner visibility),
        // fills to trailing edge. Vertical padding keeps glass below toolbar.
        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            glassView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            glassView.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            glassView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
        ])

        contentView.addSubview(container)

        let widthConstraint = container.widthAnchor.constraint(equalToConstant: containerWidth)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            container.topAnchor.constraint(equalTo: contentView.topAnchor),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            widthConstraint,
        ])

        container.isHidden = true
        if let layer = container.layer {
            layer.transform = CATransform3DMakeTranslation(-containerWidth, 0, 0)
        }

        sidebarOverlayContainer = container
        sidebarOverlayGlassView = glassView
        sidebarOverlayWidthConstraint = widthConstraint
        updateSidebarOverlayTint()
    }

    /// Fallback setup using regular NSGlassEffectView when private class unavailable.
    /// See `setupSidebarOverlayContainer` for layout documentation.
    private func setupSidebarOverlayContainerFallback(contentView: NSView) {
        let padding = Constants.SidebarAnimation.glassEffectPadding
        let sidebarWidth = windowState.sidebarThickness
        let containerWidth = sidebarWidth + padding

        let container = SidebarOverlayContainerView()
        container.translatesAutoresizingMaskIntoConstraints = false

        // Track cursor presence to conditionally block WebKit mouse events
        container.onCursorPresenceChanged = { [weak self] isInside in
            guard let self else { return }
            isCursorInSidebarOverlay = isInside
            updateOverlayEventBlocking()
        }

        let glassView = NSGlassEffectView()
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.cornerRadius = Constants.SidebarAnimation.glassCornerRadius

        let sidebarView = SidebarOverlayContent()
            .refraxEnvironment(environment)

        let hostingView = NSHostingView(rootView: sidebarView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        glassView.contentView = hostingView
        container.addSubview(glassView)

        // Glass inset from left by padding (for rounded corner visibility),
        // fills to trailing edge. Vertical padding keeps glass below toolbar.
        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            glassView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            glassView.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            glassView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
        ])

        contentView.addSubview(container)

        let widthConstraint = container.widthAnchor.constraint(equalToConstant: containerWidth)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            container.topAnchor.constraint(equalTo: contentView.topAnchor),
            container.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            widthConstraint,
        ])

        container.isHidden = true
        if let layer = container.layer {
            layer.transform = CATransform3DMakeTranslation(-containerWidth, 0, 0)
        }

        sidebarOverlayContainer = container
        sidebarOverlayGlassView = glassView
        sidebarOverlayWidthConstraint = widthConstraint
        updateSidebarOverlayTint()
    }

    /// Sets up the edge extension background view for compact sidebar mode.
    ///
    /// The edge extension background is positioned behind the sidebar overlay and displays
    /// sampled colors from the webview's left edge as a blurred gradient. This creates an
    /// ambient background effect that makes the compact sidebar feel like a natural extension
    /// of the web content.
    ///
    /// ## Layout
    ///
    /// - Positioned at leading edge of window
    /// - Width: 56px (compact sidebar width + glass padding)
    /// - Height: Full window height
    /// - Z-order: Below sidebar overlay, above content
    private func setupEdgeExtensionBackground(contentView: NSView) {
        let backgroundView = EdgeExtensionBackgroundView()
        backgroundView.translatesAutoresizingMaskIntoConstraints = false

        // Insert below sidebar overlay (so overlay glass sits on top)
        if let overlayContainer = sidebarOverlayContainer {
            contentView.addSubview(backgroundView, positioned: .below, relativeTo: overlayContainer)
        } else {
            contentView.addSubview(backgroundView)
        }

        let width = Constants.SidebarAnimation.compactWidth + Constants.SidebarAnimation.glassEffectPadding

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backgroundView.topAnchor.constraint(equalTo: contentView.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            backgroundView.widthAnchor.constraint(equalToConstant: width),
        ])

        // Start hidden - will be shown when entering compact mode
        backgroundView.isHidden = true
        backgroundView.alphaValue = 0

        edgeExtensionBackgroundView = backgroundView
    }

    private func setupSidebarTrackingRegion(contentView: NSView) {
        let trackingView = SidebarHoverTrackingView()
        trackingView.translatesAutoresizingMaskIntoConstraints = false

        trackingView.onMouseMoved = { [weak self] locationInWindow in
            guard let self else { return }
            handleMouseMoved(at: locationInWindow)
        }

        trackingView.onMouseExited = { [weak self] in
            guard let self else { return }
            handleMouseExited()
        }

        trackingView.onOverlayTriggeredChanged = { [weak self] _ in
            guard let self else { return }
            updateOverlayEventBlocking()
        }

        contentView.addSubview(trackingView)
        sidebarTrackingView = trackingView

        let widthConstraint = trackingView.widthAnchor.constraint(equalToConstant: 0)
        trackingViewWidthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            trackingView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            trackingView.topAnchor.constraint(equalTo: contentView.topAnchor),
            trackingView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            widthConstraint,
        ])
    }

    private func setupToolbar(window: NSWindow) {
        let toolbar = NSToolbar(identifier: NSToolbar.mainIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false

        window.toolbar = toolbar
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

    /// Opens the address lens
    func openAddressLens() {
        windowState.openAddressLens()
    }

    /// Toggles the sidebar visibility.
    @objc
    func toggleSidebar(_: Any?) {
        guard !isAnimatingSidebarTransition else { return }

        let sidebarItem = splitViewController.splitViewItems[0]

        cancelTutorialPeek()

        if isSidebarOverlayVisible {
            expandSidebarFromOverlay()
            return
        }

        if !sidebarItem.isCollapsed {
            collapseSidebarWithAnimation()
        } else {
            isAnimatingSidebarTransition = true

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true

                sidebarItem.animator().isCollapsed = false
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    self?.isAnimatingSidebarTransition = false
                }
            }
        }
    }

    /// Collapses the sidebar with smooth toolbar item animation.
    private func collapseSidebarWithAnimation() {
        let sidebarItem = splitViewController.splitViewItems[0]

        let sidebarWidth = sidebarItem.viewController.view.frame.width
        let dividerPosition = sidebarWidth + sidebarDividerOffset

        if let adapter = splitViewSidebarTrackingAdapter {
            adapter.overrideDividerPosition = dividerPosition
        }

        isAnimatingCollapse = true
        isAnimatingSidebarTransition = true

        applyToolbarItemsOffset(forOverlayProgress: 1.0, animated: false)
        applyTrafficLightVisibility(1.0, animated: false)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            sidebarItem.animator().isCollapsed = true

            applyToolbarItemsOffset(forOverlayProgress: 0.0, animated: true)
            applyTrafficLightVisibility(0.0, animated: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.isAnimatingCollapse = false
                self?.isAnimatingSidebarTransition = false
                // Set toolbar items to isHidden to prevent clicks on transparent items
                self?.hideToolbarItemsInstantly()
            }
        }
    }

    /// Expands the real sidebar while keeping the overlay visible.
    private func expandSidebarFromOverlay() {
        let sidebarItem = splitViewController.splitViewItems[0]
        let sidebarView = sidebarItem.viewController.view

        isAnimatingSidebarTransition = true
        overlayAnimationGeneration &+= 1

        hideTask?.cancel()
        hideTask = nil
        sidebarExpansionTask?.cancel()

        let activationWidth = Constants.SidebarAnimation.activationWidth
        trackingViewWidthConstraint?.constant = activationWidth
        updateTrackingAreaImmediately()
        isAnimatingToVisible = false
        isOverlayTriggered = false
        sidebarTrackingView?.isOverlayTriggered = false

        isTransitioningFromOverlay = true

        for subview in sidebarView.subviews {
            subview.isHidden = true
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            sidebarItem.animator().isCollapsed = false
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }

                self.isTransitioningFromOverlay = false
                self.isAnimatingSidebarTransition = false

                for subview in sidebarView.subviews {
                    subview.isHidden = false
                }

                self.hideSidebarOverlayInstantly()

                self.clearToolbarItemTransforms()

                // Exit compact traffic light mode if active
                self.exitCompactTrafficLightMode(animated: false)

                self.restoreSplitViewSidebarTracking()
                self.updateTrafficLightsForExpandedSidebar(animated: false)

                // Move detail tray to expanded sidebar position (16px gap)
                self.updateDetailTrayPosition(animated: true)

                // Hide edge extension background when sidebar expands
                self.hideEdgeExtensionBackground(animated: false)
            }
        }
    }

    /// Toggles the inspector/reference pane visibility.
    ///
    /// Inspector state is per-window (saved via window restoration).
    /// If a separate reference pane window is open, brings it to front instead of toggling.
    func toggleInspector() {
        // If a separate reference pane window is open, bring it to front
        if tabManager.windowManager.bringReferencePaneWindowToFront(for: self) {
            return
        }

        guard splitViewController.splitViewItems.count > 2 else { return }
        let inspectorItem = splitViewController.splitViewItems[2]

        // Save width before collapsing
        if !inspectorItem.isCollapsed {
            let currentWidth = inspectorItem.viewController.view.frame.width
            if currentWidth > 0 {
                windowState.referencePaneDockedWidth = currentWidth
            }
        }

        // Toggle state
        windowState.isInspectorCollapsed.toggle()

        // Apply the change with animation
        updateInspectorCollapsed(windowState.isInspectorCollapsed)
    }

    /// Reloads the active page.
    /// Stops loading the active page.
    func stopLoading() {
        windowState.activeWebPage?.stopLoading()
    }

    func reloadPage() {
        _ = windowState.activeWebPage?.reload()
    }

    /// Reloads the active page without using cache.
    func reloadPageFromOrigin() {
        _ = windowState.activeWebPage?.reload(fromOrigin: true)
    }

    /// Navigates to the next tab in the list
    func selectNextTab() {
        tabManager.selectNextTab()
    }

    /// Navigates to the previous tab in the list
    func selectPreviousTab() {
        tabManager.selectPreviousTab()
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
        cancellables.removeAll()
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

        hideTask?.cancel()
        hideTask = nil

        tutorialPeekTask?.cancel()
        tutorialPeekTask = nil

        sidebarExpansionTask?.cancel()
        sidebarExpansionTask = nil
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
        case #selector(toggleLayoutMode(_:)):
            canEnterLayoutMode
        default:
            true
        }
    }

    /// Whether layout mode can be entered with the current active tab.
    ///
    /// Layout mode is disabled when:
    /// - No tab is active
    /// - The active tab is a live favorite (favorites have special display rules)
    var canEnterLayoutMode: Bool {
        guard let activeTab = windowState.activeTab else { return false }
        return !activeTab.isLiveFavorite
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
                if isRedo, undoManager.canRedo { return event }
                if !isRedo, undoManager.canUndo { return event }
            }

            if let firstResponder = window?.firstResponder,
               let undoManager = firstResponder.undoManager {
                if isRedo, undoManager.canRedo { return event }
                if !isRedo, undoManager.canUndo { return event }
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

// MARK: - Mouse Event Handling

extension RefraxWindowController {
    override func mouseEntered(with event: NSEvent) {
        // Check if this is the compact traffic light tracking area
        if let userInfo = event.trackingArea?.userInfo as? [String: Any],
           userInfo["compactTrafficLights"] as? Bool == true {
            handleCompactTrafficLightMouseEntered()
            return
        }

        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        // Check if this is the compact traffic light tracking area
        if let userInfo = event.trackingArea?.userInfo as? [String: Any],
           userInfo["compactTrafficLights"] as? Bool == true {
            handleCompactTrafficLightMouseExited()
            return
        }

        super.mouseExited(with: event)
    }
}

// MARK: - Debug Utilities

#if DEBUG
    extension RefraxWindowController {
        func debugPrintWindowHierarchy() {
            guard let window else {
                print("🔴 DEBUG: No window")
                return
            }

            print("═══════════════════════════════════════════════════════════════")
            print("🔍 WINDOW HIERARCHY DEBUG")
            print("═══════════════════════════════════════════════════════════════")

            print("\n📦 WINDOW: \(type(of: window)) - \(window)")
            print("   Frame: \(window.frame)")
            print("   StyleMask: \(window.styleMask)")

            if let themeFrame = window.contentView?.superview {
                print("\n📦 THEME FRAME: \(type(of: themeFrame))")
                printViewHierarchy(themeFrame, indent: 3, maxDepth: 6)
            }

            print("\n🚦 TRAFFIC LIGHTS:")
            for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                if let button = window.standardWindowButton(buttonType) {
                    print("   \(buttonType): \(type(of: button))")
                    print("      Frame: \(button.frame)")
                    print("      Superview: \(type(of: button.superview as Any)) - \(button.superview?.frame ?? .zero)")
                    if let grandparent = button.superview?.superview {
                        print("      Grandparent: \(type(of: grandparent)) - \(grandparent.frame)")
                    }
                }
            }

            if let toolbar = window.toolbar {
                print("\n🔧 TOOLBAR: \(type(of: toolbar))")
                print("   Identifier: \(toolbar.identifier)")
                print("   Items: \(toolbar.items.count)")

                if let toolbarView = toolbar.value(forKey: "_toolbarView") as? NSView {
                    print("\n   TOOLBAR VIEW: \(type(of: toolbarView))")
                    print("      Frame: \(toolbarView.frame)")
                    printViewHierarchy(toolbarView, indent: 6, maxDepth: 4)
                }

                for item in toolbar.items {
                    print("\n   📍 ITEM: \(item.itemIdentifier.rawValue)")
                    print("      Class: \(type(of: item))")
                    print("      isBordered: \(item.isBordered)")

                    if let itemViewer = item.value(forKey: "_itemViewer") as? NSView {
                        print("      _itemViewer: \(type(of: itemViewer))")
                        print("         Frame: \(itemViewer.frame)")
                        printViewProperties(itemViewer, indent: 9)
                    }

                    if let view = item.view {
                        print("      view: \(type(of: view))")
                        print("         Frame: \(view.frame)")
                    }
                }
            }

            print("\n═══════════════════════════════════════════════════════════════")
        }

        private func printViewHierarchy(_ view: NSView, indent: Int, maxDepth: Int) {
            guard maxDepth > 0 else { return }

            let prefix = String(repeating: " ", count: indent)
            print("\(prefix)├─ \(type(of: view)) - \(view.frame.size)")

            if view.responds(to: NSSelectorFromString("inGlassSidebar")) {
                if let value = view.value(forKey: "inGlassSidebar") as? Bool {
                    print("\(prefix)│  inGlassSidebar: \(value)")
                }
            }
            if view.responds(to: NSSelectorFromString("transparentBackground")) {
                if let value = view.value(forKey: "transparentBackground") as? Bool {
                    print("\(prefix)│  transparentBackground: \(value)")
                }
            }
            if view.responds(to: NSSelectorFromString("glassBehavior")) {
                if let value = view.value(forKey: "glassBehavior") as? Int {
                    print("\(prefix)│  glassBehavior: \(value)")
                }
            }

            for subview in view.subviews {
                printViewHierarchy(subview, indent: indent + 3, maxDepth: maxDepth - 1)
            }
        }

        private func printViewProperties(_ view: NSView, indent: Int) {
            let prefix = String(repeating: " ", count: indent)

            let properties = [
                "inGlassSidebar", "transparentBackground", "glassBehavior",
                "firstItemInGlassGroup", "lastItemInGlassGroup", "associatedPlatter",
            ]

            for prop in properties {
                if view.responds(to: NSSelectorFromString(prop)) {
                    if let value = view.value(forKey: prop) {
                        print("\(prefix)\(prop): \(value)")
                    }
                }
            }
        }

        func debugPrintClassInfo(_ object: AnyObject, label: String) {
            print("\n🔬 CLASS INFO: \(label)")
            print("   Type: \(type(of: object))")

            var currentClass: AnyClass? = type(of: object)
            var classChain: [String] = []
            while let cls = currentClass {
                classChain.append(NSStringFromClass(cls))
                currentClass = class_getSuperclass(cls)
            }
            print("   Hierarchy: \(classChain.joined(separator: " → "))")
        }

        func debugLogToolbarPositions(context: String) {
            guard let toolbar = window?.toolbar, let toolbarView else { return }

            let sidebarItem = splitViewController.splitViewItems[0]
            let sidebarFrame = sidebarItem.viewController.view.frame
            let adapterPosition = splitViewSidebarTrackingAdapter?.sidebarDividerPosition ?? -1
            let overridePosition = splitViewSidebarTrackingAdapter?.overrideDividerPosition ?? -1

            print("═══════════════════════════════════════════════════════════════")
            print("🔍 \(context)")
            print("───────────────────────────────────────────────────────────────")
            print("   Sidebar collapsed: \(sidebarItem.isCollapsed)")
            print("   Sidebar frame.width: \(sidebarFrame.width)")
            print("   Adapter sidebarDividerPosition: \(adapterPosition)")
            print("   Adapter overrideDividerPosition: \(overridePosition)")
            print("   ToolbarView.sidebarDividerPosition: \(toolbarView.sidebarDividerPosition)")
            print("───────────────────────────────────────────────────────────────")

            for item in toolbar.items where sidebarToolbarItemIdentifiers.contains(item.itemIdentifier) {
                let viewer = item._itemViewer
                let viewerFrame = viewer.frame
                let windowFrame = viewer.convert(viewer.bounds, to: nil)

                print("   📍 \(item.itemIdentifier.rawValue)")
                print("      viewer.frame: \(viewerFrame)")
                print("      viewer in window: \(windowFrame)")
                print("      inGlassSidebar: \(viewer.inGlassSidebar)")
                if let transform = viewer.layer?.transform, !CATransform3DIsIdentity(transform) {
                    print("      layer.transform.tx: \(transform.m41)")
                }
            }
            print("═══════════════════════════════════════════════════════════════\n")
        }

        func debugPrintSidebarPosition() {
            guard let window, let themeFrame else {
                print("🔴 No window or themeFrame")
                return
            }

            let sidebarItem = splitViewController.splitViewItems[0]
            let sidebarVC = sidebarItem.viewController
            let sidebarView = sidebarVC.view

            print("═══════════════════════════════════════════════════════════════")
            print("📐 SIDEBAR POSITION DEBUG")
            print("───────────────────────────────────────────────────────────────")
            print("   Window frame: \(window.frame)")
            print("   ContentView frame: \(window.contentView?.frame ?? .zero)")
            print("   SplitView frame: \(splitViewController.splitView.frame)")
            print("───────────────────────────────────────────────────────────────")
            print("   Sidebar VC view frame: \(sidebarView.frame)")
            print("   Sidebar VC view in window: \(sidebarView.convert(sidebarView.bounds, to: nil))")
            print("   Sidebar safeAreaInsets: \(sidebarView.safeAreaInsets)")
            print("   Sidebar safeAreaRect: \(sidebarView.safeAreaRect)")
            print("───────────────────────────────────────────────────────────────")
            print("   ThemeFrame titlebarRect: \(themeFrame.titlebarRect())")
            print("   ThemeFrame titlebarRectIncludingToolbar: \(themeFrame.titlebarRectIncludingToolbar())")
            print("   ThemeFrame contentRect: \(themeFrame.contentRect())")
            print("   ThemeFrame _titlebarHeight: \(themeFrame._titlebarHeight())")
            print("───────────────────────────────────────────────────────────────")

            if let firstSubview = sidebarView.subviews.first {
                print("   First subview frame: \(firstSubview.frame)")
                print("   First subview in window: \(firstSubview.convert(firstSubview.bounds, to: nil))")
            }

            print("───────────────────────────────────────────────────────────────")
            print("   Superview chain from sidebar:")
            var currentView: NSView? = sidebarView
            var depth = 0
            while let view = currentView, depth < 10 {
                let className = String(describing: type(of: view))
                print("     \(depth): \(className) - frame: \(view.frame)")
                currentView = view.superview
                depth += 1
            }

            print("═══════════════════════════════════════════════════════════════\n")
        }
    }
#endif
