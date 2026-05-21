import SwiftUI

/// Lightweight preview of an adjacent space's tab list during swipe gesture.
///
/// Renders simplified versions of tab and group rows without drag, context menu,
/// selection, or hover state. Used during space swipe gestures to show what tabs
/// exist in the space being swiped toward, creating an iOS home screen page effect.
///
/// The view is always non-interactive (`allowsHitTesting(false)`) since it only
/// appears during an active swipe gesture.
struct AdjacentSpacePreview: View {
    let pinnedItems: [TabListItem]
    let normalItems: [TabListItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(pinnedItems) { item in
                previewRow(for: item, isPinned: true)
            }

            ForEach(normalItems) { item in
                previewRow(for: item, isPinned: false)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func previewRow(for item: TabListItem, isPinned: Bool) -> some View {
        switch item {
        case let .tab(tab):
            tabPreviewRow(tab: tab, isPinned: isPinned)
        case let .group(group):
            groupPreviewRow(group: group)
        }
    }

    private func tabPreviewRow(tab: Tab, isPinned: Bool) -> some View {
        let nestingLevel: Int = tab.groupID != nil ? 1 : 0

        return HStack(spacing: 0) {
            // Favicon
            previewFavicon(tab: tab)

            // Title
            Text(tab.displayTitle)
                .font(.callout)
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .padding(.leading, Constants.Spacing.xSmall)

            Spacer(minLength: 0)

            // Pin indicator
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: Constants.Layout.tabItemHeight)
        .padding(.horizontal, Constants.Layout.tabHorizontalPadding)
        .padding(.leading, CGFloat(nestingLevel) * Constants.Layout.nestingLevelPadding)
    }

    private func groupPreviewRow(group: TabGroup) -> some View {
        HStack(spacing: Constants.Spacing.small) {
            // Chevron
            Image(systemName: group.isCollapsed ? "chevron.right" : "chevron.down")
                .font(.caption)
                .foregroundStyle(.tertiary)

            // Group icon
            if let iconName = group.iconName {
                Image(systemName: iconName)
                    .font(.callout)
                    .foregroundStyle(group.color)
            }

            // Group name
            Text(group.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            // Tab count
            Text("\(group.tabCount)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(height: Constants.Layout.tabItemHeight)
        .padding(.horizontal, Constants.Layout.tabHorizontalPadding)
        .padding(.leading, CGFloat(group.parentGroupID == nil ? 0 : 1) * 20)
    }

    @ViewBuilder
    private func previewFavicon(tab: Tab) -> some View {
        if let faviconData = tab.activePage.faviconData,
           let nsImage = NSImage(data: faviconData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: "globe")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        }
    }
}
