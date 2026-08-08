import AppKit
import Observation
import SwiftUI

// MARK: - Window State

/// UI state for an individual browser window.
///
/// Each Refrax window maintains its own `WindowState` instance that controls
/// window-specific interface elements while sharing tab data through the global
/// ``TabManager``. This separation enables multiple windows to display different
/// views of the same underlying tabs and spaces.
///
/// ## Managed State
///
/// - **Lenses**: Command lens (Cmd+K) and address bar lens for quick actions
/// - **Layout**: Sidebar and inspector visibility, widths, and collapse states
/// - **Overlays**: Sidebar hover overlay animation and positioning
/// - **Drag Operations**: Tracks content being dragged for visual feedback
/// - **Layout Mode**: Enable/disable interface customization mode
///
/// ## Window Independence
///
/// Each window can have a different active tab, collapsed panels, and lens visibility.
/// For example, one window might show the command lens while another displays
/// web content normally.
///
/// ## Navigation State
///
/// WindowState stores only IDs for active space/tab/reference tab. Actual objects
/// are retrieved via `BrowserState.tab(for:)` which provides O(1) lookup.
/// Convenience properties (`activeTab`, `activeSpace`, `activePage`) handle
/// the lookup automatically.
///
/// ## Environment Access
///
/// WindowState is injected into the view hierarchy via both:
/// - `.environment(\.windowState, windowState)` for descendant views
/// - `.focusedSceneValue(\.windowState, windowState)` for menu commands
///
/// - Note: This state persists only during the window's lifetime. Panel collapse
///   states are saved via `@SceneStorage` in ``ContentView`` for restoration.
@Observable
final class WindowState {
    private let settings: BrowserSettings

    /// Reference to the browser state for O(1) tab lookups.
    @ObservationIgnored
    private unowned let browserState: BrowserState

    /// Reference to the NSWindow containing this state.
    ///
    /// Set during window controller initialization. Used to detect when this window
    /// becomes key for multi-window ownership tracking.
    @ObservationIgnored
    weak var window: NSWindow?

    // MARK: - Background

    /// The source of the current window background color.
    enum ColorSource: Equatable {
        /// Color from a website's theme color or sampled page top color.
        case website
        /// Color from the active space.
        case space
        /// Custom color set by the user.
        case custom
        /// No color source (transparent).
        case none
    }

    /// A resolved background color paired with its source.
    struct ResolvedBackground: Equatable {
        let color: Color.Components
        let source: ColorSource
    }

    /// Debounced website color to prevent rapid flashing during navigation.
    ///
    /// Updated via `updateWebsiteColor()` with a 200ms debounce.
    private(set) var debouncedWebsiteColor: Color.Components?

    /// Task for debouncing website color updates.
    @ObservationIgnored
    private var websiteColorDebounceTask: Task<Void, Never>?

    /// The resolved background color and its source.
    ///
    /// Priority system:
    /// 1. Per-site explicit allow (overrides space coloring)
    /// 2. Space coloring (if enabled and space has color)
    /// 3. Website coloring (if globally enabled)
    /// 4. Custom window color
    /// 5. Transparent
    var resolvedBackground: ResolvedBackground {
        let activeURL = activeWebPage?.url
        let coordinator = browserState.siteSettingsCoordinator

        // Priority 1: Per-site explicit allow - website color overrides everything
        if settings.enableWebsiteWindowColoring,
           let webColor = debouncedWebsiteColor,
           let url = activeURL,
           coordinator.websiteColoringOverridesSpace(for: url) {
            return ResolvedBackground(color: webColor, source: .website)
        }

        // Priority 2: Space coloring
        if settings.enableSpaceWindowColoring,
           let currentSpace = activeSpace,
           let colorComponents = Color.resolveStoredColorComponents(currentSpace.colorHex) {
            return ResolvedBackground(color: colorComponents, source: .space)
        }

        // Priority 3: Website coloring (global default, if not explicitly denied)
        if let webColor = debouncedWebsiteColor,
           let url = activeURL,
           coordinator.shouldApplyWebsiteColoring(for: url) {
            return ResolvedBackground(color: webColor, source: .website)
        }

        // Priority 4: Custom window color
        if let customColor = settings.customWindowBackgroundColor {
            return ResolvedBackground(color: customColor, source: .custom)
        }

        // Priority 5: Transparent
        return ResolvedBackground(color: Color.clear.components, source: .none)
    }

    /// The computed background color.
    ///
    /// For the source of this color, use ``resolvedBackground``.
    var backgroundColor: Color.Components {
        resolvedBackground.color
    }

    /// The source of the current background color.
    var backgroundColorSource: ColorSource {
        resolvedBackground.source
    }

    /// Updates the website color with debouncing to prevent rapid changes.
    ///
    /// Call this when the active page's effective color changes.
    /// Changes are debounced by 200ms to prevent flashing during navigation.
    ///
    /// Does nothing if website window coloring is disabled in settings.
    ///
    /// - Parameter color: The new website color, or nil to clear.
    func updateWebsiteColor(_ color: Color?) {
        // Skip entirely when website coloring is disabled - no point computing/storing
        // colors that won't be used. This prevents unnecessary observation tracking.
        guard settings.enableWebsiteWindowColoring else {
            // Clear any existing color if setting was just disabled
            if debouncedWebsiteColor != nil {
                debouncedWebsiteColor = nil
            }
            return
        }

        websiteColorDebounceTask?.cancel()

        websiteColorDebounceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                return // Cancelled
            }

            guard let self else { return }

            let newComponents = color?.components
            if debouncedWebsiteColor != newComponents {
                // Don't use withAnimation here - it causes per-frame body updates for all
                // observing views during the 0.3s animation. Views that need animated
                // transitions should use .animation() modifier on the rendered color.
                debouncedWebsiteColor = newComponents
            }
        }
    }

    /// Clears the website color immediately without debouncing.
    ///
    /// Use when switching tabs or spaces where the old color should not linger.
    func clearWebsiteColor() {
        websiteColorDebounceTask?.cancel()
        websiteColorDebounceTask = nil
        debouncedWebsiteColor = nil
    }
    
    // MARK: - Per-Window Navigation State

    /// Active space ID for this window.
    ///
    /// Use `activeSpace` property to get the actual Space object.
    var activeSpaceID: Space.ID?

    /// Active space for this window.
    ///
    /// Uses O(1) lookup via `BrowserState.space(for:)`.
    var activeSpace: Space? {
        guard let activeSpaceID else { return nil }
        return browserState.space(for: activeSpaceID)
    }

    /// Returns the active space if it requires authentication, otherwise nil.
    ///
    /// Use this to conditionally show the lock overlay at window level.
    /// The overlay should cover the entire window including sidebar to prevent
    /// information leakage from tab titles and group names.
    var lockedSpaceRequiringAuth: Space? {
        guard let space = activeSpace else { return nil }
        return browserState.spaceLockManager.requiresAuth(for: space) ? space : nil
    }

    /// Whether the active space is locked and requires authentication.
    ///
    /// This is a Sendable-safe alternative to `lockedSpaceRequiringAuth` for use
    /// in async observation contexts where Space (a PersistentModel) cannot be used.
    var isSpaceLocked: Bool {
        lockedSpaceRequiringAuth != nil
    }

    /// Version counter bumped by the AppKit lock state observer to ensure the
    /// SwiftUI overlay re-renders reliably.
    ///
    /// The lock overlay's observation chain crosses multiple `@Observable` objects
    /// via `@ObservationIgnored` intermediates (`browserState`, `spaceLockManager`).
    /// In `NSHostingView` contexts, this transitive chain may not trigger SwiftUI
    /// re-renders. This counter provides a direct observation path on `WindowState`
    /// itself, bridging the reliable AppKit `Observations {}` handler to SwiftUI.
    var spaceLockVersion: Int = 0

    var activeSpaceTabs: [Tab] {
        activeSpace?.tabs ?? []
    }
    
    var activeSpaceMainTabs: [Tab] {
        activeSpace?.mainTabs ?? []
    }
    
    var activeSpacePinnedTabs: [Tab] {
        activeSpace?.pinnedTabs ?? []
    }
    
    var activeSpaceGroups: [TabGroup] {
        activeSpace?.groups ?? []
    }

    /// Active tab IDs per space (allows remembering position when switching spaces).
    ///
    /// When switching back to a space, the previously active tab is restored.
    private var _activeTabIDs: [Space.ID: Tab.ID] = [:]

    /// Previous active tab IDs per space (for "go back" when closing tabs).
    ///
    /// Tracks the tab that was active before the current one in each space.
    /// When the active tab is closed, we prefer activating this tab.
    @ObservationIgnored
    private var _previousActiveTabIDs: [Space.ID: Tab.ID] = [:]

    /// Active live favorite tab ID for this window.
    ///
    /// When set, a live favorite tab takes priority over the space's active tab.
    /// Managed internally via `setActiveTab(_:)`.
    private var _activeLiveFavoriteTabID: Tab.ID?

    /// Active tab ID for this window.
    ///
    /// Returns the live favorite tab ID if one is active, otherwise returns
    /// the active space's tab ID. This unified property handles both live favorites
    /// and space-bound tabs transparently.
    ///
    /// - Note: Reading this does NOT create dictionary observation. Views should
    ///   observe `activeTabVersion` to know when to recheck this value.
    var activeTabID: Tab.ID? {
        // Live favorite takes priority if set
        if let liveFavoriteID = _activeLiveFavoriteTabID {
            return liveFavoriteID
        }
        // Otherwise, return space's active tab
        guard let activeSpaceID else { return nil }
        return _activeTabIDs[activeSpaceID]
    }

    /// Active tab ID persisted for a specific space (ignoring live favorites).
    ///
    /// Used internally for per-space tab tracking when switching spaces.
    private func persistedActiveTabID(for spaceID: Space.ID) -> Tab.ID? {
        _activeTabIDs[spaceID]
    }

    /// Active tab for this window.
    ///
    /// Returns the currently displayed tab - either a live favorite or the
    /// space's active tab. Uses O(1) lookup via `BrowserState.tab(for:)`.
    var activeTab: Tab? {
        guard let tabID = activeTabID else { return nil }
        return browserState.tab(for: tabID)
    }

    /// Whether a live favorite tab is currently being displayed.
    ///
    /// This property directly checks the internal live favorite tracking state
    /// without accessing the Tab model, avoiding unnecessary observation dependencies
    /// in views that only need to know if a live favorite is active.
    var isShowingLiveFavorite: Bool {
        _activeLiveFavoriteTabID != nil
    }
    
    /// Active page ID for the currently active tab.
    ///
    /// For single-page tabs, this is the primary page.
    /// For multi-page tabs, this is the page the user last interacted with.
    var activePageID: TabPage.ID? {
        activePage?.id
    }
    
    /// Active page for the currently displayed tab.
    ///
    /// Returns the active tab's active page, which may be the primary page
    /// or a secondary page in multi-page layouts.
    var activePage: TabPage? {
        activeTab?.activePage
    }
    
    /// Active reference tab ID for this window.
    ///
    /// Reference tabs appear in the reference pane for side-by-side browsing.
    var activeReferenceTabID: Tab.ID?

    /// Active reference tab for this window.
    ///
    /// Uses O(1) lookup via `BrowserState.tab(for:)`.
    var activeReferenceTab: Tab? {
        guard let id = activeReferenceTabID else { return nil }
        return browserState.tab(for: id)
    }

    // MARK: - Focused Webpage Tracking

    /// The ID of the last-interacted webpage in this window.
    ///
    /// This tracks which webpage (from main content, split-view, or reference pane)
    /// the user last interacted with. Used by the address bar to show the correct
    /// URL and navigation state.
    ///
    /// ## Interaction Triggers
    /// - Clicking on a web view
    /// - Switching to a tab
    /// - Navigating within a page
    ///
    /// ## Fallback Behavior
    /// When nil or the referenced page is removed, falls back to:
    /// 1. Active tab's primary page (if single-page tab)
    /// 2. Active tab's active page (if split-view tab)
    /// 3. First reference tab's page (if no main tab)
    var focusedPageID: TabPage.ID?

    /// The focused webpage for address bar and navigation display.
    ///
    /// Returns the last-interacted webpage, or falls back to a sensible default
    /// if the focused page is no longer available or belongs to a hidden reference pane.
    var focusedWebPage: WebPage? {
        if let focusedPageID, let webPage = browserState.webPage(for: focusedPageID) {
            // If the inspector is collapsed, don't return reference tab pages
            // The address bar should show the active main tab instead
            if isInspectorCollapsed, webPage.tabPage.tab?.isReferenceTab == true {
                return fallbackWebPage
            }
            return webPage
        }
        return fallbackWebPage
    }
    
    /// Fallback webpage when focused page is unavailable.
    private var fallbackWebPage: WebPage? {
        guard let page = fallbackPage else { return nil }
        return browserState.webPage(for: page.id)
    }

    /// The focused TabPage for URL display.
    ///
    /// Returns the last-interacted page, or falls back to a sensible default.
    /// @ObservationIgnored to reduce observation dependencies.
    @ObservationIgnored
    var focusedPage: TabPage? {
        focusedWebPage?.tabPage ?? fallbackPage
    }

    /// Fallback page when focused page is unavailable.
    /// @ObservationIgnored to reduce observation dependencies.
    @ObservationIgnored
    private var fallbackPage: TabPage? {
        if let activeTab {
            return activeTab.activePage
        }
        // Only fall back to reference tab if the reference pane is visible
        if !isInspectorCollapsed,
           let refTab = activeReferenceTab {
            return refTab.activePage
        }
        return nil
    }

    /// Records an interaction with a webpage.
    ///
    /// Call this when the user clicks on, navigates within, or otherwise
    /// interacts with a webpage. This updates the focused page for the
    /// address bar display.
    ///
    /// - Parameter pageID: The ID of the page that was interacted with.
    func recordInteraction(with pageID: TabPage.ID) {
        focusedPageID = pageID
    }

    /// Clears focus from a specific page if it's currently focused.
    ///
    /// Call this when a page is being removed to ensure the focus
    /// falls back to another available page.
    ///
    /// - Parameter pageID: The ID of the page being removed.
    func clearFocusIfNeeded(for pageID: TabPage.ID) {
        if focusedPageID == pageID {
            focusedPageID = nil
        }
    }

    /// The active WebPage for the currently displayed tab.
    ///
    /// Uses O(1) lookup via `BrowserState.webPage(for:)`.
    var activeWebPage: WebPage? {
        guard let page = activeTab?.activePage else { return nil }
        return browserState.webPage(for: page.id)
    }

    // MARK: - Lens State

    /// Currently visible lens, if any.
    ///
    /// When set, darkens the background and presents the lens interface for
    /// quick actions or address entry.
    private(set) var focusedLens: FocusedLens?
    
    /// Frame of the address bar in global coordinates (root of view hierarchy).
    ///
    /// Used to position the address lens overlay aligned with the address bar.
    var addressBarFrame: CGRect = .zero

    // MARK: - Split View State

    /// Whether the sidebar (vertical tabs) is collapsed.
    ///
    /// When collapsed, only the sidebar overlay appears on hover. When expanded,
    /// the sidebar is pinned open. Synced with `@SceneStorage` for persistence.
    var isSidebarCollapsed: Bool = false

    /// Whether the inspector (reference pane) is collapsed.
    ///
    /// The inspector shows side-by-side content when working with multiple sources.
    /// Synced with `@SceneStorage` for persistence across launches.
    var isInspectorCollapsed: Bool = true

    // MARK: - Sidebar Overlay State

    /// The effective sidebar mode for this window.
    ///
    /// Returns the global default from ``BrowserSettings/defaultSidebarMode``.
    var effectiveSidebarMode: SidebarMode {
        settings.defaultSidebarMode
    }

    // MARK: - Detail Tray State

    /// Current mode for the detail tray (downloads, bookmarks, history, or hidden).
    ///
    /// The detail tray is a secondary panel that slides in adjacent to the sidebar,
    /// providing quick access to downloads, bookmarks, and history without opening
    /// dedicated tabs. Uses Liquid Glass styling consistent with the sidebar overlay.
    var detailTrayMode: DetailTrayMode = .hidden

    /// Whether the detail tray is currently visible.
    var isDetailTrayVisible: Bool {
        detailTrayMode != .hidden
    }

    /// Trailing edge of the detail tray in window coordinates.
    ///
    /// Set by `RefraxWindowController` when the tray position changes. Used by views
    /// like `LinkHoverPreviewView` to avoid overlapping with the tray. A value of 0
    /// means the tray is hidden or not yet positioned.
    var detailTrayTrailingEdge: CGFloat = 0

    /// Trailing edge of the sidebar overlay in window coordinates.
    ///
    /// Set by `RefraxWindowController` when the sidebar overlay shows/hides.
    /// Accounts for compact strip width or full overlay width. A value of 0
    /// means the overlay is hidden or the sidebar is expanded (pinned).
    var sidebarOverlayTrailingEdge: CGFloat = 0

    /// Current width of the sidebar panel.
    ///
    /// Dynamically updated as the user resizes the sidebar. Persisted per
    /// window by AppKit state restoration and app-wide by `WindowGeometryStore`.
    var sidebarThickness: CGFloat = 300

    /// Tracks whether the tutorial peek animation has played this session.
    ///
    /// On first launch, the sidebar briefly peeks out to teach users about
    /// the hover interaction. This flag prevents repeated animations.
    var hasShownTutorialPeek = false

    // MARK: - Compact Tab Title Tooltip

    /// Frame of the currently hovered compact tab button in global coordinates.
    ///
    /// Used by CompactTabTitleOverlay to position the title tooltip adjacent
    /// to the tab when hovered.
    var compactTabTooltipFrame: CGRect = .zero

    /// Title to display in the compact tab tooltip.
    ///
    /// Set when hovering a compact tab button after the delay expires.
    /// Cleared when hover ends.
    private(set) var compactTabTooltipTitle: String?

    /// Centralized task for compact tab tooltip delay.
    ///
    /// Previously each CompactTabButton had its own `@State tooltipTask`, creating
    /// 100+ Task allocations for windows with many tabs. Now managed centrally.
    @ObservationIgnored
    private var compactTabTooltipTask: Task<Void, Never>?

    /// Delay before showing compact tab tooltip.
    private static let compactTabTooltipDelay: Duration = .milliseconds(200)

    /// Starts the tooltip hover delay for a compact tab.
    ///
    /// After the delay, the tooltip title will be set if the hover hasn't been cancelled.
    /// Frame should be updated separately via `compactTabTooltipFrame`.
    ///
    /// - Parameter title: The title to show in the tooltip.
    func startCompactTabTooltipHover(title: String) {
        compactTabTooltipTask?.cancel()

        let capturedTitle = title
        compactTabTooltipTask = Task {
            try? await Task.sleep(for: Self.compactTabTooltipDelay)
            guard !Task.isCancelled else { return }
            compactTabTooltipTitle = capturedTitle
        }
    }

    /// Ends the tooltip hover, cancelling any pending delay and clearing the title.
    func endCompactTabTooltipHover() {
        compactTabTooltipTask?.cancel()
        compactTabTooltipTask = nil
        compactTabTooltipTitle = nil
    }

    // MARK: - Compact Address Bar

    /// Whether the compact sidebar address bar overlay is visible.
    ///
    /// Shown when hovering the link button or during page load in compact mode.
    /// The overlay is rendered in OverlayContainer with fixed positioning.
    var showsCompactAddressBar = false

    // MARK: - Layout Mode State

    /// Whether the window is currently in layout editing mode
    var isInLayoutMode = false

    /// Whether a layout mode exit animation is in progress.
    ///
    /// `@ObservationIgnored` so it doesn't trigger view rebuilds. Read directly
    /// by the `.transaction` modifier to allow the exit animation through.
    @ObservationIgnored private(set) var isAnimatingLayoutTransition = false

    /// Whether the mouse cursor is currently inside the bounds of an overlay.
    ///
    /// When `true`, WKWebView's `_ignoresAllEvents` is set to block all input.
    /// This is used when the sidebar overlay or detail tray is visible, so that
    /// the overlay receives events instead of the underlying web content.
    var webViewsShouldIgnoreAllEvents = false

    /// Whether the cursor is hovering over an interactive overlay notification
    /// (e.g., the search engine detected pill).
    ///
    /// When `true`, the overlay hosting view stops passing through hit tests,
    /// allowing SwiftUI buttons in the notification to receive clicks.
    /// Set via `.onHover` on the notification view itself.
    var isHoveringOverlayNotification = false

    /// Target pane position for adding a page via command lens in layout mode
    ///
    /// When set, the command lens will add a new page to the active tab's layout
    /// at this position instead of creating a new tab.
    var layoutModeTargetPosition: PanePosition?

    /// When set, command lens creates a new reference tab instead of a main tab.
    ///
    /// Set to `true` when user taps the "add tab" button in the reference pane.
    /// The command lens will then route the selected URL/search to `addReferenceTab()`
    /// instead of creating a normal tab.
    var isCreatingReferenceTab = false

    /// Whether the command lens is visible in the reference pane window.
    ///
    /// This is separate from `showsCommandLens` because the reference pane window
    /// has its own lens overlay positioned at the top-middle of the window.
    var showsReferencePaneLens = false

    /// Whether a reference pane window is open for this WindowState.
    ///
    /// Set by `WindowManager.createReferencePaneWindow()` and cleared when the window closes.
    /// When true, the docked reference pane view should NOT force WebViews inactive
    /// because the content is being displayed in the separate window.
    var hasReferencePaneWindow = false

    /// Whether the agent chat is active in the reference pane.
    ///
    /// When true, the reference pane shows the agent chat interface instead of
    /// reference tabs. Toggled via Cmd+Shift+S keyboard shortcut.
    var isAgentChatActive = false

    // MARK: - Toast Notification State

    /// Current toast message to display, if any.
    ///
    /// Set this to show a brief notification at the top of the window.
    /// Automatically clears after a few seconds.
    var toastMessage: String?

    /// Auto-dismiss task for the current toast.
    @ObservationIgnored
    private var toastDismissTask: Task<Void, any Error>?

    /// Shows a toast notification that auto-dismisses.
    ///
    /// - Parameters:
    ///   - message: The message to display.
    ///   - duration: How long to show the toast (default 4 seconds).
    func showToast(_ message: String, duration: Duration = .seconds(4)) {
        toastDismissTask?.cancel()
        toastMessage = message

        toastDismissTask = Task { [weak self] in
            try await Task.sleep(for: duration)
            self?.toastMessage = nil
        }
    }

    /// Dismisses the current toast immediately.
    func dismissToast() {
        toastDismissTask?.cancel()
        toastDismissTask = nil
        toastMessage = nil
    }

    // MARK: - Search Engine Detection

    /// A search engine detected from browsing that the user hasn't acted on yet.
    var pendingSearchEngineDetection: DetectedSearchEngine?

    /// Domains whose search engine detection was dismissed this session.
    @ObservationIgnored
    var dismissedSearchEngineDomains: Set<String> = []

    // MARK: - Remind Me Sheet State

    /// Page info for the "Remind Me" sheet.
    ///
    /// When set, the main window presents the RemindMeSheet.
    /// Set to nil when the sheet is dismissed.
    struct RemindMePageInfo: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let title: String
    }

    /// Current page info for the Remind Me sheet, if showing.
    var remindMePageInfo: RemindMePageInfo?

    /// Shows the Remind Me sheet for the specified page.
    func showRemindMeSheet(url: URL, title: String) {
        remindMePageInfo = RemindMePageInfo(url: url, title: title)
    }

    /// Dismisses the Remind Me sheet.
    func dismissRemindMeSheet() {
        remindMePageInfo = nil
    }

    // MARK: - GIF Picker State

    /// Context for the GIF picker sheet.
    ///
    /// Stores the page where the GIF should be inserted.
    struct GifPickerContext: Identifiable {
        let id = UUID()
        let page: WebPage
    }

    /// Current GIF picker context, if the picker is showing.
    var gifPickerContext: GifPickerContext?

    /// Shows the GIF picker for inserting into the specified page.
    func showGifPicker(for page: WebPage) {
        gifPickerContext = GifPickerContext(page: page)
    }

    /// Dismisses the GIF picker.
    func dismissGifPicker() {
        gifPickerContext = nil
    }

    // MARK: - Browser Import State

    /// Whether the browser data import wizard is showing.
    var showsBrowserImport = false

    // MARK: - Speed Reader State

    /// Current speed reader window controller, retained to keep the window alive.
    @ObservationIgnored
    private var speedReaderWindowController: SpeedReaderWindowController?

    /// Shows the speed reader panel for the given selected text.
    ///
    /// Creates a minimal `ExtractedArticle` from the text and opens the speed reader panel
    /// attached to the current window. The panel reference is retained until closed.
    ///
    /// - Parameter text: The selected text to speed read.
    func showSpeedReader(for text: String) {
        // Close existing speed reader if open
        speedReaderWindowController?.close()

        // Create a minimal article from the selected text
        let article = ExtractedArticle(
            title: "Selected Text",
            byline: nil,
            content: text,
            textContent: text,
            excerpt: nil,
            siteName: nil,
            publishedTime: nil,
            sourceURL: URL.staticRequired("refrax://selection"),
        )

        // Create and show the speed reader panel
        let controller = SpeedReaderWindowController(
            article: article,
            settings: settings,
            parentWindow: NSApp.keyWindow,
        )
        controller.showCentered()
        speedReaderWindowController = controller
    }

    // MARK: - Page Search Bar State

    /// Per-tab page find navigator presentation state
    private var findNavigatorIsPresented: [TabPage.ID: Bool] = [:]

    /// Binding for find navigator presentation for a specific tab page
    ///
    /// Automatically cleans up dictionary entry when set to false.
    subscript(findNavigatorFor pageId: Tab.ID) -> Binding<Bool> {
        Binding(
            get: { self.findNavigatorIsPresented[pageId] ?? false },
            set: { newValue in
                if newValue {
                    self.findNavigatorIsPresented[pageId] = true
                } else {
                    self.findNavigatorIsPresented.removeValue(forKey: pageId)
                }
            },
        )
    }
    
    // MARK: - Reference Pane Layout (Window-Specific)

    // Per-window visual layout state for the reference pane.
    //
    // ## Architecture: Content vs Layout Separation
    //
    // ```
    // ┌─────────────────────────────────────────────────────┐
    // │ CONTENT (What)        → Per-Space (TabManager)      │
    // │ • Reference tabs      → Stored in Space             │
    // ├─────────────────────────────────────────────────────┤
    // │ LAYOUT (How)          → Per-Window (WindowState)    │
    // │ • Inspector collapsed → Here                        │
    // │ • Docked width        → Here                        │
    // │ • Controls locked     → Here                        │
    // │ • Active ref tab ID   → Here                        │
    // └─────────────────────────────────────────────────────┘
    // ```
    //
    // ## Why Separate?
    //
    // Multiple windows can show the SAME space with DIFFERENT layouts:
    // - Window A: Reference pane docked at 400px width
    // - Window B: Reference pane docked at 500px width
    // - Both showing the same Space with same reference tabs
    //
    // ## Separate Window Mode
    //
    // To detach the reference pane into a separate window, use
    // `WindowManager.createReferencePaneWindow()`. This creates a new
    // `ReferencePaneWindow` that shares the same WindowState.

    /// Reference pane width when docked in inspector panel
    var referencePaneDockedWidth: CGFloat = 400

    // MARK: - Computed Properties

    var showsCommandLens: Bool {
        focusedLens == .command
    }

    var showsAddressLens: Bool {
        focusedLens == .address
    }

    var commandLensBinding: Binding<Bool> {
        Binding(
            get: { self.showsCommandLens },
            set: { isPresented in
                if isPresented {
                    self.openCommandLens()
                } else {
                    self.closeCommandLens()
                }
            },
        )
    }
    
    // MARK: - Initialization
    
    /// Creates a WindowState for a browser window.
    ///
    /// - Parameters:
    ///   - settings: Browser settings for appearance preferences.
    ///   - browserState: The shared browser state for tab lookups.
    init(settings: BrowserSettings, browserState: BrowserState) {
        self.settings = settings
        self.browserState = browserState
    }

    // MARK: - Lens Actions

    /// Opens the address lens.
    ///
    /// Animation is handled by `AddressLensOverlay`.
    func openAddressLens() {
        webViewsShouldIgnoreAllEvents = true
        focusedLens = .address
    }

    /// Closes the address lens.
    ///
    /// Animation is handled by `AddressLensOverlay`.
    func closeAddressLens() {
        clearFocus()
    }

    /// Opens the command lens (no animation by default)
    func openCommandLens() {
        webViewsShouldIgnoreAllEvents = true
        focusedLens = .command
    }

    /// Closes the command lens (no animation by default)
    func closeCommandLens() {
        clearFocus()
    }

    /// Opens the command lens in the reference pane window.
    ///
    /// This shows the lens overlay in the reference pane window. The lens is
    /// positioned at the top-middle of the window.
    ///
    /// - Parameter forNewTab: If true, the lens will create a new reference tab.
    ///   If false (default), the lens will navigate the current reference tab.
    func openReferencePaneLens(forNewTab: Bool = false) {
        isCreatingReferenceTab = forNewTab
        showsReferencePaneLens = true
    }

    /// Closes the command lens in the reference pane window.
    func closeReferencePaneLens() {
        showsReferencePaneLens = false
        isCreatingReferenceTab = false
    }

    private func clearFocus() {
        focusedLens = nil
        webViewsShouldIgnoreAllEvents = false
        (window as? RefraxWindow)?.lockedFirstResponder = nil
        // Clear contextual creation flags when any lens closes
        isCreatingReferenceTab = false
        layoutModeTargetPosition = nil
    }
    
    // MARK: - Layout Mode Actions
    
    /// Enter layout editing mode for creating multi-page layouts
    func enterLayoutMode() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
            isInLayoutMode = true
        }
    }
    
    /// Exit layout editing mode and save layout
    func exitLayoutMode() {
        isAnimatingLayoutTransition = true
        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
            isInLayoutMode = false
        }
        // Clear after the spring animation has settled (~0.6s for response 0.4, damping 0.78)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.isAnimatingLayoutTransition = false
        }
    }
    
    // MARK: - Split View Actions

    /// Toggle sidebar visibility
    func toggleSidebar() {
        isSidebarCollapsed.toggle()
    }

    /// Toggle inspector/reference pane visibility
    func toggleInspector() {
        isInspectorCollapsed.toggle()
    }

    /// Toggle agent chat in the reference pane
    func toggleAgentChat() {
        isAgentChatActive.toggle()
        // Ensure inspector is visible when activating chat
        if isAgentChatActive, isInspectorCollapsed {
            isInspectorCollapsed = false
        }
    }

    // MARK: - Detail Tray Actions

    /// Toggles the detail tray for a specific mode.
    ///
    /// If the tray is already showing the requested mode, it will be hidden.
    /// If hidden or showing a different mode, it will show the requested mode.
    ///
    /// - Parameter mode: The mode to toggle (downloads, bookmarks, or history).
    func toggleDetailTray(_ mode: DetailTrayMode) {
        guard mode != .hidden else { return }
        if detailTrayMode == mode {
            detailTrayMode = .hidden
        } else {
            detailTrayMode = mode
        }
    }

    /// Shows the detail tray with the specified mode.
    ///
    /// - Parameter mode: The mode to show. Passing `.hidden` hides the tray.
    func showDetailTray(_ mode: DetailTrayMode) {
        detailTrayMode = mode
    }

    /// Hides the detail tray.
    func hideDetailTray() {
        detailTrayMode = .hidden
    }
    
    // MARK: - Page Search Actions
    
    /// Show find navigator for the currently active tab page.
    func showFindNavigator() {
        guard let activePageID else { return }
        findNavigatorIsPresented[activePageID] = true
    }

    /// Hide find navigator for a specific tab page.
    func hideFindNavigator(for pageId: Tab.ID) {
        findNavigatorIsPresented.removeValue(forKey: pageId)
    }
    
    // MARK: - Navigation Methods
    
    /// Gets the active tab ID for a specific space in this window.
    ///
    /// Each space remembers its last active tab independently.
    func activeTabID(for spaceID: Space.ID) -> Tab.ID? {
        _activeTabIDs[spaceID]
    }
    
    /// Sets the active tab ID for a specific space in this window.
    ///
    /// Also updates the previous active tab ID for "go back" behavior.
    ///
    /// - Parameters:
    ///   - tabID: The tab ID to set as active, or nil to clear.
    ///   - spaceID: The space to set the active tab for.
    ///   - trackPrevious: Whether to track the current tab as previous. Set to false
    ///     when setting active tab during batch operations or cleanup.
    func setActiveTabID(_ tabID: Tab.ID?, for spaceID: Space.ID, trackPrevious: Bool = true) {
        // Track current as previous before changing (if applicable)
        if trackPrevious, let currentID = _activeTabIDs[spaceID], currentID != tabID {
            _previousActiveTabIDs[spaceID] = currentID
        }

        if let tabID {
            _activeTabIDs[spaceID] = tabID
        } else {
            _activeTabIDs.removeValue(forKey: spaceID)
        }
    }

    /// Sets a tab as active in this window.
    ///
    /// Handles both live favorite tabs and space-bound tabs with unified logic:
    /// - **Live favorites**: Sets the live favorite override, making this tab the
    ///   window's active tab regardless of the current space.
    /// - **Space tabs**: Clears any live favorite override and sets this tab as
    ///   active for its space.
    ///
    /// - Parameters:
    ///   - tab: The tab to activate.
    ///   - trackPrevious: Whether to track the current tab as previous for "go back"
    ///     behavior. Set to false during batch operations or cleanup.
    func setActiveTab(_ tab: Tab, trackPrevious: Bool = true) {
        if tab.status == .liveFavorite {
            // Live favorites override space-based active tab
            _activeLiveFavoriteTabID = tab.id
        } else if let spaceID = tab.space?.id {
            // Space tabs clear any live favorite override
            _activeLiveFavoriteTabID = nil

            // Track previous tab for go-back behavior
            if trackPrevious, let currentID = _activeTabIDs[spaceID], currentID != tab.id {
                _previousActiveTabIDs[spaceID] = currentID
            }
            _activeTabIDs[spaceID] = tab.id
        }

        // Sync focused page with the new active tab's primary page.
        // This ensures AddressBar and other UI that depends on focusedPageID
        // updates immediately when switching tabs, not just on user interaction.
        focusedPageID = tab.activePage.id
    }

    /// Clears the active live favorite, returning focus to the space's active tab.
    ///
    /// Call this when navigating away from a live favorite without activating
    /// a specific tab (e.g., when closing a live favorite tab or loading a URL
    /// in the space's active page).
    func clearActiveLiveFavorite() {
        _activeLiveFavoriteTabID = nil
    }

    /// Gets the previous active tab ID for a specific space.
    ///
    /// Returns the tab that was active before the current one, used for
    /// "go back" behavior when closing the active tab.
    func previousActiveTabID(for spaceID: Space.ID) -> Tab.ID? {
        _previousActiveTabIDs[spaceID]
    }

    /// Clears the previous active tab ID for a specific space.
    ///
    /// Call this when the previous tab is closed or otherwise becomes invalid.
    func clearPreviousActiveTabID(for spaceID: Space.ID) {
        _previousActiveTabIDs.removeValue(forKey: spaceID)
    }
    
    /// Sets the active space for this window.
    ///
    /// - Parameters:
    ///   - space: The space to activate.
    ///   - restoreActiveTab: Whether to restore the space's last active tab. Set to false
    ///     for new windows that should start without a tab selected.
    func setActiveSpace(_ space: Space, restoreActiveTab _: Bool = true) {
        activeSpaceID = space.id
        // Note: Reference tabs intentionally don't auto-select on space switch.
        // The user must explicitly choose which reference tab to load via the
        // empty state tab selector, matching the behavior for main tabs.
    }
    
    /// Removes references to a deleted tab from all navigation state.
    ///
    /// Call this when a tab is closed or deleted to prevent stale IDs from
    /// lingering in inactive spaces' active tab dictionaries.
    ///
    /// - Parameters:
    ///   - tabID: The deleted tab's identifier.
    ///   - spaceID: The space the tab belonged to.
    func handleTabRemoved(_ tabID: Tab.ID, from spaceID: Space.ID) {
        if _activeTabIDs[spaceID] == tabID {
            _activeTabIDs.removeValue(forKey: spaceID)
        }
        if _previousActiveTabIDs[spaceID] == tabID {
            _previousActiveTabIDs.removeValue(forKey: spaceID)
        }
        if _activeLiveFavoriteTabID == tabID {
            _activeLiveFavoriteTabID = nil
        }
    }

    /// Removes all stale tab IDs that no longer exist in the browser state.
    ///
    /// Iterates through all stored active and previous tab IDs and removes
    /// entries whose tabs have been deleted. Call periodically or after batch
    /// tab operations to prevent stale references from accumulating.
    func purgeStaleTabIDs() {
        for (spaceID, tabID) in _activeTabIDs {
            if browserState.tab(for: tabID) == nil {
                _activeTabIDs.removeValue(forKey: spaceID)
            }
        }
        for (spaceID, tabID) in _previousActiveTabIDs {
            if browserState.tab(for: tabID) == nil {
                _previousActiveTabIDs.removeValue(forKey: spaceID)
            }
        }
        if let liveFavoriteID = _activeLiveFavoriteTabID,
           browserState.tab(for: liveFavoriteID) == nil {
            _activeLiveFavoriteTabID = nil
        }
    }

    /// Clears navigation state (for window cleanup).
    ///
    /// Called when a window is being closed to release references.
    func clearNavigationState() {
        activeSpaceID = nil
        _activeTabIDs.removeAll()
        _previousActiveTabIDs.removeAll()
        activeReferenceTabID = nil
        _activeLiveFavoriteTabID = nil
    }
}

// MARK: - Focus Region

/// Identifies which quick-action lens is currently visible in the window.
///
/// Lenses are overlay interfaces that appear over the main content for
/// focused tasks like entering URLs or executing commands.
///
/// ## Lens Types
///
/// - **Address Lens**: Appears below the address bar for URL entry with suggestions
/// - **Command Lens**: Centered overlay (Cmd+K) for quick actions and search
///
/// ## Behavior
///
/// Only one lens can be visible at a time. When a lens is active:
/// - Background is dimmed with a dark overlay
/// - Keyboard focus moves to the lens
/// - Escape key dismisses the lens
/// - Background clicks dismiss the lens
///
/// - Note: The lens state is managed by ``WindowState`` which coordinates
///   the animation and keyboard focus.
enum FocusedLens: Hashable, Sendable {
    /// Address bar lens for URL entry and suggestions.
    ///
    /// Positioned directly below the address bar in the toolbar.
    /// Displays search suggestions and history as the user types.
    case address

    /// Command palette for quick actions.
    ///
    /// Centered overlay (Cmd+K) providing:
    /// - Quick tab switching
    /// - URL navigation
    /// - Command execution
    /// - Search across tabs and history
    case command
}

// MARK: - Detail Tray Mode

/// Content mode for the sidebar detail tray panel.
///
/// The detail tray is a secondary slide-out panel adjacent to the sidebar that
/// provides quick access to downloads, bookmarks, and history. It uses the same
/// Liquid Glass styling as the sidebar overlay and coordinates with it when the
/// sidebar is collapsed.
///
/// ## Entry Points
///
/// - Sidebar overlay buttons (when sidebar is collapsed)
/// - Menu bar: View → Show Downloads/Bookmarks/History
/// - Keyboard shortcuts: ⌘⇧D (downloads), ⌘⇧B (bookmarks), ⌘Y (history)
///
/// ## Positioning
///
/// The detail tray positions itself based on sidebar state:
/// - **Sidebar expanded**: Adjacent to sidebar trailing edge with 8px gap
/// - **Sidebar collapsed + overlay visible**: Adjacent to overlay trailing edge
/// - **Sidebar collapsed + overlay hidden**: Floats at left edge with glass effect
///
/// - Note: The tray state is managed by ``WindowState`` and animated by
///   ``RefraxWindowController`` using layer-based transforms.
enum DetailTrayMode: Equatable, Sendable {
    /// Detail tray is hidden.
    case hidden

    /// Showing downloads panel with active and completed downloads.
    case downloads

    /// Showing bookmarks panel with folder navigation.
    case bookmarks

    /// Showing history panel with recent visits grouped by date.
    case history

    /// Showing back/forward navigation list for the active page.
    case backForward

    /// Showing tab snapshots panel for browsing and restoring session states.
    case tabSnapshots

    /// Showing Lightboard dashboard for monitoring tab health and resources.
    case lightboard
}
