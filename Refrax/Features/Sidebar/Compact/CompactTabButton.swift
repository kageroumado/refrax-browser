import SwiftUI

// MARK: - Compact Tab Button

/// A dock-style tab button showing favicon with close on hover.
///
/// Uses a Discord-style indicator system on the left edge:
/// - Unread tabs: small semi-circle
/// - Hovered tabs: medium semi-capsule
/// - Selected tabs: tall semi-capsule
struct CompactTabButton: View {
    @Environment(TabManager.self) private var tabManager
    @Environment(WindowState.self) private var windowState

    let tab: Tab
    let isSelected: Bool
    var groupColor: Color?
    /// Returns the global (screen) frame for the cell, used for tooltip positioning.
    /// Provided by the recycling list coordinator via AppKit coordinates.
    var tooltipFrameProvider: ((_ itemID: UUID) -> CGRect)?

    @State private var isHovered = false
    @State private var isShowingInfoPopover = false

    enum Layout {
        static let faviconSize: CGFloat = 32
        static let faviconPadding: CGFloat = 6
        static let buttonHeight: CGFloat = faviconSize + 12
        static let backgroundOpacity: Double = 0.2

        enum Indicator {
            static let width: CGFloat = 8
            static let unreadHeight: CGFloat = 8
            static let hoverHeight: CGFloat = 12
            static let selectedHeight: CGFloat = 20
            static let animationDuration: Double = 0.15
        }

        enum CloseButton {
            static let size: CGFloat = 12
            static let iconSize: CGFloat = 7
            static let backgroundOpacity: Double = 0.9
            static let offset: CGFloat = 3
        }
    }

    var body: some View {
        Button {
            tabManager.setActiveTab(tab, in: windowState)
        } label: {
            TabFaviconView(tab: tab, size: Layout.faviconSize)
                .faviconBackground(groupColor ?? .secondary.opacity(Layout.backgroundOpacity))
                .overlay {
                    CompactTabLoadingRing(
                        tab: tab,
                        size: Layout.faviconSize
                    )
                }
                .padding(Layout.faviconPadding)
                .overlay(alignment: .topLeading) {
                    if isHovered {
                        closeButton
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .overlay(alignment: .topTrailing) {
                    multiPageBadge
                }
                .overlay(alignment: .bottomTrailing) {
                    if !isHovered {
                        CompactTabStatusBadge(tab: tab)
                            .padding(Layout.faviconPadding)
                            .allowsHitTesting(true)
                    }
                }
                .contentShape(Rectangle())
        }
        .frame(height: Layout.buttonHeight)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .leading) {
            indicator
                // Use transaction instead of double .animation() modifiers.
                // This is more efficient and avoids redundant animation tracking.
                .transaction { transaction in
                    transaction.animation = .snappy(duration: Layout.Indicator.animationDuration)
                }
                .offset(x: -Layout.Indicator.width / 2)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                // Use AppKit frame lookup if available (recycling list),
                // providing accurate positioning without SwiftUI geometry overhead.
                if let globalFrame = tooltipFrameProvider?(tab.id) {
                    windowState.compactTabTooltipFrame = globalFrame
                }
                windowState.startCompactTabTooltipHover(title: tab.displayTitle)
            } else {
                windowState.endCompactTabTooltipHover()
            }
        }
        .onChange(of: tab.id) {
            isHovered = false
            isShowingInfoPopover = false
            windowState.endCompactTabTooltipHover()
        }
        .onDisappear {
            windowState.endCompactTabTooltipHover()
        }
        .contextMenu {
            SidebarContextMenus.Tab(
                tab: tab,
                isCompactMode: true,
                onGetInfo: { isShowingInfoPopover = true },
            )
        }
        .if(isShowingInfoPopover) { view in
            view.popover(isPresented: $isShowingInfoPopover, arrowEdge: .trailing) {
                TabInfoPopover(tab: tab, isPresented: $isShowingInfoPopover)
            }
        }
    }

    // MARK: - Indicator

    private var indicator: some View {
        let height = if isSelected {
            Layout.Indicator.selectedHeight
        } else if isHovered {
            Layout.Indicator.hoverHeight
        } else if tab.isUnread {
            Layout.Indicator.unreadHeight
        } else {
            0.0
        }
        return Capsule()
            .fill(Color.primary)
            .frame(width: Layout.Indicator.width, height: height)
    }

    // MARK: - Multi-Page Badge

    @ViewBuilder
    private var multiPageBadge: some View {
        if tab.pages.count > 1 {
            Text("\(tab.pages.count)")
                .font(.system(size: CompactSidebarLayout.Badge.iconSize, weight: .bold))
                .foregroundStyle(.white)
                .frame(
                    width: CompactSidebarLayout.Badge.size,
                    height: CompactSidebarLayout.Badge.size
                )
                .background {
                    Circle()
                        .fill(Color.secondary.opacity(CompactSidebarLayout.Badge.backgroundOpacity))
                }
                .offset(
                    x: -CompactSidebarLayout.Badge.offset,
                    y: CompactSidebarLayout.Badge.offset
                )
        }
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button {
            tabManager.requestCloseTab(tab)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: Layout.CloseButton.iconSize, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: Layout.CloseButton.size, height: Layout.CloseButton.size)
                .background(
                    Circle()
                        .fill(Color.secondary.opacity(Layout.CloseButton.backgroundOpacity)),
                )
        }
        .buttonStyle(.plain)
        .offset(x: Layout.CloseButton.offset, y: Layout.CloseButton.offset)
    }
}
