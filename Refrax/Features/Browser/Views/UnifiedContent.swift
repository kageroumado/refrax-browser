import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Main content view displaying web pages with support for single, multi-pane, and layout editing modes
///
/// Architecture:
/// - Single WebView instance per TabPage (prevents WebKit crashes)
/// - Physics-based animations for natural feel
/// - Cached frame calculations for performance
/// - Resizable dividers with snap points
///
/// Performance Optimizations (following Apple SwiftUI best practices):
/// - **Batched Updates**: Uses `frameUpdateGeneration` counter to consolidate multiple state changes
///   into single frame recalculation, preventing redundant work from onChange handlers
/// - **Geometry Tracking**: Uses custom Equatable struct for task(id:) instead of string interpolation
///   to avoid floating-point precision noise triggering unnecessary updates
/// - **Minimal Dependencies**: View bodies kept fast by moving expensive work to model layer
/// - **Session Lifecycle**: Careful ordering prevents dual WebView rendering during transitions
struct UnifiedContentView: View {
    let tab: Tab

    @Environment(TabManager.self) var tabManager
    @Environment(WindowState.self) var windowState
    @Environment(WebPagePool.self) var pagePool

    // MARK: - State

    /// Currently focused page (receives keyboard input)
    @State var focusedPageID: UUID?

    /// Layout grid for layout mode (2x2 grid state)
    @State var layoutGrid = LayoutGrid()

    /// Working layout configuration (synced with tab.layoutConfiguration)
    /// This is the single source of truth for dividers, expansions, and pane positions
    @State var workingConfig = LayoutConfiguration(panePositions: [:])

    /// Cached frame calculations for multi-pane layouts (updated only when layout changes).
    /// Single-pane tabs don't use this - they always fill the container.
    @State var cachedFrames: [UUID: CGRect] = [:]

    /// Counter to trigger frame updates. Increment to request an update.
    /// Using a counter instead of a boolean avoids the extra view update
    /// that would occur when resetting a boolean back to false.
    @State var frameUpdateGeneration: Int = 0

    /// Available content size (from GeometryReader)
    @State var contentSize: CGSize = .zero

    /// Active divider being dragged
    @State var activeDivider: DividerType?

    /// Divider position at start of drag (for delta-based movement)
    @State var dividerDragStartValue: CGFloat = 0.5

    /// Drop target for drag operations
    @State var dropTarget: PanePosition?

    /// Pane dragging state
    @State var draggedPaneID: UUID? = nil
    @State var dragModel = DragModel()
    @State var temporarilyDisplacedPanes: [UUID: PanePosition] = [:]
    @State var highlightedDropTarget: PanePosition? = nil

    /// Invalid drag state (for multi-page tabs that can't be dropped)
    @State var invalidDragTarget: PanePosition?
    @State var invalidDragMessage: String?

    // MARK: - Computed Divider Properties

    var horizontalDivider: CGFloat {
        get { CGFloat(workingConfig.horizontalDivider) }
        nonmutating set { workingConfig.horizontalDivider = Double(newValue) }
    }

    var verticalDivider: CGFloat {
        get { CGFloat(workingConfig.verticalDivider) }
        nonmutating set { workingConfig.verticalDivider = Double(newValue) }
    }

    // MARK: - Constants

    enum Layout {
        static let layoutModeCornerRadius: CGFloat = 18
        static let dividerVisualThickness: CGFloat = 1
        static let dividerGap: CGFloat = 1
        static let minPaneRatio: CGFloat = 0.2
        static let maxPaneRatio: CGFloat = 0.8
        static let snapPoints: [CGFloat] = [0.5, 0.3, 0.7]
        static let snapThreshold: CGFloat = 0.03
    }

    var conditionalSpringAnimation: Animation? {
        windowState.isInLayoutMode ? Animation.spring(response: 0.35, dampingFraction: 0.75) : nil
    }

    private let glassRimGradient = LinearGradient(
        stops: [
            .init(color: .white.opacity(0.7), location: 0.0),
            .init(color: .white.opacity(0.3), location: 0.15),
            .init(color: .clear, location: 0.5),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing,
    )

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                if windowState.isInLayoutMode {
                    emptySlots
                }

                contentLayer
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)

                if !windowState.isInLayoutMode, tab.isMultiPage {
                    dividersLayer
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                }

                if windowState.isInLayoutMode {
                    layoutModeControls
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                }
            }
            .task(id: SizeIdentifier(geometry.size)) {
                // Only fires when window SIZE changes, not on tab switches.
                // Tab switches are handled by reinitializeForNewTab().
                contentSize = geometry.size
                updateCachedFrames(animated: false)
            }
            .task(id: frameUpdateGeneration) {
                // Runs when frameUpdateGeneration increments.
                // Using a counter avoids the extra view update that would occur
                // when resetting a boolean flag back to false.
                guard frameUpdateGeneration > 0 else { return }
                updateCachedFrames()
            }
            .onChange(of: windowState.isInLayoutMode) { _, newValue in
                if newValue {
                    loadLayoutState()
                } else {
                    saveAndExitLayoutMode()
                }
                frameUpdateGeneration += 1
            }
            .onChange(of: tab.layoutConfigurationData) { _, _ in
                // layoutConfiguration is computed, so observe the backing data.
                // This handles same-tab layout changes (divider drag, page add/remove).
                // Tab switches are handled by reinitializeForNewTab() via onChange(of: tab.id).
                //
                // We sync layout grid for layout mode, but DON'T increment frameUpdateGeneration here.
                // For divider changes, the horizontalDivider/verticalDivider onChange handlers
                // will trigger updates. For page add/remove, the layout grid sync handles it.
                // This prevents redundant frame recalculation during tab switches.
                syncNewPagesToLayoutGrid()
            }
            .onChange(of: horizontalDivider) { _, _ in
                // Divider changed - update frames for multi-pane layouts.
                // Single-pane tabs don't use dividers so this only fires for multi-pane.
                if !windowState.isInLayoutMode, tab.isMultiPage {
                    frameUpdateGeneration += 1
                }
            }
            .onChange(of: verticalDivider) { _, _ in
                // Divider changed - update frames for multi-pane layouts.
                if !windowState.isInLayoutMode, tab.isMultiPage {
                    frameUpdateGeneration += 1
                }
            }
        }
        .onAppear {
            initializeState()
        }
        .onChange(of: tab.id) { _, _ in
            // Tab changed - reinitialize state to match new tab's configuration.
            // This syncs workingConfig and frames for the new tab.
            reinitializeForNewTab()
        }
    }

    /// Reinitializes state when switching to a different tab.
    ///
    /// Unlike `initializeState()` which runs on appear, this is called when the tab changes
    /// while the view remains in the hierarchy. It syncs the working config and cached frames
    /// to the new tab's layout configuration.
    ///
    /// **Key insight**: Single-pane tabs don't need cached frames at all - they always fill
    /// the container. Only multi-pane tabs use the cachedFrames dictionary.
    private func reinitializeForNewTab() {
        // Sync working config to new tab's layout
        let newConfig = tab.layoutConfiguration ?? LayoutConfiguration(panePositions: [:])
        workingConfig = newConfig

        // Update focus to new tab's active page
        focusedPageID = newConfig.activePaneID ?? tab.activePage.id

        // Only compute frames for multi-pane tabs
        // Single-pane tabs always use singlePaneFrame (fills container)
        if tab.isMultiPage {
            cachedFrames = computeFramesForTab()
        } else {
            // Clear cached frames for single-pane tabs - not needed
            cachedFrames = [:]
        }
    }

    /// Computes frames for all visible pages in a multi-pane tab.
    ///
    /// Used during tab switches and frame updates. Only called for multi-pane tabs.
    private func computeFramesForTab() -> [UUID: CGRect] {
        guard contentSize != .zero else { return [:] }
        guard let config = tab.layoutConfiguration else { return [:] }

        var frames: [UUID: CGRect] = [:]

        for (pageID, position) in config.panePositions {
            // Skip covered positions
            guard !config.isCovered(position) else { continue }

            let frame = computeMultiPaneFrame(at: position, using: config)
            if frame.width > 0, frame.height > 0 {
                frames[pageID] = frame
            }
        }

        return frames
    }

    // MARK: - Content Layer

    /// All pane positions for constant view structure.
    private static let allPositions: [PanePosition] = [.topLeft, .topRight, .bottomLeft, .bottomRight]

    var contentLayer: some View {
        // CRITICAL: Always render all 4 positions with position-based IDs.
        // This ensures constant view structure - SwiftUI never recreates adapters.
        // Empty positions have zero-sized frames but their adapters persist.
        ForEach(Self.allPositions, id: \.self) { position in
            paneSlot(at: position)
        }
    }

    /// A slot at a fixed position. Always renders PositionedAdapter for stable identity.
    @ViewBuilder
    private func paneSlot(at position: PanePosition) -> some View {
        let tabPage = tabPageAt(position)
        let webPage = tabPage.flatMap { pagePool.page(for: $0) }
        let frame = frameAt(position)
        let hasContent = tabPage != nil && frame.width > 0 && frame.height > 0

        ZStack {
            if windowState.isInLayoutMode, hasContent {
                RoundedRectangle(cornerRadius: Layout.layoutModeCornerRadius)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            }

            // The content wrapper - handles adapter + browser overlays
            // Position-based identity ensures adapters persist across tab switches
            // Ownership (active vs portal mode) is computed inside PaneContentWrapper
            PaneContentWrapper(
                position: position,
                tabPage: tabPage,
                webPage: webPage,
                frame: frame,
                isLayoutMode: windowState.isInLayoutMode,
            )

            if windowState.isInLayoutMode, hasContent {
                glassRim(cornerRadius: Layout.layoutModeCornerRadius)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: max(frame.width, 0), height: max(frame.height, 0))
        .clipShape(RoundedRectangle(cornerRadius: windowState.isInLayoutMode && hasContent ? Layout.layoutModeCornerRadius : 0))
        .offset(x: frame.minX, y: frame.minY)
        // Only animate frame/offset changes in layout mode. Outside layout mode,
        // tab switches should be instant without any implicit animations.
        // Allow the exit animation through when transitioning FROM layout mode.
        .transaction { transaction in
            if !windowState.isInLayoutMode, !windowState.isAnimatingLayoutTransition {
                transaction.animation = nil
            }
            // Don't animate empty slots during exit — spring overshoot produces
            // negative frame values ("Invalid view geometry" warnings).
            // These slots are invisible behind the expanding pane anyway.
            if windowState.isAnimatingLayoutTransition, tabPage == nil {
                transaction.animation = nil
            }
        }
        // Layout mode drag displacement animation
        .animation(
            windowState.isInLayoutMode ? .spring(response: 0.35, dampingFraction: 0.75) : nil,
            value: tabPage.map { temporarilyDisplacedPanes[$0.id] },
        )
        .modifier(PaneDragEffect(offset: tabPage.map { draggedPaneID == $0.id ? dragModel.draggedPaneOffset : .zero } ?? .zero))
        .zIndex(tabPage.map { draggedPaneID == $0.id ? 100 : 0 } ?? 0)
        .gesture(windowState.isInLayoutMode && tabPage != nil ? paneDragGesture(for: tabPage!) : nil)
        .allowsHitTesting(hasContent)
        .onTapGesture {
            if !windowState.isInLayoutMode, let tabPage {
                focusPage(tabPage)
            }
        }
    }

    /// TabPage at a position, if any.
    private func tabPageAt(_ position: PanePosition) -> TabPage? {
        if windowState.isInLayoutMode {
            // In layout mode, read from layoutGrid.
            // Fall back to tab's active page at .topLeft if grid is empty.
            // This handles the timing gap before loadLayoutState() populates the grid.
            if let page = layoutGrid.page(at: position) {
                return page
            } else if position == .topLeft, layoutGrid.filledPositions.isEmpty {
                // Grid not yet populated - use active page as fallback
                return tab.activePage
            }
            return nil
        } else if let config = tab.layoutConfiguration {
            return tab.pages.first { config.panePositions[$0.id] == position }
        } else {
            // Single-pane: only .topLeft has the active page
            return position == .topLeft ? tab.activePage : nil
        }
    }

    /// Frame for a position. Returns zero for empty/hidden positions.
    private func frameAt(_ position: PanePosition) -> CGRect {
        // Guard against zero contentSize - can happen before GeometryReader task completes.
        // Return zero frame so panes are hidden until we have valid dimensions.
        guard contentSize != .zero else { return .zero }

        if windowState.isInLayoutMode {
            // Layout mode: all positions get frames for editing
            return layoutModeFrame(at: position)
        } else if tab.isMultiPage {
            // Multi-pane: only populated positions have frames
            guard tabPageAt(position) != nil else { return .zero }
            return multiPaneFrame(at: position)
        } else {
            // Single-pane: only .topLeft fills the container
            return position == .topLeft ? singlePaneFrame : .zero
        }
    }

    /// Frame for single-pane tabs - fills the entire content area.
    private var singlePaneFrame: CGRect {
        CGRect(origin: .zero, size: contentSize)
    }

    /// Positions for layout mode editing.
    private var layoutModePositions: [PanePosition] {
        layoutGrid.filledPositions
            .filter { !workingConfig.isCovered($0) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Pages visible in layout mode, sorted by position.
    private var layoutModePages: [TabPage] {
        layoutModePositions.compactMap { layoutGrid.page(at: $0) }
    }

    /// Pages to display in multi-pane mode, excluding covered positions.
    private func multiPanePages(config: LayoutConfiguration) -> [TabPage] {
        tab.sortedPages.filter { page in
            guard let position = config.panePositions[page.id] else { return false }
            return !config.isCovered(position)
        }
    }

    /// Returns the pane position for a page from the layout configuration.
    private func panePosition(for page: TabPage) -> PanePosition {
        if windowState.isInLayoutMode {
            return layoutGrid.position(for: page) ?? .topLeft
        } else if let config = tab.layoutConfiguration {
            return config.panePositions[page.id] ?? .topLeft
        }
        return .topLeft
    }

    // MARK: - Helper Views

    func loadingPlaceholder(for page: TabPage) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text(page.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    // MARK: - Visual Properties

    func glassRim(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .strokeBorder(glassRimGradient, lineWidth: 1)
            .blendMode(.plusLighter)
            .compositingGroup()
            .allowsHitTesting(false)
    }

    // MARK: - Computed Properties

    /// Pages currently visible in the content area.
    ///
    /// Used for frame calculations and layout mode overlays.
    var visiblePages: [TabPage] {
        if windowState.isInLayoutMode {
            layoutGrid.allPages.filter { page in
                if let position = layoutGrid.position(for: page) {
                    return !workingConfig.isCovered(position)
                }
                return false
            }
        } else if tab.isMultiPage, let config = tab.layoutConfiguration {
            multiPanePages(config: config)
        } else {
            [tab.activePage]
        }
    }

    var emptyGridPositions: [PanePosition] {
        let allPositions: [PanePosition] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        let filled = Set(layoutGrid.filledPositions)

        return allPositions.filter { position in
            !filled.contains(position) && !workingConfig.isCovered(position)
        }
    }
}
