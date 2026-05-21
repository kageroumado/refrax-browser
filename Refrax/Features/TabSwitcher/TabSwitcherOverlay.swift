import SwiftUI

/// Overlay view displaying the Control+Tab tab switcher.
///
/// Shows a horizontal row of recently used tabs with preview thumbnails
/// and titles. The currently selected tab is highlighted.
///
/// ## Architecture
///
/// This view is rendered in `OverlayContainer` which sits above all split view
/// content. It uses `TabSwitcherManager` to access the list of recent tabs
/// and the current selection state.
///
/// ## Layout
///
/// ```
/// ┌─────────────────────────────────────────────────────────────────┐
/// │                          Glass Container                        │
/// │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐│
/// │  │ Preview │  │ Preview │  │ Preview │  │ Preview │  │ Preview ││
/// │  │         │  │         │  │ (sel)   │  │         │  │         ││
/// │  │─────────│  │─────────│  │─────────│  │─────────│  │─────────││
/// │  │  Title  │  │  Title  │  │  Title  │  │  Title  │  │  Title  ││
/// │  └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘│
/// └─────────────────────────────────────────────────────────────────┘
/// ```
struct TabSwitcherOverlay: View {
    @Environment(TabSwitcherManager.self) private var tabSwitcherManager

    var body: some View {
        if tabSwitcherManager.isActive {
            ZStack {
                switcherContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
            .animation(.spring(duration: 0.15), value: tabSwitcherManager.selectedIndex)
        }
    }

    private var switcherContent: some View {
        HStack(spacing: Layout.itemSpacing) {
            ForEach(Array(tabSwitcherManager.recentTabs.enumerated()), id: \.element.id) { index, tab in
                TabSwitcherItem(
                    tab: tab,
                    isSelected: index == tabSwitcherManager.selectedIndex,
                )
            }
        }
        .padding(Layout.containerPadding)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Layout.containerCornerRadius))
        .shadow(color: .black.opacity(0.25), radius: Layout.shadowRadius, y: Layout.shadowY)
    }

    // MARK: - Constants

    private enum Layout {
        static let containerPadding: CGFloat = 16
        static let containerCornerRadius: CGFloat = 24
        static let itemSpacing: CGFloat = 12
        static let shadowRadius: CGFloat = 32
        static let shadowY: CGFloat = 8
    }
}

// MARK: - Tab Switcher Item

/// Individual tab item in the switcher showing preview and title.
///
/// Only the preview thumbnail is highlighted when selected, mirroring
/// macOS Cmd+Tab behavior where only the icon gets the selection background.
private struct TabSwitcherItem: View {
    let tab: Tab
    let isSelected: Bool

    var body: some View {
        VStack(spacing: Layout.contentSpacing) {
            previewContainer
            titleView
        }
        .frame(width: Layout.itemWidth)
    }

    private var previewContainer: some View {
        previewContent
            .padding(Layout.selectionPadding)
            .background(selectionBackground)
            .clipShape(RoundedRectangle(cornerRadius: Layout.selectionCornerRadius))
    }

    @ViewBuilder
    private var previewContent: some View {
        WebViewThumbnail(tabID: tab.id)
            .frame(width: Layout.previewWidth, height: Layout.previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: Layout.previewCornerRadius))
    }

    private var fallbackPreview: some View {
        RoundedRectangle(cornerRadius: Layout.previewCornerRadius)
            .fill(.quaternary)
            .frame(width: Layout.previewWidth, height: Layout.previewHeight)
            .overlay {
                faviconView
            }
    }

    @ViewBuilder
    private var faviconView: some View {
        FaviconView(data: tab.activePage.faviconData, url: tab.activePage.url, size: Layout.faviconSize)
    }

    private var titleView: some View {
        Text(tab.displayTitle)
            .font(.callout)
            .fontWeight(isSelected ? .medium : .regular)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity)
            .foregroundStyle(isSelected ? .primary : .secondary)
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: Layout.selectionCornerRadius)
                .fill(Color("TabSwitcherSelection"))
                .overlay {
                    RoundedRectangle(cornerRadius: Layout.selectionCornerRadius)
                        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                }
        }
    }

    // MARK: - Constants

    private enum Layout {
        static let itemWidth: CGFloat = 160
        static let contentSpacing: CGFloat = 8
        static let previewWidth: CGFloat = 144
        static let previewHeight: CGFloat = 90
        static let previewCornerRadius: CGFloat = 8
        static let selectionPadding: CGFloat = 8
        static let selectionCornerRadius: CGFloat = 12
        static let faviconSize: CGFloat = 32
    }
}
