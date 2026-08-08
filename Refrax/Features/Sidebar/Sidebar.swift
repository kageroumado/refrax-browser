import SwiftUI

/// Combined version key for layout rebuild triggers.
/// Using a struct instead of tuple because tuples don't conform to Equatable.
private struct LayoutVersionKey: Equatable {
    let tabListVersion: UInt64
    let favoritesVersion: Int
    let filterSignature: Int
}

/// Main sidebar containing favorites, address bar, filters, and tab list.
///
/// ## Architecture
///
/// The sidebar managers are created in `RefraxWindowController` and injected
/// via the environment. This ensures they persist for the window lifecycle,
/// avoiding recreation during hover-to-appear animations.
///
/// ## Bottom Controls
///
/// The bottom controls area supports two layout states:
/// - **Collapsed**: Single row with filter button, space picker, and new space button
/// - **Expanded**: Two rows with full filter bar above, space picker + new space button below
///
/// The filter button morphs into the full filter bar using matchedGeometryEffect.
///
/// ## Rebuilds
///
/// Layout rebuilds are triggered explicitly via `onChange` rather than on every
/// body evaluation, ensuring performance with large tab counts.
struct Sidebar: View {
    @Environment(TabManager.self) private var tabManager
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(BookmarksManager.self) private var bookmarksManager
    @Environment(TabGroupManager.self) private var groupManager
    @Environment(UndoRedoManager.self) private var undoRedoManager
    @Environment(WindowState.self) private var windowState
    @Environment(BrowserState.self) private var browserState
    @Environment(BrowserSettings.self) private var settings
    @Environment(ModifierKeysState.self) private var modifierKeysState
    @Environment(TabPreviewManager.self) private var tabPreviewManager
    @Environment(WebPagePool.self) private var pagePool
    @Environment(HistoryManager.self) private var historyManager
    @Environment(TabAutoArchiveManager.self) private var autoArchiveManager
    @Environment(WindowManager.self) private var windowManager

    // Managers (injected from window controller, persist for window lifecycle)
    @Environment(Sidebar.LayoutManager.self) private var layoutManager
    @Environment(Sidebar.DragCoordinator.self) private var dragCoordinator
    @Environment(Sidebar.FilterManager.self) private var filterManager
    @Environment(Sidebar.TabSelectionManager.self) private var selectionManager
    @Environment(Sidebar.MediaControlsManager.self) private var mediaControlsManager
    @Environment(ShelfManager.self) private var shelfManager
    @Environment(Sidebar.TransitionCoordinator.self) private var transitionCoordinator
    @Environment(Sidebar.MiddleClickCoordinator.self) private var middleClickCoordinator
    @Environment(Sidebar.DependencyContainer.self) private var dependencyContainer
    @Environment(Sidebar.GeometryState.self) private var geometryState
    @Environment(AppUpdateManager.self) private var appUpdateManager

    // UI state
    @State private var showUpdateSheet = false
    @State private var isInstallingCLIHelper = false
    @State private var showCreateSpaceSheet = false
    @State private var showSpaceManagementSheet = false
    @State private var spaceToEdit: Space?

    // Space context menu state
    @State private var showingSpaceSettingsPopover = false
    @State private var spaceToDelete: Space?
    @State private var showDeleteConfirmation = false

    /// The space that was right-clicked for context menu operations.
    /// Used to ensure settings popover operates on the correct space.
    @State private var contextMenuSpace: Space?

    /// Whether the filter bar is expanded (showing full text field)
    @State private var isFilterExpanded = false

    /// Whether a layout rebuild is pending (deferred until after transition animation)
    @State private var pendingLayoutRebuild = false

    /// Shared handler for space swipe gesture, used by both the modifier and adjacent preview.
    @State private var swipeGestureHandler = SpaceSwipeGestureHandler()

    /// Proxy for programmatic scrolling, replacing ScrollViewReader.
    @State private var scrollToProxy = ScrollToItemProxy()

    /// Tracked heights for header/footer overlays, fed as content insets to NSScrollView.
    @State private var topHeaderHeight: CGFloat = 0
    @State private var bottomControlsHeight: CGFloat = 0

    @Namespace private var filterMorphNamespace
    
    var body: some View {
        ZStack(alignment: .top) {
            mainContent
            dropZoneOverlays
            dragOverlay

            // Invisible view for AppKit drag session handoff
            SidebarDragSourceView(coordinator: dragCoordinator)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)

            // Invisible view for receiving drops (re-entry, external URLs, and shelf items)
            // Note: Hit testing passes through via hitTest override, so the NSView
            // receives drag events but doesn't intercept normal mouse events
            SidebarDropReceiver(coordinator: dragCoordinator, shelfManager: shelfManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        // Track complete sidebar bounds for authoritative handoff detection
        .onGeometryChange(for: CGRect.self) { geo in
            geo.frame(in: .global)
        } action: { bounds in
            dragCoordinator.updateSidebarBounds(bounds)
        }
        .accessibilityIdentifier("Sidebar")
        .frame(minWidth: Constants.Layout.sidebarMinWidth, maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            layoutManager.rebuildLayout()
            middleClickCoordinator.setup()
        }
        .onDisappear {
            middleClickCoordinator.teardown()
        }
        // Combined onChange for layout-triggering versions to prevent multiple rebuilds
        // when several change in the same frame (e.g., closing a tab that's also a favorite)
        .onChange(of: LayoutVersionKey(
            tabListVersion: browserState.tabListVersion,
            favoritesVersion: bookmarksManager.favoritesVersion,
            filterSignature: filterManager.signature,
        )) {
            // Defer rebuild during space transitions to avoid jank during animation
            if transitionCoordinator.isTransitioning {
                pendingLayoutRebuild = true
            } else {
                rebuildLayoutAnimated()
            }
        }
        .onChange(of: transitionCoordinator.isTransitioning) { _, isTransitioning in
            // When transition completes, perform any deferred layout rebuild
            if !isTransitioning, pendingLayoutRebuild {
                pendingLayoutRebuild = false
                layoutManager.rebuildLayout()
            }
        }
        .onChange(of: windowState.activeSpaceID) {
            selectionManager.clearSelection()
        }
        .sheet(isPresented: $showCreateSpaceSheet) {
            CreateSpaceSheet()
        }
        .sheet(isPresented: $showSpaceManagementSheet) {
            SpaceManagementSheet()
        }
        .sheet(item: $spaceToEdit) { space in
            EditSpaceSheet(space: space)
        }
        .alert(deleteAlertTitle, isPresented: $showDeleteConfirmation, presenting: spaceToDelete) { space in
            Button("Cancel", role: .cancel) {
                spaceToDelete = nil
            }

            if tabManager.hasMultipleSpaces {
                Button("Delete", role: .destructive) {
                    spaceManager.deleteSpace(space, windowState: windowState)
                    spaceToDelete = nil
                }
            } else {
                Button("Clear All Tabs", role: .destructive) {
                    handleLastSpaceClear(space)
                    spaceToDelete = nil
                }
            }
        } message: { space in
            if tabManager.hasMultipleSpaces {
                Text("Are you sure you want to delete '\(space.name)'? This will close all \(browserState.tabs(in: space).count) tabs in this space.")
            } else {
                Text("This is your last space. All tabs will be closed and the space will be reset to default.")
            }
        }
    }
    
    // MARK: - Main Content
    

    private var mainContent: some View {
        // NSScrollView occupies full sidebar height. Header and footer are overlaid
        // with blur backgrounds. Content insets push scroll content below/above them.
        RecyclingTabListView(
            pinnedItems: layoutManager.pinnedItems,
            normalItems: layoutManager.normalItems,
            activeTabID: windowState.activeTabID,
            isShowingLiveFavorite: windowState.isShowingLiveFavorite,
            isCompact: false,
            scrollToProxy: scrollToProxy,
            tabListPushOffset: dragCoordinator.tabListPushOffset,
            itemPushOffsets: dragCoordinator.itemPushOffsets,
            topContentInset: topHeaderHeight,
            bottomContentInset: bottomControlsHeight,
            onScrollChange: { [geometryState, windowState] documentToSidebarOffset, topInset in
                geometryState.documentToSidebarOffset = documentToSidebarOffset
                // Only update observable property when value actually changed
                // to avoid triggering unnecessary SwiftUI re-renders.
                if geometryState.currentScrollTopInset != topInset {
                    geometryState.currentScrollTopInset = topInset
                }
                // Recompute active tab visibility for the sticky indicator.
                // Only writes when the state flips (visible ↔ above ↔ below).
                geometryState.updateActiveTabScrollPosition(
                    activeTabID: windowState.activeTabID,
                )
            },
            emptyAreaMenuBuilder: { [dependencyContainer] in
                SidebarContextMenus.buildEmptyAreaMenu(dependencies: dependencyContainer)
            },
        )
        .offset(x: transitionCoordinator.animationOffset)
        .overlay {
            ClickOutsideTextFieldHandler()
                .allowsHitTesting(false)
        }
        .sidebarSpaceSwipeGesture(handler: swipeGestureHandler)
        .overlay(alignment: .topLeading) {
            if swipeGestureHandler.adjacentSpaceID != nil {
                adjacentSpacePreview
            }
        }
        // Active tab indicator overlay — uses full frame so it can position at top/bottom
        .overlay {
            ActiveTabIndicator()
        }
        .environment(scrollToProxy)
        // Header overlaid at top with height tracking
        .overlay(alignment: .top) {
            topHeader
                .onGeometryChange(for: CGFloat.self) { geo in
                    geo.size.height
                } action: { height in
                    topHeaderHeight = height
                }
        }
        // Footer overlaid at bottom with height tracking
        .overlay(alignment: .bottom) {
            bottomControls
                .onGeometryChange(for: CGFloat.self) { geo in
                    geo.size.height
                } action: { height in
                    bottomControlsHeight = height
                    geometryState.bottomControlsHeight = height
                }
        }
        // Close confirmation alert (migrated from TabList.swift)
        .alert(
            tabManager.pendingCloseConfirmation?.title ?? "Close Tab?",
            isPresented: Binding(
                get: { tabManager.pendingCloseConfirmation != nil },
                set: { if !$0 { tabManager.cancelCloseTabs() } },
            ),
            presenting: tabManager.pendingCloseConfirmation,
        ) { _ in
            Button("Cancel", role: .cancel) {
                tabManager.cancelCloseTabs()
            }
            Button("Close", role: .destructive) {
                tabManager.confirmCloseTabs()
            }
        } message: { confirmation in
            CloseConfirmationMessage(confirmation: confirmation)
        }
    }
    
    /// Preview of the adjacent space's tabs, shown during swipe gesture.
    ///
    /// Positioned to the left or right of the current tab list based on swipe direction,
    /// and moves together with the main content via the gesture's translation offset.
    @ViewBuilder
    private var adjacentSpacePreview: some View {
        let offset = swipeGestureHandler.translationOffset
        let sidebarWidth = geometryState.sidebarBounds.width
        // Swipe right (positive offset) → previous space → preview to the left
        // Swipe left (negative offset) → next space → preview to the right
        let direction: CGFloat = offset > 0 ? -1 : 1

        AdjacentSpacePreview(
            pinnedItems: swipeGestureHandler.adjacentPinnedItems,
            normalItems: swipeGestureHandler.adjacentNormalItems,
        )
        .frame(width: sidebarWidth)
        .offset(x: direction * sidebarWidth + transitionCoordinator.animationOffset)
        .opacity(min(1.0, abs(offset) / 50.0)) // Fade in as user swipes
    }

    // MARK: - Top Header
    
    /// Simplified top header with address bar and favorites only.
    private var topHeader: some View {
        VStack(spacing: 12) {
            AddressBar()

            FavoritesGrid()
        }
        .padding(.horizontal, Constants.Layout.sidebarPadding)
        .padding(.bottom, !layoutManager.favoritesLayout.isEmpty ? 8 : 0)
        .background {
            VariableBackdropBlurView(
                edge: .top,
                tintColor: Color(windowState.backgroundColor.color),
            )
            .ignoresSafeArea(.all, edges: .vertical)
        }
    }
    
    // MARK: - Drop Zone Overlays

    private typealias DropZoneLayout = Sidebar.DragCoordinator.DropZoneConstants

    private var dropZoneOverlays: some View {
        ZStack(alignment: .top) {
            // Internal drag drop zones (tab reordering)
            if dragCoordinator.shouldShowFavoritesDropZone {
                dropZoneOverlay(
                    type: .favorites,
                    isActive: dragCoordinator.activeDropZone == .favoritesGrid,
                )
            }

            if dragCoordinator.shouldShowPinDropZone {
                dropZoneOverlay(
                    type: .pinned,
                    isActive: dragCoordinator.activeDropZone == .pinnedSection,
                )
            }

            // Inbound external drop zones (URL drops from outside app)
            inboundDropZoneOverlays
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Inbound Drop Zone Overlays

    /// Overlays for external URL drops, positioned using GeometryState frames.
    @ViewBuilder
    private var inboundDropZoneOverlays: some View {
        // Account for 8px top padding of sidebar container
        let topPadding: CGFloat = 8

        if let zone = dragCoordinator.inboundDropZone {
            switch zone {
            case .favoritesGrid:
                inboundDropZoneHighlight
                    .frame(
                        width: geometryState.favoritesGridFrame.width,
                        height: geometryState.favoritesGridFrame.height,
                    )
                    .offset(
                        x: geometryState.favoritesGridFrame.minX - geometryState.sidebarBounds.minX,
                        y: geometryState.favoritesGridFrame.minY - geometryState.sidebarBounds.minY - topPadding,
                    )

            case .pinnedSection:
                let frame = geometryState.computedPinnedSectionFrame
                if !frame.isEmpty {
                    inboundDropZoneHighlight
                        .frame(width: frame.width, height: frame.height)
                        .offset(
                            x: frame.minX - geometryState.sidebarBounds.minX,
                            y: frame.minY - topPadding,
                        )
                }

            case .normalSection:
                let frame = geometryState.computedNormalSectionFrame
                // Limit height to visible area
                let visibleHeight = max(0, geometryState.sidebarBounds.height - frame.minY)
                inboundDropZoneHighlight
                    .frame(width: frame.width, height: min(frame.height, visibleHeight))
                    .offset(
                        x: frame.minX - geometryState.sidebarBounds.minX,
                        y: frame.minY - topPadding,
                    )

            case .groupHeader:
                // Group headers use normal section highlight for now
                EmptyView()
            }
        }
    }

    /// The visual highlight for inbound drop zones.
    private var inboundDropZoneHighlight: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Color.appAccentColor.opacity(0.6), lineWidth: 2)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.appAccentColor.opacity(0.1)),
            )
            .allowsHitTesting(false)
    }

    private func dropZoneOverlay(
        type: DropZoneType,
        isActive: Bool,
    ) -> some View {
        let additionalOffset: CGFloat = if case .pinned = type {
            dragCoordinator.shouldShowFavoritesDropZone ? DropZoneLayout.favoritesDropZoneTotalHeight : 0
        } else { 0 }
        return DropZonePlaceholder(type: type, isActive: isActive)
            .frame(maxWidth: .infinity)
            .offset(y: calculateDropZoneBaseOffset() + additionalOffset)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    private func calculateDropZoneBaseOffset() -> CGFloat {
        var offset = DropZoneLayout.addressBarOffset

        if !layoutManager.favoritesLayout.isEmpty {
            offset += dragCoordinator.favoritesGridFrame.height + 12
        }

        return offset
    }
    
    // MARK: - Drag Overlay

    @ViewBuilder
    private var dragOverlay: some View {
        // Only show SwiftUI overlay when we own the drag (internal phase)
        // During external phase, AppKit's drag image is displayed instead
        //
        // IMPORTANT: Check `isDragging` first to create observation dependency.
        // `primaryDraggedItem` reads from @ObservationIgnored `draggedItems`,
        // so without `isDragging` check, the body wouldn't re-render on drag start.
        if dragCoordinator.isDragging,
           let item = dragCoordinator.primaryDraggedItem,
           dragCoordinator.handoffPhase == .internal {
            MorphingDragOverlay(
                primaryItem: item,
                totalCount: dragCoordinator.draggedItems.count + dragCoordinator.followerItems.count,
            )
        }
    }
    
    // MARK: - Bottom Controls
    
    /// Bottom controls with collapsible filter bar and media controls.
    ///
    /// ## Layout States
    ///
    /// **Base (no filter, no media):**
    /// ```
    /// ┌─────────────────────────────────────────────┐
    /// │ [≡]  [Space Picker fills width]       [+]   │
    /// └─────────────────────────────────────────────┘
    /// ```
    ///
    /// **With media active:**
    /// ```
    /// ┌─────────────────────────────────────────────┐
    /// │ [≡] [🔊] [Space Picker fills width]   [+]   │
    /// └─────────────────────────────────────────────┘
    /// ```
    ///
    /// **With media panel expanded:**
    /// ```
    /// ┌─────────────────────────────────────────────┐
    /// │ Media & Calls                         [📌]  │
    /// │ ┌─────────────────────────────────────────┐ │
    /// │ │ youtube.com          [▶][PiP]           │ │
    /// │ │ 🔇─────────●───🔊                       │ │
    /// │ └─────────────────────────────────────────┘ │
    /// ├─────────────────────────────────────────────┤
    /// │ [≡] [🔊] [Space Picker fills width]   [+]   │
    /// └─────────────────────────────────────────────┘
    /// ```
    private var bottomControls: some View {
        VStack(spacing: Constants.Spacing.small) {
            // Crash report or post-update notification (only one at a time, crash takes priority)
            if appUpdateManager.crashReportSent {
                CrashReportPanel()
            } else {
                UpdateNotificationPanel()
            }

            // Media controls panel (expands upward when active)
            MediaControlsPanel()

            // Shelf panel (expands upward when items exist)
            ShelfPanel()

            if isFilterExpanded {
                // Expanded: Filter bar on its own row
                SidebarFilter(
                    isExpanded: $isFilterExpanded,
                    morphNamespace: filterMorphNamespace,
                )
            }

            // Main controls row
            // Layout: [Filter] [SpacePicker] [New Space] | [Dynamic buttons]
            // Dynamic buttons are placed after static controls for visual stability
            HStack(spacing: Constants.Spacing.small - 1) {
                if !isFilterExpanded {
                    // Collapsed: Filter button in the row
                    SidebarFilter(
                        isExpanded: $isFilterExpanded,
                        morphNamespace: filterMorphNamespace,
                    )
                }

                SpacePicker(
                    selection: spacePickerSelection,
                    spaces: tabManager.state.spaces,
                    unlockedSpaceIDs: tabManager.state.spaceLockManager.unlockedSpaceIDs,
                ) { space in
                    spaceContextMenuContent(for: space)
                }
                .if(showingSpaceSettingsPopover) { view in
                    view.popover(isPresented: $showingSpaceSettingsPopover, arrowEdge: .top) {
                        spaceSettingsPopoverContent
                    }
                }

                SidebarControlButton(
                    icon: "plus.square.on.square",
                    accessibilityID: "sidebar-new-space",
                    action: {
                        showCreateSpaceSheet = true
                    },
                )
                .accessibilityLabel("Create New Space")

                // Dynamic buttons (after static controls for visual stability)
                // Media controls button - unified speaker/call indicator
                if mediaControlsManager.hasActiveMedia {
                    MediaControlsButton()
                }

                // Downloads button - only show during/after downloads
                DownloadsButton()

                // Shelf button - only show when there are items
                ShelfButton()

                // Reminders widget button
                RemindersWidgetButton()

                // Calendar widget button
                CalendarWidgetButton()

                // CLI helper install (only when admin privileges are required)
                if browserState.cliHelperNeedsPrivilegedInstall {
                    SidebarControlButton(
                        icon: "terminal",
                        accessibilityID: "sidebar-install-cli",
                        action: installCLIHelper,
                    )
                    .disabled(isInstallingCLIHelper)
                    .help("Install the refrax-ctl command-line tool (requires administrator password)")
                    .accessibilityLabel("Install command-line tool")
                }

                // Update phase indicator
                switch appUpdateManager.phase {
                case .downloading(let progress):
                    SidebarControlButton(
                        icon: "arrow.down.circle",
                        accessibilityID: "sidebar-update-downloading",
                        action: {},
                    )
                    .overlay {
                        ProgressView(value: progress)
                            .progressViewStyle(.circular)
                            .scaleEffect(0.5)
                    }
                    .accessibilityLabel("Downloading update: \(Int(progress * 100))%")

                case .readyToInstall:
                    SidebarControlButton(
                        icon: "arrow.trianglehead.2.clockwise.rotate.90",
                        accessibilityID: "sidebar-restart-to-update",
                        action: { showUpdateSheet = true },
                    )
                    .foregroundStyle(.green)
                    .accessibilityLabel("Restart to update")

                case .failed:
                    SidebarControlButton(
                        icon: "exclamationmark.triangle.fill",
                        accessibilityID: "sidebar-update-failed",
                        action: {
                            appUpdateManager.showFailedPanel = true
                        },
                    )
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Update failed — tap for details")

                default:
                    EmptyView()
                }
            }
            .sheet(isPresented: $showUpdateSheet) {
                UpdateAvailableView()
            }
        }
        .padding(Constants.Layout.sidebarPadding)
        .adaptiveBackgroundBlur()
        .background {
            VariableBackdropBlurView(
                edge: .bottom,
                tintColor: Color(windowState.backgroundColor.color),
            )
        }
        .arrowlessPopover(
            isPresented: Bindable(dependencyContainer).showWindowBackgroundPopover,
            arrowEdge: .top,
        ) {
            WindowBackgroundPopover()
        }
    }

    /// Installs the `refrax-ctl` helper via the system administrator prompt.
    ///
    /// The button that triggers this is the user's consent — the system
    /// authentication panel is the only dialog shown. On success the button
    /// disappears; on cancel it stays for another try.
    private func installCLIHelper() {
        isInstallingCLIHelper = true
        Task {
            if await RefraxControlHost.installCLIHelperWithAuthorization() {
                browserState.cliHelperNeedsPrivilegedInstall = false
            }
            isInstallingCLIHelper = false
        }
    }

    /// Builds a context menu for a specific space segment.
    ///
    /// - Parameter space: The space for the context menu.
    /// - Returns: A view containing the context menu items for that space.
    private func spaceContextMenuContent(for space: Space) -> some View {
        SidebarContextMenus.SpaceMenu(
            space: space,
            onQuickEdit: {
                contextMenuSpace = space
                showingSpaceSettingsPopover = true
            },
            onEdit: {
                spaceToEdit = space
            },
            onDelete: {
                spaceToDelete = space
                showDeleteConfirmation = true
            },
            onNewSpace: {
                showCreateSpaceSheet = true
            },
            onManageSpaces: {
                showSpaceManagementSheet = true
            },
        )
    }

    // MARK: - Space Settings Popover

    @ViewBuilder
    private var spaceSettingsPopoverContent: some View {
        if let targetSpace = contextMenuSpace {
            SpaceSettingsPopover(
                name: Binding(
                    get: { targetSpace.name },
                    set: { newName in
                        spaceManager.updateSpace(targetSpace, name: newName)
                    },
                ),
                selectedIcon: Binding(
                    get: { targetSpace.iconName },
                    set: { newIcon in
                        spaceManager.updateSpace(targetSpace, iconName: newIcon)
                    },
                ),
                selectedColorHex: Binding(
                    get: { targetSpace.colorHex },
                    set: { newValue in
                        spaceManager.updateSpace(
                            targetSpace,
                            color: Color.resolveStoredColor(newValue),
                        )
                    },
                ),
                isPresented: $showingSpaceSettingsPopover,
            )
        }
    }

    // MARK: - Delete Alert

    private var deleteAlertTitle: String {
        tabManager.hasMultipleSpaces ? "Delete Space" : "Clear Space"
    }

    private func handleLastSpaceClear(_ space: Space) {
        // Close all tabs
        let tabsToClose = browserState.tabs(in: space)
        for tab in tabsToClose {
            tabManager.closeTab(tab)
        }

        // Delete all groups (tabs already closed, so don't delete contained tabs again)
        let groupsToDelete = browserState.groups(in: space)
        for group in groupsToDelete {
            groupManager.deleteGroup(group, in: space, deleteContainedTabs: false)
        }

        // Reset space to default configuration
        spaceManager.updateSpace(
            space,
            name: SpaceManager.DefaultSpaceConfig.name,
            iconName: SpaceManager.DefaultSpaceConfig.iconName,
            color: SpaceManager.DefaultSpaceConfig.color,
        )
    }

    // MARK: - Helper Methods

    /// Rebuilds the sidebar layout with a spring animation.
    private func rebuildLayoutAnimated() {
        withAnimation(.spring(response: Constants.Animation.springDuration, dampingFraction: Constants.Animation.springDamping)) {
            layoutManager.rebuildLayout()
        }
    }

    /// Binding for space picker selection that handles transition animation.
    private var spacePickerSelection: Binding<UUID> {
        Binding(
            get: { windowState.activeSpaceID ?? UUID() },
            set: { newSpaceID in
                updateActiveSpace(to: newSpaceID)
            },
        )
    }

    /// Updates the active space with animated transition.
    ///
    /// For locked spaces, authentication is required before the switch animation plays.
    private func updateActiveSpace(to newSpaceID: UUID) {
        guard newSpaceID != windowState.activeSpaceID else { return }

        // Check if target space requires authentication
        guard let targetSpace = spaceManager.spaces.first(where: { $0.id == newSpaceID }) else { return }

        let spaceLockManager = browserState.spaceLockManager
        let needsAuth = targetSpace.isLockEnabled && !spaceLockManager.unlockedSpaceIDs.contains(targetSpace.id)

        if needsAuth {
            // Authenticate first, then switch if successful
            Task {
                let result = await spaceLockManager.authenticate(for: targetSpace)
                guard case .success = result else { return }
                performSpaceSwitch(to: newSpaceID)
            }
        } else {
            // No auth needed, switch immediately
            performSpaceSwitch(to: newSpaceID)
        }
    }

    /// Performs the actual space switch with animation.
    private func performSpaceSwitch(to newSpaceID: UUID) {
        let oldIndex = spaceManager.spaces.firstIndex(where: { $0.id == windowState.activeSpaceID }) ?? 0
        let newIndex = spaceManager.spaces.firstIndex(where: { $0.id == newSpaceID }) ?? 0

        // Animate with proper out/in sequencing
        // The coordinator calls performSwitch after the out animation completes.
        // Uses switchToSpaceSync because authentication is already handled by
        // updateActiveSpace before this method is called.
        //
        // rebuildLayout() is called explicitly because the normal onChange path
        // defers rebuilds while isTransitioning is true. At this point the content
        // is off-screen (at outTarget offset), so the rebuild is invisible.
        transitionCoordinator.animateSpaceChange(from: oldIndex, to: newIndex) {
            spaceManager.switchToSpaceSync(id: newSpaceID, for: windowState)
            layoutManager.rebuildLayout()
        }
    }
}

// MARK: - Close Confirmation Message

/// Message view for the close confirmation alert.
///
/// Displays a list of tabs and why they require confirmation (form data, audio, media).
private struct CloseConfirmationMessage: View {
    let confirmation: TabManager.CloseConfirmation

    var body: some View {
        if confirmation.reasons.count == 1, let reason = confirmation.reasons.first {
            singleTabMessage(reason)
        } else {
            batchMessage
        }
    }

    private func singleTabMessage(_ reason: TabManager.TabCloseReason) -> Text {
        let title = reason.tab.displayTitle
        let reasonText = reason.reasons.map(\.description).joined(separator: " and ")
        return Text("\"\(title)\" \(reasonText).")
    }

    private var batchMessage: Text {
        let items = confirmation.reasons.map { reason in
            let title = reason.tab.displayTitle
            let reasonText = reason.reasons.map(\.description).joined(separator: ", ")
            return "• \(title): \(reasonText)"
        }
        let message = "The following tabs have warnings:\n\n" + items.joined(separator: "\n") + "\n"
        return Text(message)
    }
}
