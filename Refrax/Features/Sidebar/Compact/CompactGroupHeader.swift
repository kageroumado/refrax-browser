import SwiftUI

/// Compact sidebar representation of a tab group.
///
/// The group icon is always rendered at the same size and position regardless
/// of collapsed/expanded state. All sub-elements (squircle background, badge,
/// indicator) are always in the view tree with animated properties — no `if/else`
/// branching — so SwiftUI can interpolate smoothly between states.
///
/// Left-edge indicator reflects aggregate child state (active/unread).
struct CompactGroupHeader: View {
    @Environment(TabGroupManager.self) private var groupManager
    @Environment(WindowState.self) private var windowState

    let group: TabGroup

    /// Whether any child tab is the active tab.
    let hasActiveChild: Bool

    /// Whether any child tab is unread.
    let hasUnreadChild: Bool

    /// Returns the global (screen) frame for the cell, used for tooltip positioning.
    var tooltipFrameProvider: ((_ itemID: UUID) -> CGRect)?

    @State private var isHovered = false
    @State private var isShowingEditPopover = false

    private typealias Layout = CompactSidebarLayout
    private typealias GroupLayout = CompactSidebarLayout.Group

    var body: some View {
        Button {
            groupManager.toggleGroupCollapsed(group)
        } label: {
            ZStack(alignment: .bottomTrailing) {
                groupIcon
                    .frame(width: Layout.buttonSize, height: Layout.buttonSize)
                    .background {
                        SquircleShape()
                            .fill(group.color.opacity(GroupLayout.collapsedBackgroundOpacity))
                            .opacity(group.isCollapsed ? 1 : 0)
                    }
                    .padding(CompactTabButton.Layout.faviconPadding)

                tabCountBadge
                    .opacity(group.isCollapsed ? 1 : 0)
                    .scaleEffect(group.isCollapsed ? 1 : 0.5)
            }
            .contentShape(Rectangle())
        }
        .frame(height: CompactTabButton.Layout.buttonHeight)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
            indicator
                .offset(x: -CompactTabButton.Layout.Indicator.width / 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                if let globalFrame = tooltipFrameProvider?(group.id) {
                    windowState.compactTabTooltipFrame = globalFrame
                }
                windowState.startCompactTabTooltipHover(title: group.name)
            } else {
                windowState.endCompactTabTooltipHover()
            }
        }
        .onChange(of: group.id) {
            isHovered = false
            isShowingEditPopover = false
            windowState.endCompactTabTooltipHover()
        }
        .onDisappear {
            windowState.endCompactTabTooltipHover()
        }
        .help(group.name)
        .contextMenu {
            SidebarContextMenus.Group(
                group: group,
                onEditGroup: { isShowingEditPopover = true }
            )
        }
        .if(isShowingEditPopover) { view in
            view.popover(isPresented: $isShowingEditPopover, arrowEdge: .trailing) {
                groupSettingsPopover
            }
        }
    }

    // MARK: - Group Icon

    @ViewBuilder
    private var groupIcon: some View {
        if let iconName = group.iconName, !iconName.isEmpty {
            if group.isEmoji {
                Text(iconName)
                    .font(.system(size: GroupLayout.iconSize))
            } else {
                Image(systemName: iconName)
                    .font(.system(size: GroupLayout.iconSize, weight: .medium))
                    .foregroundStyle(group.color)
            }
        } else {
            Image(systemName: "folder.fill")
                .font(.system(size: GroupLayout.iconSize, weight: .medium))
                .foregroundStyle(group.color)
        }
    }

    // MARK: - Tab Count Badge

    private var tabCountBadge: some View {
        let count = group.tabs.count
        return Text("\(count)")
            .font(.system(size: Layout.Badge.iconSize, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: Layout.Badge.size, height: Layout.Badge.size)
            .background {
                Circle()
                    .fill(group.color.opacity(Layout.Badge.backgroundOpacity))
            }
            .offset(x: -Layout.Badge.offset, y: -Layout.Badge.offset)
    }

    // MARK: - Indicator

    /// Indicator is only relevant when collapsed (expanded groups show
    /// per-tab indicators on their children instead).
    private var indicator: some View {
        let height: CGFloat = if !group.isCollapsed {
            0.0
        } else if hasActiveChild {
            CompactTabButton.Layout.Indicator.selectedHeight
        } else if isHovered {
            CompactTabButton.Layout.Indicator.hoverHeight
        } else if hasUnreadChild {
            CompactTabButton.Layout.Indicator.unreadHeight
        } else {
            0.0
        }
        return Capsule()
            .fill(Color.primary)
            .frame(width: CompactTabButton.Layout.Indicator.width, height: height)
            .animation(.snappy(duration: CompactTabButton.Layout.Indicator.animationDuration), value: height)
    }

    // MARK: - Group Settings Popover

    private var groupSettingsPopover: some View {
        GroupSettingsPopover(
            name: Binding(
                get: { group.name },
                set: { newName in
                    groupManager.renameGroup(group, to: newName)
                }
            ),
            selectedIcon: Binding(
                get: { group.iconName },
                set: { newIcon in
                    groupManager.updateGroupIcon(group, to: newIcon)
                }
            ),
            selectedColorHex: Binding(
                get: { group.colorString },
                set: { newColor in
                    groupManager.updateGroupColor(group, to: newColor)
                }
            ),
            isPresented: $isShowingEditPopover
        )
    }
}
