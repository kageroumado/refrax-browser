import SwiftUI

// MARK: - Tab Row Cell

/// Tab row cell for the recycling tab list.
///
/// Handles click selection, drag gestures, and visibility during drag.
/// Push offsets are applied externally as `CATransform3D` on the hosting view layer
/// by the `RecyclingTabListView` Coordinator — not through SwiftUI observation.
struct TabRowCell: View {
    let tab: Tab
    let collection: SidebarCollection
    let activeTabID: Tab.ID?
    let isShowingLiveFavorite: Bool

    @Environment(SidebarCellEnvironment.self) private var env

    var body: some View {
        let isHidden = env.dragCoordinator.shouldHideItemDuringDrag(tab.id)
        let isConvertedItem = tab.id == env.dragCoordinator._convertedItemID

        Button { handleTabClick(tab) } label: {
            TabView(
                tab: tab,
                isSelected: !isShowingLiveFavorite && activeTabID == tab.id,
                isDragging: env.dragCoordinator.isTabBeingDragged(tab.id),
            )
            .frame(height: Constants.Layout.tabItemHeight)
        }
        .buttonStyle(.plain)
        .opacity(isHidden ? 0 : 1)
        .animation(
            isConvertedItem ? .easeOut(duration: 0.2) : nil,
            value: env.dragCoordinator.isAnimatingReturn,
        )
        .animation(nil, value: env.dragCoordinator.isAnimatingReturn)
        .contentShape(Rectangle())
        .allowsHitTesting(!env.dragCoordinator.isDragging)
        .simultaneousGesture(tabDragGesture)
        .padding(.horizontal, Constants.Layout.tabHorizontalPadding)
        .padding(.leading, CGFloat(env.layoutManager.nestingLevel(for: tab.id)) * Constants.Layout.nestingLevelPadding)
    }

    // MARK: - Drag Gesture

    private var tabDragGesture: some Gesture {
        DragGesture(minimumDistance: Constants.TabDrag.minimumDragDistance, coordinateSpace: .global)
            .onChanged { value in
                guard !env.dragCoordinator.isAnimatingReturn else { return }

                if !env.dragCoordinator.isDragging,
                   let meta = env.layoutManager.metadata[tab.id]
                {
                    let itemsToDrag: [Sidebar.DragCoordinator.DraggedItem]

                    if env.selectionManager.isSelected(tab), env.selectionManager.hasSelection {
                        let selectedTabs = env.selectionManager.selectedTabsIncludingActive
                        let followers = selectedTabs
                            .filter { $0.id != tab.id }
                            .map { Sidebar.DragCoordinator.DraggedItem.tab($0) }
                        itemsToDrag = [.tab(tab)] + followers
                    } else {
                        env.selectionManager.clearSelection()
                        itemsToDrag = [.tab(tab)]
                    }

                    let originPosition: ItemPosition = switch collection {
                    case .favorites: .favorites(localIndex: meta.indexInCollection)
                    case .pinned: .pinned(localIndex: meta.indexInCollection)
                    case .normal: .normal(localIndex: meta.indexInCollection)
                    }

                    env.dragCoordinator.startDrag(
                        items: itemsToDrag,
                        originPosition: originPosition,
                        startLocation: value.startLocation,
                    )
                }

                env.dragCoordinator.updateDrag(
                    offset: value.translation.height,
                    location: value.location,
                )
            }
            .onEnded { _ in
                env.dragCoordinator.commitDrag()
                env.selectionManager.clearSelection()
            }
    }

    // MARK: - Click Handling

    private func handleTabClick(_ tab: Tab) {
        if tab.isArchived {
            env.tabManager.showingRestorePopoverForTabID = tab.id
            return
        }

        let commandDown = NSEvent.modifierFlags.contains(.command)
        let shiftDown = NSEvent.modifierFlags.contains(.shift)

        let shouldActivate = env.selectionManager.handleClick(
            on: tab,
            commandDown: commandDown,
            shiftDown: shiftDown,
        )

        if shouldActivate {
            env.tabManager.setActiveTab(tab, in: env.windowState)
            env.selectionManager.updateAnchorToActiveTab()
        }
    }

}

// MARK: - Group Header Cell

/// Group header cell matching `TabList.groupHeaderView(group:collection:)`.
struct GroupHeaderCell: View {
    let group: TabGroup
    let collection: SidebarCollection

    @Environment(SidebarCellEnvironment.self) private var env

    var body: some View {
        let isHidden = env.dragCoordinator.shouldHideItemDuringDrag(group.id)

        TabGroupHeaderView(
            group: group,
            isActive: env.windowState.activeTab?.groupID == group.id,
            isDragging: env.dragCoordinator.primaryDraggedItem?.group?.id == group.id,
        )
        .frame(height: Constants.Layout.tabItemHeight)
        .opacity(isHidden ? 0 : 1)
        .animation(nil, value: env.dragCoordinator.isAnimatingReturn)
        .contentShape(Rectangle())
        .allowsHitTesting(!env.dragCoordinator.isDragging)
        .gesture(groupDragGesture)
        .padding(.horizontal, Constants.Layout.tabHorizontalPadding)
        .padding(.leading, CGFloat(env.layoutManager.nestingLevel(for: group.id)) * Constants.Layout.nestingLevelPadding)
        .padding(.top, topPadding)
    }

    // MARK: - Drag Gesture

    private var groupDragGesture: some Gesture {
        DragGesture(minimumDistance: Constants.TabDrag.minimumDragDistance, coordinateSpace: .global)
            .onChanged { value in
                guard !env.dragCoordinator.isAnimatingReturn else { return }
                if !env.dragCoordinator.isDragging,
                   let metadata = env.layoutManager.metadata[group.id]
                {
                    env.dragCoordinator.startDrag(
                        item: .group(group),
                        originPosition: ItemPosition.from(metadata: metadata),
                        startLocation: value.startLocation,
                    )
                }
                env.dragCoordinator.updateDrag(
                    offset: value.translation.height,
                    location: value.location,
                )
            }
            .onEnded { _ in
                env.dragCoordinator.commitDrag()
            }
    }

    private var topPadding: CGFloat {
        guard let metadata = env.layoutManager.metadata[group.id],
              metadata.indexInCollection > 0 else { return 0 }
        return metadata.topPadding
    }
}

// MARK: - New Tab Button Cell

/// New tab button cell with conditional section divider.
struct NewTabButtonCell: View {
    @Environment(SidebarCellEnvironment.self) private var env

    private var shouldShowDivider: Bool {
        !env.layoutManager.pinnedItems.isEmpty || !env.layoutManager.favoritesLayout.isEmpty
    }

    var body: some View {
        NewTabView()
            .padding(.top, shouldShowDivider ? 9 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: shouldShowDivider)
            .overlay(alignment: .top) {
                sectionDivider
            }
            .offset(y: env.dragCoordinator.newTabButtonPushOffset)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: env.dragCoordinator.newTabButtonPushOffset)
    }

    private var sectionDivider: some View {
        let centerOffset: CGFloat = 2
        let isVisible = env.dragCoordinator.shouldShowDividerDuringDrag
        return Divider()
            .padding(.horizontal)
            .offset(y: centerOffset)
            .opacity(isVisible ? 1 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isVisible)
    }
}

// MARK: - Compact Tab Row Cell

/// Compact tab cell for the recycling tab list.
struct CompactTabRowCell: View {
    let tab: Tab
    let activeTabID: Tab.ID?

    @Environment(SidebarCellEnvironment.self) private var env

    var body: some View {
        CompactTabButton(
            tab: tab,
            isSelected: tab.id == activeTabID,
            tooltipFrameProvider: env.globalFrameForItem,
        )
    }
}

// MARK: - Compact Group Header Row Cell

/// Compact group header cell for the recycling tab list.
///
/// Computes aggregate child state (active/unread) from the group's tabs relationship.
struct CompactGroupHeaderRowCell: View {
    let group: TabGroup
    let activeTabID: Tab.ID?

    @Environment(SidebarCellEnvironment.self) private var env

    var body: some View {
        CompactGroupHeader(
            group: group,
            hasActiveChild: group.tabs.contains { $0.id == activeTabID },
            hasUnreadChild: group.tabs.contains { $0.isUnread },
            tooltipFrameProvider: env.globalFrameForItem,
        )
    }
}

// MARK: - Compact Divider Cell

/// Section divider between pinned and normal tabs in compact mode.
struct CompactDividerCell: View {
    var body: some View {
        Divider()
            .padding(.horizontal, CompactSidebarLayout.dividerHorizontalPadding)
    }
}

// MARK: - Compact Command Lens Cell

/// Command lens / filter button cell in compact mode.
///
/// Opens the command lens on click, or the filter popover on Option+click.
struct CompactCommandLensCell: View {
    @Environment(SidebarCellEnvironment.self) private var env

    @State private var showingFilterPopover = false

    var body: some View {
        Button {
            if NSEvent.modifierFlags.contains(.option) {
                showingFilterPopover = true
            } else {
                env.windowState.openCommandLens()
            }
        } label: {
            Image(
                systemName: env.filterManager.hasActiveFilter
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "sparkle.magnifyingglass"
            )
            .font(.system(size: CompactSidebarLayout.Icon.standardSize, weight: .medium))
            .foregroundStyle(env.filterManager.hasActiveFilter ? Color.appAccentColor : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: CompactSidebarLayout.buttonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(
            env.filterManager.hasActiveFilter
                ? "Filter Active (⌥ Click to edit)"
                : "Command Lens (⌥ Click to filter)"
        )
        .arrowlessPopover(isPresented: $showingFilterPopover, arrowEdge: .trailing) {
            CompactFilterPopover(filterManager: env.filterManager)
        }
        .onChange(of: showingFilterPopover) { _, isShowing in
            if !isShowing {
                env.filterManager.searchText = ""
            }
        }
    }
}

/// Filter popover content for the compact command lens cell.
private struct CompactFilterPopover: View {
    @Bindable var filterManager: Sidebar.FilterManager

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "line.3.horizontal.decrease")
                    .foregroundStyle(.secondary)
                TextField("Filter tabs...", text: $filterManager.searchText)
                    .textFieldStyle(.plain)
                if filterManager.hasActiveFilter {
                    Button {
                        filterManager.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .frame(width: 200)
    }
}
