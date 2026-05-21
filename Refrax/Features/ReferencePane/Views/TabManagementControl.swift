import SwiftUI

/// Custom alignment for vertically centering on the active tab.
extension VerticalAlignment {
    private enum ActiveTabAlignment: AlignmentID {
        nonisolated static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    nonisolated static let activeTab = VerticalAlignment(ActiveTabAlignment.self)
}

/// Expandable tab management control for the reference pane.
///
/// Displays collapsed dots that expand on hover to show full tab buttons
/// with titles, close buttons, and utility actions.
struct TabManagementControl: View {
    @Environment(WindowState.self) private var windowState
    
    let tabs: [Refrax.Tab]
    let activeTab: Refrax.Tab?
    let canAddTab: Bool
    let onSelectTab: (Refrax.Tab) -> Void
    let onCloseTab: (Refrax.Tab) -> Void
    let onAddTab: () -> Void
    let onOpenInWindow: () -> Void

    @State private var isExpanded = false
    @State private var hoveredTabID: UUID?
    @State private var closingTabID: UUID?
    @State private var isCommandLensHovered: Bool = false
    @State private var isNewWindowHovered: Bool = false

    @Namespace private var animation
    @Namespace private var tabsNamespace

    private enum Layout {
        static let dotSize: CGFloat = 7
        static let activeDotSize: CGFloat = 9
        static let dotSpacing: CGFloat = 6
        static let buttonSize: CGFloat = 28
        static let tabButtonWidth: CGFloat = 140
        static let collapsedPadding: CGFloat = 8
        static let tabCornerRadius: CGFloat = 14
        static let iconSize: CGFloat = 16
        static let fontSize: CGFloat = 10
        static let closeIconSize: CGFloat = 8
    }

    var body: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 0) {
                if isExpanded {
                    expandedTabsList
                } else {
                    collapsedDots
                }
            }
            .padding(4)
        }
        .onHover { hovering in
            windowState.webViewsShouldIgnoreAllEvents = hovering
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                isExpanded = hovering
            }
        }
        .accessibilityIdentifier("reference-pane-tab-control")
        .accessibilityLabel("Reference pane tab management")
    }

    // MARK: - Collapsed Dots

    private var collapsedDots: some View {
        VStack(spacing: Layout.dotSpacing) {
            ForEach(tabs) { tab in
                let isActive = tab.id == activeTab?.id

                Circle()
                    .fill(isActive ? Color.primary : Color.clear)
                    .frame(
                        width: isActive ? Layout.activeDotSize : Layout.dotSize,
                        height: isActive ? Layout.activeDotSize : Layout.dotSize,
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.3), lineWidth: 1)
                            .opacity(isActive ? 0 : 1),
                    )
                    .matchedGeometryEffect(id: "tab_\(tab.id)", in: animation)
                    .alignmentGuide(.activeTab) { d in
                        isActive ? d[VerticalAlignment.center] : d[.activeTab]
                    }
            }
        }
        .padding(Layout.collapsedPadding)
        .glassEffect()
    }

    // MARK: - Expanded Tabs List

    private var expandedTabsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(tabs) { tab in
                tabButton(tab)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8, anchor: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity),
                    ))
            }

            utilityButtonsSection
        }
    }

    // MARK: - Utility Buttons

    private var utilityButtonsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if canAddTab {
                utilityButton(
                    title: "Command Lens",
                    icon: "sparkle.magnifyingglass",
                    isHovered: isCommandLensHovered,
                    action: onAddTab,
                )
                .onHover { hovering in
                    isCommandLensHovered = hovering
                }
                .accessibilityIdentifier("reference-pane-add-tab")
                .accessibilityLabel("Add reference tab via Command Lens")
            }

            utilityButton(
                title: "Move to Window",
                icon: "macwindow.on.rectangle",
                isHovered: isNewWindowHovered,
                action: onOpenInWindow,
            )
            .onHover { hovering in
                isNewWindowHovered = hovering
            }
            .accessibilityIdentifier("reference-pane-move-to-window")
            .accessibilityLabel("Move reference pane to separate window")
        }
    }

    private func utilityButton(
        title: String,
        icon: String,
        isHovered: Bool,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: Layout.fontSize, weight: .medium))
                    .frame(width: Layout.iconSize, height: Layout.iconSize)

                Text(title)
                    .font(.system(size: Layout.fontSize, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .frame(width: Layout.tabButtonWidth, height: Layout.buttonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: Layout.tabCornerRadius - 2)
                    .fill(.secondary)
                    .padding(2)
                    .opacity(0.15)
            }
        }
        .glassEffect(in: RoundedRectangle(cornerRadius: Layout.tabCornerRadius))
        .glassEffectUnion(id: "tabs_union", namespace: tabsNamespace)
    }

    // MARK: - Tab Button

    private func tabButton(_ tab: Tab) -> some View {
        let isActive = tab.id == activeTab?.id
        let isHovered = hoveredTabID == tab.id
        let isClosing = closingTabID == tab.id

        return Button(action: {
            if !isActive {
                onSelectTab(tab)
            }
        }) {
            HStack(spacing: 6) {
                // Left icon: close button on hover, favicon otherwise
                ZStack {
                    if isHovered, !isClosing {
                        Button(action: {
                            closeTab(tab)
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: Layout.closeIconSize, weight: .medium))
                                .foregroundStyle(isActive ? .white.opacity(0.9) : .primary)
                                .frame(width: Layout.iconSize, height: Layout.iconSize)
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        FaviconView(data: tab.activePage.faviconData, url: tab.activePage.url, size: Layout.iconSize)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .animation(.easeInOut(duration: 0.15), value: isHovered)

                // Title
                Text(tab.displayTitle)
                    .font(.system(size: Layout.fontSize, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(isActive ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .frame(width: Layout.tabButtonWidth, height: Layout.buttonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: Layout.tabCornerRadius - 2)
                    .fill(.secondary)
                    .padding(2)
                    .opacity(0.15)
            }
        }
        .glassEffect(
            isActive ? .regular.interactive() : .regular,
            in: RoundedRectangle(cornerRadius: Layout.tabCornerRadius),
        )
        .glassEffectUnion(id: "tabs_union", namespace: tabsNamespace)
        .matchedGeometryEffect(id: "tab_\(tab.id)", in: animation)
        .alignmentGuide(.activeTab) { d in
            isActive ? d[VerticalAlignment.center] : d[.activeTab]
        }
        .opacity(isClosing ? 0 : 1)
        .scaleEffect(isClosing ? 0.8 : 1, anchor: .leading)
        .animation(.easeIn(duration: 0.2), value: isClosing)
        .onHover { hovering in
            hoveredTabID = hovering ? tab.id : nil
        }
        .contextMenu {
            SidebarContextMenus.ReferenceTab(tab: tab)
        }
    }

    // MARK: - Actions

    private func closeTab(_ tab: Tab) {
        closingTabID = tab.id

        // Wait for tab slide-out animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                onCloseTab(tab)
                closingTabID = nil
            }
        }
    }
}
