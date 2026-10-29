import SwiftUI

struct ControlIslandFavoriteIcon: View {
    let favorite: FavoriteItem
    let tab: Tab
    let isSelected: Bool
    @Environment(\.appearsActive) private var appearsActive

    enum Layout {
        static let faviconSize = ControlIslandPlacement.pageIconSize
        static let rowHeight = ControlIslandPlacement.rowHeight
        static let selectionWidth: CGFloat = 3
        static let selectionHeight: CGFloat = 16
    }

    var body: some View {
        FaviconView(data: favorite.largeFaviconData, url: tab.activePage.url, size: Layout.faviconSize)
            .faviconBackground()
            .overlay { TabLoadingRing(tab: tab, size: Layout.faviconSize) }
            .saturation(appearsActive ? 1 : 0)
            .frame(maxWidth: .infinity)
            .frame(height: Layout.rowHeight)
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(appearsActive ? Color.primary : Color.secondary)
                        .frame(width: Layout.selectionWidth, height: Layout.selectionHeight)
                }
            }
            .contentShape(Rectangle())
    }
}
