import AppKit
import SwiftUI

// MARK: - Cell Environment

/// Bundles all environment objects that sidebar cell views need into a single
/// `@Environment` lookup, eliminating per-object environment resolution.
///
/// All properties are immutable references set once at creation. `@ObservationIgnored`
/// prevents the `@Observable` macro from registering tracking for reads — these
/// references never change, so observation would be pure overhead.
@Observable
final class SidebarCellEnvironment {
    @ObservationIgnored unowned let layoutManager: Sidebar.LayoutManager
    @ObservationIgnored unowned let dragCoordinator: Sidebar.DragCoordinator
    @ObservationIgnored unowned let selectionManager: Sidebar.TabSelectionManager
    @ObservationIgnored unowned let tabManager: TabManager
    @ObservationIgnored unowned let windowState: WindowState
    @ObservationIgnored unowned let browserState: BrowserState
    @ObservationIgnored unowned let dependencyContainer: Sidebar.DependencyContainer
    @ObservationIgnored unowned let geometryState: Sidebar.GeometryState
    @ObservationIgnored unowned let modifierKeysState: ModifierKeysState
    @ObservationIgnored unowned let tabPreviewManager: TabPreviewManager
    @ObservationIgnored unowned let pagePool: WebPagePool
    @ObservationIgnored unowned let historyManager: HistoryManager
    @ObservationIgnored unowned let groupManager: TabGroupManager
    @ObservationIgnored unowned let filterManager: Sidebar.FilterManager
    @ObservationIgnored unowned let settings: BrowserSettings
    @ObservationIgnored unowned let mediaControlsManager: Sidebar.MediaControlsManager
    @ObservationIgnored unowned let autoArchiveManager: TabAutoArchiveManager
    @ObservationIgnored unowned let windowManager: WindowManager

    /// Returns the global frame (screen coordinates) for a cell with the given ID.
    /// Set by the RecyclingTabListView coordinator; used by compact cells for tooltip positioning.
    @ObservationIgnored var globalFrameForItem: ((_ itemID: UUID) -> CGRect)?

    init(
        layoutManager: Sidebar.LayoutManager,
        dragCoordinator: Sidebar.DragCoordinator,
        selectionManager: Sidebar.TabSelectionManager,
        tabManager: TabManager,
        windowState: WindowState,
        browserState: BrowserState,
        dependencyContainer: Sidebar.DependencyContainer,
        geometryState: Sidebar.GeometryState,
        modifierKeysState: ModifierKeysState,
        tabPreviewManager: TabPreviewManager,
        pagePool: WebPagePool,
        historyManager: HistoryManager,
        groupManager: TabGroupManager,
        filterManager: Sidebar.FilterManager,
        settings: BrowserSettings,
        mediaControlsManager: Sidebar.MediaControlsManager,
        autoArchiveManager: TabAutoArchiveManager,
        windowManager: WindowManager
    ) {
        self.layoutManager = layoutManager
        self.dragCoordinator = dragCoordinator
        self.selectionManager = selectionManager
        self.tabManager = tabManager
        self.windowState = windowState
        self.browserState = browserState
        self.dependencyContainer = dependencyContainer
        self.geometryState = geometryState
        self.modifierKeysState = modifierKeysState
        self.tabPreviewManager = tabPreviewManager
        self.pagePool = pagePool
        self.historyManager = historyManager
        self.groupManager = groupManager
        self.filterManager = filterManager
        self.settings = settings
        self.mediaControlsManager = mediaControlsManager
        self.autoArchiveManager = autoArchiveManager
        self.windowManager = windowManager
    }
}

// MARK: - Cell Content

/// Concrete cell content view for both expanded and compact sidebar modes.
///
/// Switches between expanded cells (`TabRowCell`, `GroupHeaderCell`, `NewTabButtonCell`)
/// and compact cells (`CompactTabRowCell`, `CompactGroupHeaderRowCell`,
/// `CompactDividerCell`, `CompactCommandLensCell`) based on `isCompact`.
///
/// Environment values are applied once here, bridging `SidebarCellEnvironment`
/// to individual `@Environment` lookups used by shared views.
struct SidebarCellContent: View {
    let item: RecyclingTabListItem
    let cellEnvironment: SidebarCellEnvironment
    let activeTabID: Tab.ID?
    let isShowingLiveFavorite: Bool
    let isCompact: Bool

    var body: some View {
        content
            // SidebarCellEnvironment: single-lookup access for cell views.
            .environment(cellEnvironment)
            // Individual writes for shared views (AdaptiveBackground, context menus,
            // TabFaviconView, popovers, etc.) that use @Environment(Type.self) directly.
            // Can't be removed without adopting NSHostingViewDelegate.willUpdate (private).
            .environment(cellEnvironment.layoutManager)
            .environment(cellEnvironment.dragCoordinator)
            .environment(cellEnvironment.selectionManager)
            .environment(cellEnvironment.tabManager)
            .environment(cellEnvironment.windowState)
            .environment(cellEnvironment.browserState)
            .environment(cellEnvironment.dependencyContainer)
            .environment(cellEnvironment.geometryState)
            .environment(cellEnvironment.modifierKeysState)
            .environment(cellEnvironment.tabPreviewManager)
            .environment(cellEnvironment.pagePool)
            .environment(cellEnvironment.historyManager)
            .environment(cellEnvironment.groupManager)
            .environment(cellEnvironment.filterManager)
            .environment(cellEnvironment.settings)
            .environment(cellEnvironment.mediaControlsManager)
            .environment(cellEnvironment.autoArchiveManager)
            .environment(cellEnvironment.windowManager)
    }

    @ViewBuilder
    private var content: some View {
        if isCompact {
            compactContent
        } else {
            expandedContent
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        switch item {
        case .sidebarItem(let tabListItem, let collection):
            expandedSidebarItemContent(tabListItem, collection: collection)
        case .newTabButton:
            NewTabButtonCell()
        case .compactDivider, .compactCommandLens:
            EmptyView()
        }
    }

    @ViewBuilder
    private var compactContent: some View {
        switch item {
        case .sidebarItem(let tabListItem, _):
            compactSidebarItemContent(tabListItem)
        case .compactDivider:
            CompactDividerCell()
        case .compactCommandLens:
            CompactCommandLensCell()
        case .newTabButton:
            EmptyView()
        }
    }

    @ViewBuilder
    private func expandedSidebarItemContent(
        _ item: TabListItem,
        collection: SidebarCollection,
    ) -> some View {
        switch item {
        case .tab(let tab):
            TabRowCell(
                tab: tab,
                collection: collection,
                activeTabID: activeTabID,
                isShowingLiveFavorite: isShowingLiveFavorite,
            )
        case .group(let group):
            GroupHeaderCell(
                group: group,
                collection: collection,
            )
        }
    }

    @ViewBuilder
    private func compactSidebarItemContent(_ item: TabListItem) -> some View {
        switch item {
        case .tab(let tab):
            CompactTabRowCell(tab: tab, activeTabID: activeTabID)
        case .group(let group):
            CompactGroupHeaderRowCell(group: group, activeTabID: activeTabID)
        }
    }
}

// MARK: - Section

/// Single section for the diffable data source.
/// All items (pinned, new tab button, normal) live in one section.
private enum SidebarSection: Hashable {
    case main
}

// MARK: - Cell Identifiers

private extension NSUserInterfaceItemIdentifier {
    static let tabRow = NSUserInterfaceItemIdentifier("TabRow")
    static let groupHeader = NSUserInterfaceItemIdentifier("GroupHeader")
    static let newTabButton = NSUserInterfaceItemIdentifier("NewTabButton")
}

// MARK: - NSViewRepresentable

struct RecyclingTabListView: NSViewRepresentable {
    let pinnedItems: [TabListItem]
    let normalItems: [TabListItem]
    let activeTabID: Tab.ID?
    let isShowingLiveFavorite: Bool
    let isCompact: Bool
    let scrollToProxy: ScrollToItemProxy
    let tabListPushOffset: CGFloat
    let itemPushOffsets: [UUID: CGPoint]
    let topContentInset: CGFloat
    let bottomContentInset: CGFloat
    let onScrollChange: ((_ documentToSidebarOffset: CGFloat, _ topInset: CGFloat) -> Void)?
    let emptyAreaMenuBuilder: (() -> NSMenu)?

    @Environment(SidebarCellEnvironment.self) private var cellEnvironment

    func makeCoordinator() -> Coordinator {
        Coordinator(scrollToProxy: scrollToProxy)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.setupTableView(
            isCompact: isCompact,
            emptyAreaMenuBuilder: emptyAreaMenuBuilder,
        )
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let items = if isCompact {
            RecyclingTabListItem.buildCompactSidebarItems(
                pinnedItems: pinnedItems,
                normalItems: normalItems,
            )
        } else {
            RecyclingTabListItem.buildFullSidebarItems(
                pinnedItems: pinnedItems,
                normalItems: normalItems,
            )
        }

        context.coordinator.update(
            items: items,
            activeTabID: activeTabID,
            isShowingLiveFavorite: isShowingLiveFavorite,
            tabListPushOffset: tabListPushOffset,
            itemPushOffsets: itemPushOffsets,
            topContentInset: topContentInset,
            bottomContentInset: bottomContentInset,
            onScrollChange: onScrollChange,
            cellEnvironment: cellEnvironment,
        )
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.teardown()
    }
}

// MARK: - Coordinator

extension RecyclingTabListView {
    final class Coordinator: NSObject, NSTableViewDelegate {
        // MARK: - Views

        private let scrollView: TabListScrollView = {
            let sv = TabListScrollView()
            sv.hasVerticalScroller = true
            sv.hasHorizontalScroller = false
            sv.autohidesScrollers = true
            sv.drawsBackground = false
            sv.automaticallyAdjustsContentInsets = false
            sv.scrollerStyle = .overlay
            sv.verticalScrollElasticity = .allowed
            sv.contentView.postsBoundsChangedNotifications = true
            return sv
        }()

        private let tableView: FirstMouseTableView = {
            let tv = FirstMouseTableView()
            tv.headerView = nil
            tv.style = .plain
            tv.backgroundColor = .clear
            tv.rowSizeStyle = .custom
            tv.selectionHighlightStyle = .none
            tv.intercellSpacing = NSSize(
                width: 0,
                height: Constants.Layout.tabSpacing,
            )
            tv.rowHeight = Constants.Layout.tabItemHeight
            tv.usesAutomaticRowHeights = false
            tv.floatsGroupRows = false

            // Disable features we handle ourselves to avoid unnecessary work.
            tv.allowsColumnReordering = false
            tv.allowsColumnResizing = false
            tv.allowsColumnSelection = false
            tv.allowsMultipleSelection = false
            tv.allowsEmptySelection = true

            let column = NSTableColumn(identifier: .init("content"))
            column.resizingMask = .autoresizingMask
            tv.addTableColumn(column)

            return tv
        }()

        // MARK: - Data Source

        private var dataSource: NSTableViewDiffableDataSource<SidebarSection, RecyclingTabListItem>!

        // MARK: - State

        private var items: [RecyclingTabListItem] = []
        private var cachedItemIDs: [UUID] = []
        private var itemIDToIndex: [UUID: Int] = [:]
        private var activeTabID: Tab.ID?
        private var isShowingLiveFavorite = false
        private var tabListPushOffset: CGFloat = 0
        private var itemPushOffsets: [UUID: CGPoint] = [:]
        private var onScrollChange: ((_ scrollOffset: CGFloat, _ topInset: CGFloat) -> Void)?
        private var isFirstSnapshot = true

        private var isCompact = false

        private var cellEnvironment: SidebarCellEnvironment?
        private let scrollToProxy: ScrollToItemProxy
        private var scrollObserver: (any NSObjectProtocol)?

        // MARK: - Init

        init(scrollToProxy: ScrollToItemProxy) {
            self.scrollToProxy = scrollToProxy
            super.init()
        }

        // MARK: - Setup

        func setupTableView(isCompact: Bool = false, emptyAreaMenuBuilder: (() -> NSMenu)? = nil) -> NSScrollView {
            self.isCompact = isCompact

            if isCompact {
                tableView.intercellSpacing = NSSize(width: 0, height: 0)
                tableView.rowHeight = CompactTabButton.Layout.buttonHeight
                // Hide scrollers entirely — the 48pt strip has no room for them.
                // Trackpad/scroll wheel still works without a visible scroller.
                scrollView.hasVerticalScroller = false
            }

            tableView.delegate = self
            tableView.menuBuilder = emptyAreaMenuBuilder
            scrollView.documentView = tableView

            dataSource = NSTableViewDiffableDataSource<SidebarSection, RecyclingTabListItem>(
                tableView: tableView,
            ) { [weak self] tableView, tableColumn, row, item in
                guard let self else { return NSView() }
                return self.cellView(for: item, in: tableView, row: row)
            }
            dataSource.defaultRowAnimation = .effectFade

            scrollToProxy.scrollHandler = { [weak self] itemID, anchor in
                self?.scrollToItem(itemID, anchor: anchor)
            }

            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main,
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleScroll()
                }
            }

            return scrollView
        }

        func teardown() {
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
            scrollToProxy.scrollHandler = nil
            cellEnvironment?.globalFrameForItem = nil
        }

        // MARK: - Update

        func update(
            items: [RecyclingTabListItem],
            activeTabID: Tab.ID?,
            isShowingLiveFavorite: Bool,
            tabListPushOffset: CGFloat,
            itemPushOffsets: [UUID: CGPoint],
            topContentInset: CGFloat,
            bottomContentInset: CGFloat,
            onScrollChange: ((_ scrollOffset: CGFloat, _ topInset: CGFloat) -> Void)?,
            cellEnvironment: SidebarCellEnvironment,
        ) {
            self.cellEnvironment = cellEnvironment
            self.onScrollChange = onScrollChange

            // Wire AppKit-based frame lookup for compact tooltip positioning.
            if isCompact, cellEnvironment.globalFrameForItem == nil {
                cellEnvironment.globalFrameForItem = { [weak self] itemID in
                    self?.globalFrameForItem(itemID) ?? .zero
                }
            }

            // Detect changes — lazy comparison avoids allocating a [UUID] on every update cycle.
            let itemsChanged: Bool = {
                guard items.count == cachedItemIDs.count else { return true }
                for (item, cachedID) in zip(items, cachedItemIDs) where item.id != cachedID {
                    return true
                }
                return false
            }()
            let selectionChanged = self.activeTabID != activeTabID
                || self.isShowingLiveFavorite != isShowingLiveFavorite
            let itemPushOffsetsChanged = self.itemPushOffsets != itemPushOffsets
            // Push offsets going from non-empty → empty means a drag just ended.
            // The diffable data source animation must be suppressed so it doesn't
            // fight with the push offset layer transforms (rows are already at
            // their correct visual positions from the drag).
            let dragJustEnded = !self.itemPushOffsets.isEmpty && itemPushOffsets.isEmpty

            // Update stored state
            self.items = items
            if itemsChanged { self.cachedItemIDs = items.map(\.id) }
            self.activeTabID = activeTabID
            self.isShowingLiveFavorite = isShowingLiveFavorite
            self.tabListPushOffset = tabListPushOffset
            self.itemPushOffsets = itemPushOffsets

            // Update item index lookup
            if itemsChanged {
                itemIDToIndex.removeAll(keepingCapacity: true)
                for (index, item) in items.enumerated() {
                    itemIDToIndex[item.id] = index
                }
            }

            // Content insets (header/footer blur)
            // Expanded sidebar adds 8pt gap between header blur and first tab.
            // Compact sidebar uses 0 (controls handle their own padding).
            let effectiveTopPadding: CGFloat = isCompact ? 0 : 8
            let targetTopInset = topContentInset + effectiveTopPadding
            let oldTopInset = scrollView.contentInsets.top
            if oldTopInset != targetTopInset
                || scrollView.contentInsets.bottom != bottomContentInset
            {
                scrollView.contentInsets = NSEdgeInsets(
                    top: targetTopInset,
                    left: 0,
                    bottom: bottomContentInset,
                    right: 0,
                )

                let delta = targetTopInset - oldTopInset
                var origin = scrollView.contentView.bounds.origin
                origin.y -= delta
                scrollView.contentView.setBoundsOrigin(origin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }

            // Apply snapshot when items changed
            if itemsChanged {
                applySnapshot(animated: !isFirstSnapshot && !dragJustEnded)
                isFirstSnapshot = false

                // New tab button height depends on divider visibility
                // (changes when pinning/unpinning or favorites change).
                if let newTabIndex = items.firstIndex(where: {
                    if case .newTabButton = $0 { return true }
                    return false
                }) {
                    tableView.noteHeightOfRows(
                        withIndexesChanged: IndexSet(integer: newTabIndex),
                    )
                }
            }

            // Selection change → reconfigure affected cells
            if selectionChanged && !itemsChanged {
                reconfigureVisibleCells()
            }

            // Geometry state
            updateGeometryState()

            // Per-item push offsets via layer transforms
            if itemPushOffsetsChanged {
                applyPushOffsets(animated: true)
            }

            // Compact mode: ensure the single column fills the scroll view width.
            // Column auto-resizing may not trigger on initial layout.
            if isCompact {
                tableView.sizeLastColumnToFit()
            }
        }

        // MARK: - Snapshot

        private func applySnapshot(animated: Bool) {
            var snapshot = NSDiffableDataSourceSnapshot<SidebarSection, RecyclingTabListItem>()
            snapshot.appendSections([.main])
            snapshot.appendItems(items, toSection: .main)
            dataSource.apply(snapshot, animatingDifferences: animated)
        }

        /// Reconfigure visible cells when selection changes (without structural change).
        private func reconfigureVisibleCells() {
            let visibleRange = tableView.rows(in: tableView.visibleRect)
            guard visibleRange.length > 0 else { return }

            for row in visibleRange.location ..< (visibleRange.location + visibleRange.length) {
                guard row < items.count,
                      let cellView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
                    as? CellHostingView
                else { continue }

                cellView.updateContent(makeCellContent(for: items[row]))
            }
        }

        // MARK: - Cell Provider

        private func cellView(
            for item: RecyclingTabListItem,
            in tableView: NSTableView,
            row: Int,
        ) -> NSView {
            let identifier: NSUserInterfaceItemIdentifier = switch item {
            case .sidebarItem(let tabListItem, _):
                switch tabListItem {
                case .tab: .tabRow
                case .group: .groupHeader
                }
            case .newTabButton: .newTabButton
            case .compactDivider, .compactCommandLens: .tabRow
            }

            let content = makeCellContent(for: item)

            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil)
                as? CellHostingView
            {
                reused.updateContent(content)
                return reused
            }

            return CellHostingView(identifier: identifier, initialContent: content)
        }

        // MARK: - Cell Content

        private func makeCellContent(for item: RecyclingTabListItem) -> SidebarCellContent {
            SidebarCellContent(
                item: item,
                cellEnvironment: cellEnvironment!,
                activeTabID: activeTabID,
                isShowingLiveFavorite: isShowingLiveFavorite,
                isCompact: isCompact,
            )
        }

        // MARK: - NSTableViewDelegate

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard row < items.count else {
                return isCompact ? CompactTabButton.Layout.buttonHeight : Constants.Layout.tabItemHeight
            }

            if isCompact {
                if case .compactDivider = items[row] {
                    return CompactSidebarLayout.dividerVerticalPadding * 2 + 1
                }
                return CompactTabButton.Layout.buttonHeight
            }

            if case .newTabButton = items[row] {
                return newTabButtonRowHeight
            }
            return Constants.Layout.tabItemHeight
        }

        /// New tab button height derived from GeometryState constants.
        /// With divider: gap = dividerHeight(5) + slotHeight(40) = 45
        /// Without divider: tabItemHeight(36) (same as regular tab).
        private var newTabButtonRowHeight: CGFloat {
            // Divider is present when there are pinned items before the new tab button.
            let hasDivider = items.contains(where: {
                if case .sidebarItem(_, let collection) = $0 {
                    return collection == .pinned || collection == .favorites
                }
                return false
            })
            if hasDivider {
                return 5 + Constants.Layout.tabItemHeight + Constants.Layout.tabSpacing
            }
            return Constants.Layout.tabItemHeight
        }

        // NOTE: No `tableView(_:rowViewForRow:)` override.
        // Letting NSTableView manage row views enables automatic reuse.
        // Reused row views already have their key view loop established,
        // avoiding the expensive `_updateKeyViewLoopForRowView` →
        // `_setDefaultKeyViewLoop` → `layoutSubtreeIfNeeded` chain
        // that dominated the scroll profile (~39% of scroll time).

        // MARK: - Cell Frame Lookup

        /// Returns the frame for the cell in SwiftUI's global coordinate space
        /// (window-relative, top-left origin). Used for compact tooltip positioning.
        private func globalFrameForItem(_ itemID: UUID) -> CGRect {
            guard let index = itemIDToIndex[itemID],
                  let window = tableView.window
            else { return .zero }

            let rowRect = tableView.rect(ofRow: index)
            // Convert to window coordinates (bottom-left origin in AppKit)
            let windowRect = tableView.convert(rowRect, to: nil)
            // Flip Y to match SwiftUI's global coordinate space (top-left origin)
            let flippedY = window.frame.height - windowRect.maxY
            return CGRect(
                x: windowRect.origin.x,
                y: flippedY,
                width: windowRect.width,
                height: windowRect.height,
            )
        }

        // MARK: - Scroll Handling

        private func handleScroll() {
            updateGeometryState()
        }

        private func updateGeometryState() {
            let clipOriginY = scrollView.contentView.bounds.origin.y
            let topInset = scrollView.contentInsets.top
            // NSTableView distributes intercellSpacing evenly: half above, half below
            // each cell. The cell content starts at intercellSpacing.height/2 within
            // each row slot. Add this offset so GeometryState's frame calculations
            // match the actual cell positions, not the row rect origins.
            let cellInsetTop = tableView.intercellSpacing.height / 2
            let documentToSidebarOffset = -clipOriginY + cellInsetTop
            onScrollChange?(documentToSidebarOffset, topInset)
        }

        // MARK: - Scroll To Item

        private func scrollToItem(_ itemID: UUID, anchor: ScrollToItemProxy.ScrollAnchor) {
            guard let index = itemIDToIndex[itemID] else { return }

            let rowRect = tableView.rect(ofRow: index)
            let visibleHeight = scrollView.bounds.height

            let targetY: CGFloat
            switch anchor {
            case .top:
                targetY = rowRect.minY
            case .bottom:
                targetY = rowRect.maxY - visibleHeight
            case .center:
                targetY = rowRect.midY - visibleHeight / 2
            }

            let maxY = tableView.frame.height - visibleHeight
            let clampedY = max(0, min(targetY, maxY))

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                scrollView.contentView.animator().setBoundsOrigin(
                    NSPoint(x: 0, y: clampedY),
                )
            }
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        // MARK: - Push Offset Layer Transforms

        private static let pushSpringStiffness: CGFloat = 986.96
        private static let pushSpringDamping: CGFloat = 50.27

        private func applyPushOffsets(animated: Bool) {
            let visibleRange = tableView.rows(in: tableView.visibleRect)
            guard visibleRange.length > 0 else { return }

            for row in visibleRange.location ..< (visibleRange.location + visibleRange.length) {
                guard row < items.count else { continue }
                let itemID = items[row].id
                let newPushY = itemPushOffsets[itemID]?.y ?? 0

                guard let rowView = tableView.rowView(atRow: row, makeIfNecessary: false),
                      let layer = rowView.layer ?? {
                          rowView.wantsLayer = true
                          return rowView.layer
                      }()
                else { continue }

                if animated {
                    let currentPushY = (layer.presentation() ?? layer)
                        .value(forKeyPath: "transform.translation.y") as? CGFloat ?? 0

                    if abs(currentPushY - newPushY) > 0.5 {
                        let anim = CASpringAnimation(keyPath: "transform.translation.y")
                        anim.fromValue = currentPushY
                        anim.toValue = newPushY
                        anim.mass = 1
                        anim.stiffness = Self.pushSpringStiffness
                        anim.damping = Self.pushSpringDamping
                        anim.initialVelocity = 0
                        anim.duration = anim.settlingDuration
                        layer.add(anim, forKey: "pushOffset")
                    }
                } else {
                    layer.removeAnimation(forKey: "pushOffset")
                }

                layer.transform = newPushY != 0
                    ? CATransform3DMakeTranslation(0, newPushY, 0)
                    : CATransform3DIdentity
            }
        }

    }
}

// MARK: - TabListScrollView

/// NSScrollView subclass that explicitly opts into concurrent VBL scrolling.
///
/// AppKit's `_isConcurrentScrollingCompatible` checks `isCompatibleWithResponsiveScrolling`
/// on the scroll view, clip view, and document view classes. All three must return true.
/// NSScrollView returns true by default, but a subclass ensures the optimization
/// survives any future AppKit changes. Matches Apple's `ListCoreScrollView` pattern.
///
/// With concurrent VBL, scroll event processing is decoupled from the display refresh:
/// - `prepareContentInRect:` can prepare rows beyond the visible rect (overdraw)
/// - The GPU composites the current frame while the CPU prepares the next
/// - This hides cell preparation latency behind the frame pipeline
private final class TabListScrollView: NSScrollView {
    @objc override class var isCompatibleWithResponsiveScrolling: Bool { true }
}

// MARK: - FirstMouseTableView

/// NSTableView subclass with Apple's internal SwiftUI List optimizations.
///
/// Overrides the same private NSTableView methods that `SwiftUIOutlineTableView`
/// and `SwiftUIOutlineListView` override internally. These are ObjC selectors
/// (stable across macOS versions) that skip unnecessary work:
///
/// - `_needsBackgroundFillerView` → skips creating filler views below content
/// - `_needsRubberBandViews` → skips rubber band selection view creation
/// - `_validatesRowHeight` → skips row height validation (we control via delegate)
/// - `_shouldDelayFirstResponder:forRow:` → allows immediate first responder
///   without the default delay, enabling click-through from inactive windows
private final class FirstMouseTableView: NSTableView {
    var menuBuilder: (() -> NSMenu)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let location = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: location)
        if clickedRow == -1 {
            return menuBuilder?()
        }
        return super.menu(for: event)
    }

    // MARK: - Private NSTableView Optimizations

    @objc func _needsBackgroundFillerView() -> Bool { false }
    @objc func _needsRubberBandViews() -> Bool { false }
    @objc func _validatesRowHeight() -> Bool { false }
    @objc func _shouldDelayFirstResponder(_ responder: NSResponder, forRow row: Int) -> Bool { false }
}
