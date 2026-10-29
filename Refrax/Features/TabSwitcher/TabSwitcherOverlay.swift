import SwiftUI

/// Recent tabs support click selection, outside dismissal, and Control-Tab navigation.
struct TabSwitcherOverlay: View {
    @Environment(TabSwitcherManager.self) private var switcher

    var body: some View {
        if switcher.isActive {
            GeometryReader { geometry in
                ZStack {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { switcher.cancel() }
                        .accessibilityLabel("Dismiss recent tabs")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { switcher.cancel() }
                    switcherContent
                        .frame(width: min(contentWidth, max(1, geometry.size.width - Layout.windowInset * 2)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .transition(.opacity)
        }
    }

    private var contentWidth: CGFloat {
        CGFloat(switcher.recentTabs.count) * Layout.itemWidth
            + CGFloat(max(0, switcher.recentTabs.count - 1)) * Layout.itemSpacing
            + Layout.containerPadding * 2
    }

    private var switcherContent: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Recent Tabs").font(.callout.weight(.semibold))
                Spacer()
                Button {
                    switcher.cancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                    .accessibilityLabel("Dismiss recent tabs")
                    .buttonStyle(ControlIslandButtonStyle())
                    .focusEffectDisabled()
                    .help("Dismiss recent tabs · Esc")
            }
            ScrollViewReader { reader in
                ScrollView(.horizontal) {
                    HStack(spacing: Layout.itemSpacing) {
                        ForEach(Array(switcher.recentTabs.enumerated()), id: \.element.id) { index, tab in
                            Button {
                                switcher.activate(tabID: tab.id)
                            } label: {
                                TabSwitcherItem(tab: tab, isSelected: index == switcher.selectedIndex)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(ControlIslandButtonStyle())
                            .focusEffectDisabled()
                            .accessibilityLabel("Switch to \(tab.displayTitle)")
                            .id(tab.id)
                        }
                    }
                }
                .scrollIndicators(.automatic)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: Layout.itemHeight)
                .onChange(of: switcher.selectedIndex, initial: true) { _, index in
                    if switcher.recentTabs.indices.contains(index) {
                        reader.scrollTo(switcher.recentTabs[index].id, anchor: .center)
                    }
                }
            }
        }
        .padding(Layout.containerPadding)
        .background { Color.clear.contentShape(Rectangle()).onTapGesture {} }
        .glassEffect(.regular, in: .rect(cornerRadius: Layout.containerCornerRadius))
        .shadow(color: .black.opacity(0.25), radius: 32, y: 8)
    }

    private enum Layout {
        static let containerPadding: CGFloat = 16
        static let containerCornerRadius: CGFloat = 24
        static let itemSpacing: CGFloat = 12
        static let itemWidth: CGFloat = 160
        static let itemHeight: CGFloat = 136
        static let windowInset: CGFloat = 24
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
            .allowsHitTesting(false)
            .frame(width: Layout.previewWidth, height: Layout.previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: Layout.previewCornerRadius))
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
    }
}
