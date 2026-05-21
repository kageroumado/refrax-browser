import SwiftUI

/// Sticky indicator that appears when the active tab scrolls out of view.
///
/// Shows the active tab's favicon and title pinned at the top or bottom edge
/// of the visible tab list area. Clicking it scrolls the list to reveal the
/// active tab in its natural position.
///
/// ## Coordinate System
///
/// `GeometryState.itemFrame(for:)` returns positions in sidebar-local coordinates
/// where y=0 is the sidebar's top edge. The visible content area spans from
/// `currentScrollTopInset` (below the header) to `sidebarBounds.height -
/// bottomControlsHeight` (above the footer). Tabs whose frame falls outside
/// this range are considered off-screen.
struct ActiveTabIndicator: View {
    @Environment(ScrollToItemProxy.self) private var scrollProxy

    @Environment(WindowState.self) private var windowState
    @Environment(Sidebar.GeometryState.self) private var geometryState
    @Environment(Sidebar.LayoutManager.self) private var layoutManager
    @Environment(Sidebar.DragCoordinator.self) private var dragCoordinator
    @Environment(Sidebar.TransitionCoordinator.self) private var transitionCoordinator

    // MARK: - Position

    private enum Position: Equatable, Hashable {
        case above
        case below
    }

    /// Determines where the active tab is relative to the visible scroll area.
    ///
    /// Returns nil when the tab is visible or when the indicator should be hidden
    /// (during drags, transitions, live favorites, or when geometry isn't ready).
    ///
    /// Uses `GeometryState.activeTabScrollPosition` which is computed in the
    /// scroll handler. This avoids depending on `documentToSidebarOffset` (which
    /// is `@ObservationIgnored` and wouldn't trigger re-evaluation on scroll).
    private var position: Position? {
        guard windowState.activeTabID != nil,
              !windowState.isShowingLiveFavorite,
              !dragCoordinator.isDragging,
              !transitionCoordinator.isTransitioning
        else { return nil }

        switch geometryState.activeTabScrollPosition {
        case .above: return .above
        case .below: return .below
        case .visible: return nil
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let position {
                indicatorButton(position: position)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: position == .above ? .top : .bottom
                    )
                    // Inset the indicator within the content area (below header, above footer)
                    // so it doesn't overlap the address bar or bottom controls.
                    .padding(.top, geometryState.currentScrollTopInset + geometryState.scrollViewInsetPadding)
                    .padding(.bottom, geometryState.bottomControlsHeight)
                    .transition(.move(edge: position == .above ? .top : .bottom).combined(with: .opacity))
                    .id(position)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: position)
    }

    // MARK: - Indicator Button

    private func indicatorButton(position: Position) -> some View {
        Button {
            guard let activeTabID = windowState.activeTabID else { return }
            scrollProxy.scrollTo(activeTabID, anchor: position == .above ? .top : .bottom)
        } label: {
            indicatorLabel
                .padding(.horizontal, Constants.Layout.tabHorizontalPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shadow(
            color: .black.opacity(0.12),
            radius: 8,
            y: position == .above ? 4 : -4
        )
    }

    @ViewBuilder
    private var indicatorLabel: some View {
        if let tab = windowState.activeTab {
            HStack(spacing: 0) {
                TabFaviconView(tab: tab)

                Text(tab.displayTitle)
                    .font(.system(size: Constants.Typography.bodySize))
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, Constants.Spacing.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6)
            .frame(height: Constants.Layout.tabItemHeight)
            .contentShape(Rectangle())
            .padding(.horizontal, Constants.Spacing.small2)
            .adaptiveBackground(.emphasized, in: RoundedRectangle(cornerRadius: Constants.Layout.tabCornerRadius))
        }
    }
}
