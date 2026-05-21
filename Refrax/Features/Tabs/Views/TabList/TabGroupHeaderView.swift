import SwiftUI

/// A header row for tab groups in the sidebar
///
/// This view displays a collapsible group header with:
/// - Group icon and name
/// - Chevron indicating collapsed/expanded state
/// - Tab count badge
/// - Hover states and visual feedback
/// - Pin indicator for pinned groups
/// - Tint color accent on the left edge
///
/// ## Interaction
/// - Single click: Expand/collapse group
/// - Right click: Show context menu with "Edit Group..." option
/// - Drag: Move entire group with all contained tabs
///
/// ## Visual States
/// - Default: Minimal visual weight
/// - Hover: Show material background
/// - Selected: Emphasized background (when any tab in group is active)
struct TabGroupHeaderView: View {
    @Environment(SidebarCellEnvironment.self) private var env

    // MARK: - Public Properties
    
    /// The group model containing name, color, and state
    let group: TabGroup
    
    /// Whether any tab in this group is currently active
    let isActive: Bool
    
    /// Whether this group header is being dragged
    let isDragging: Bool
    
    // MARK: - Private State

    @State private var isLocallyHovered = false

    /// Whether the settings popover is showing
    @State private var showingSettingsPopover = false

    // MARK: - Body
    
    var body: some View {
        contentRow
            .padding(.vertical, 6)
            .frame(height: Constants.Layout.tabItemHeight)
            .contentShape(Rectangle())
            .padding(.horizontal, Constants.Spacing.small2)
            .adaptiveBackground(highlightState, in: RoundedRectangle(cornerRadius: Constants.Layout.tabCornerRadius))
            .onTapGesture {
                if !env.filterManager.hasActiveFilter, group.tabCount > 0 {
                    env.groupManager.toggleGroupCollapsed(group)
                }
            }
            .onHover { hovering in
                isLocallyHovered = hovering
            }
            .contextMenu {
                SidebarContextMenus.Group(
                    group: group,
                    onEditGroup: { showingSettingsPopover = true },
                )
            }
            .if(showingSettingsPopover) { view in
                view.popover(isPresented: $showingSettingsPopover, arrowEdge: .trailing) {
                    settingsPopoverContent
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("GroupHeader")
            .accessibilityLabel(group.name)
            .accessibilityHint("\(group.tabCount) tabs")
            .task {
                // Check if this group should enter editing mode (e.g., just created)
                guard env.groupManager.groupIDToEdit == group.id else { return }

                // Wait for view to appear
                try? await Task.sleep(for: Constants.Animation.renameDelay)
                guard env.groupManager.groupIDToEdit == group.id else { return }

                env.groupManager.groupIDToEdit = nil
                showingSettingsPopover = true
            }
    }
    
    // MARK: - Content Row

    private var contentRow: some View {
        HStack(spacing: Constants.Spacing.small) {
            groupIcon
            groupName
            chevronCountCapsule
        }
    }

    /// Combined chevron, tab count, and pin icon in a single capsule.
    @ViewBuilder
    private var chevronCountCapsule: some View {
        let showChevron = !env.filterManager.hasActiveFilter && group.tabCount > 0

        HStack(spacing: 5) {
            if showChevron {
                Image(systemName: group.isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 9)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: group.isCollapsed)
                    .contentTransition(.symbolEffect(.replace))
            }

            Text("\(group.tabCount)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            if group.isPinned {
                Image(systemName: effectiveHoverState ? "pin.slash.fill" : "pin.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, showChevron ? 6 : 7)
        .padding(.trailing, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))
        .contentShape(Capsule())
        .onTapGesture {
            if group.isPinned {
                env.tabManager.pinGroup(group)
            }
        }
    }
    
    private var groupIcon: some View {
        // Access colorString directly (stored property) so SwiftData observes changes.
        // Using the computed `color` property doesn't trigger observation because
        // SwiftData only tracks stored property access.
        let iconColor = Color.resolveStoredColor(group.colorString)

        return Group {
            if let iconName = group.iconName, group.isEmoji {
                Text(iconName)
                    .font(.system(size: 14))
            } else if let iconName = group.iconName {
                Image(systemName: iconName)
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)
            } else {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundColor(iconColor)
            }
        }
        .frame(width: Constants.Layout.tabFaviconSize, height: Constants.Layout.tabFaviconSize)
    }
    
    /// Group name displayed as static text.
    private var groupName: some View {
        Text(group.name)
            .font(.system(size: Constants.Typography.bodySize, weight: .medium))
            .foregroundColor(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Computed Properties
    
    /// Combines dragging and hover states.
    private var effectiveHoverState: Bool {
        isDragging || (isLocallyHovered && !isDragging)
    }

    /// The background style for the group header.
    ///
    /// Group headers only show subtle state, not emphasis. The `isActive` property
    /// indicates whether a tab within the group is selected, but the header itself
    /// uses subtle styling to avoid visual competition with the selected tab.
    private var highlightState: AdaptiveBackgroundStyle {
        if effectiveHoverState || isActive { return .subtle }
        return .clear
    }
    
    /// Settings popover content for editing name, icon, and color
    private var settingsPopoverContent: some View {
        GroupSettingsPopover(
            name: Binding(
                get: { group.name },
                set: { newName in
                    env.groupManager.renameGroup(group, to: newName)
                },
            ),
            selectedIcon: Binding(
                get: { group.iconName },
                set: { newIcon in
                    env.groupManager.updateGroupIcon(group, to: newIcon)
                },
            ),
            selectedColorHex: Binding(
                get: { group.colorString },
                set: { newColor in
                    env.groupManager.updateGroupColor(group, to: newColor)
                },
            ),
            isPresented: $showingSettingsPopover,
        )
    }
}
