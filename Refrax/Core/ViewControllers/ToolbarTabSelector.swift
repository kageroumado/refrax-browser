import SwiftUI

/// Custom tab selector for the reference pane window toolbar.
///
/// Shows a collapsed button with tab count indicator. When clicked, displays
/// a popover with all tabs allowing selection and close actions.
struct ToolbarTabSelector: View {
    let tabs: [Tab]
    let activeTab: Tab?
    let onSelectTab: (Tab) -> Void
    let onCloseTab: (Tab) -> Void

    @State private var isExpanded = false
    @State private var isHovered = false
    @State private var hoveredTabID: UUID?

    private enum Layout {
        static let buttonHeight: CGFloat = 24
        static let tabRowHeight: CGFloat = 28
        static let tabWidth: CGFloat = 180
        static let faviconSize: CGFloat = 14
        static let dotSize: CGFloat = 8
    }

    var body: some View {
        collapsedButton
            .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
                expandedTabsList
            }
    }

    // MARK: - Collapsed Button

    private var collapsedButton: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 4) {
                tabCountIndicator
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .frame(height: Layout.buttonHeight)
            .glassEffect()
            .background {
                Capsule()
                    .fill(.secondary)
                    .opacity(isHovered ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var tabCountIndicator: some View {
        if tabs.count > 1 {
            HStack(spacing: 3) {
                ForEach(0 ..< min(tabs.count, 4), id: \.self) { index in
                    Circle()
                        .fill(tabs[index].id == activeTab?.id ? Color.primary : Color.secondary.opacity(0.2))
                        .frame(width: Layout.dotSize, height: Layout.dotSize)
                }
            }
        } else {
            Image(systemName: "square.on.square")
                .font(.system(size: 16, weight: .regular))
        }
    }

    // MARK: - Expanded Tabs List

    private var expandedTabsList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(tabs) { tab in
                tabRow(tab)
            }
        }
        .padding(6)
    }

    private func tabRow(_ tab: Tab) -> some View {
        let isActive = tab.id == activeTab?.id
        let isRowHovered = hoveredTabID == tab.id

        return Button {
            onSelectTab(tab)
            isExpanded = false
        } label: {
            HStack(spacing: 6) {
                tabRowLeadingContent(tab: tab, isActive: isActive, isHovered: isRowHovered)
                    .frame(width: Layout.faviconSize, height: Layout.faviconSize)
                    .animation(.easeInOut(duration: 0.15), value: isRowHovered)

                Text(tab.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(isActive ? .white : .primary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(width: Layout.tabWidth, height: Layout.tabRowHeight)
            .background {
                tabRowBackground(isActive: isActive, isHovered: isRowHovered)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredTabID = hovering ? tab.id : nil
        }
    }

    private func tabRowLeadingContent(tab: Tab, isActive: Bool, isHovered: Bool) -> some View {
        ZStack {
            if isHovered {
                Button {
                    onCloseTab(tab)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isActive ? .white : .primary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            } else {
                FaviconView(data: tab.activePage.faviconData, url: tab.activePage.url, size: Layout.faviconSize)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func tabRowBackground(isActive: Bool, isHovered: Bool) -> some View {
        let fillColor = if isActive {
            Color.appAccentColor
        } else if isHovered {
            Color.secondary.opacity(0.2)
        } else {
            Color.clear
        }
        return Capsule().fill(fillColor)
    }
}
