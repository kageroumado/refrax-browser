import SwiftUI

/// Responsive grid of shared favorites in the library drawer.
///
/// Favorites are space-independent and always available. They can be:
/// - **Live tabs**: Persistent tabs that activate when clicked
/// - **Shortcuts**: Navigate current tab to URL
/// - **Folders**: Collections of bookmarks
///
/// Uses `AdaptiveFavoritesGridLayout`, a custom `Layout` that sizes its columns from
/// the width it is offered.
///
/// Tiles are dragged to reorder: a favorite dropped on a later tile lands after it, on an
/// earlier tile before it, in the same shared order the control rail shows.
struct FavoritesGrid: View {
    var showsTitles = false
    @Environment(BookmarksManager.self) private var bookmarksManager
    @State private var draggedID: UUID?
    @State private var dragSessionID: DragSession.ID?
    @State private var targetID: UUID?

    var body: some View {
        AdaptiveFavoritesGridLayout(configuration: gridConfiguration) {
            ForEach(bookmarksManager.favorites) { item in
                tile(item)
            }
        }
        .onChange(of: bookmarksManager.favorites.map(\.id)) { finishDrag() }
        .onDisappear(perform: finishDrag)
        .accessibilityIdentifier("FavoritesGrid")
    }

    private func tile(_ item: FavoriteItem) -> some View {
        FavoriteTileView(item: item, shouldShowTitle: showsTitles)
            .opacity(draggedID == item.id ? Metrics.draggedOpacity : 1)
            .overlay {
                if targetID == item.id, draggedID != item.id {
                    RoundedRectangle(cornerRadius: Metrics.targetCornerRadius)
                        .strokeBorder(Color.appAccentColor, lineWidth: Metrics.targetLineWidth)
                        .allowsHitTesting(false)
                }
            }
            .draggable(ControlIslandFavoriteDrag(id: item.id)) {
                FaviconView(data: item.largeFaviconData, url: item.url, size: Metrics.dragPreviewSize)
                    .faviconBackground()
            }
            .dragConfiguration(DragConfiguration(
                operationsWithinApp: .init(allowCopy: false, allowMove: true),
                operationsOutsideApp: .init(allowCopy: false),
            ))
            .onDragSessionUpdated { trackDrag($0, favoriteID: item.id) }
            .onDrop(of: [ControlIslandFavoriteDrag.contentType], delegate: ControlIslandFavoriteDropDelegate(
                isActive: draggedID != nil,
                onUpdate: { _ in targetID = item.id },
                onExit: {
                    if targetID == item.id {
                        targetID = nil
                    }
                },
                onDrop: { _ in commitDrop(onto: item.id) },
            ))
            .accessibilityAction(named: "Move earlier") { move(item.id, by: -1) }
            .accessibilityAction(named: "Move later") { move(item.id, by: 1) }
    }

    // MARK: - Reordering

    private func commitDrop(onto target: UUID) -> Bool {
        defer { finishDrag() }
        guard let id = draggedID else { return false }
        let ids = bookmarksManager.favorites.map(\.id)
        guard let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target), from != to else { return false }
        // A favorite dropped on a later tile lands after it, on an earlier tile before it.
        let nextID = from < to ? (ids.indices.contains(to + 1) ? ids[to + 1] : nil) : target
        return bookmarksManager.moveFavorite(id, before: nextID)
    }

    private func move(_ id: UUID, by offset: Int) {
        let ids = bookmarksManager.favorites.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        let nextIndex = offset < 0 ? index - 1 : index + 2
        bookmarksManager.moveFavorite(id, before: ids.indices.contains(nextIndex) ? ids[nextIndex] : nil)
    }

    private func trackDrag(_ session: DragSession, favoriteID: UUID) {
        switch session.phase {
        case .initial, .active:
            guard dragSessionID == nil || dragSessionID == session.id else { return }
            dragSessionID = session.id
            draggedID = favoriteID
        case .ended, .dataTransferCompleted:
            if dragSessionID == session.id {
                finishDrag()
            }
        @unknown default:
            finishDrag()
        }
    }

    private func finishDrag() {
        draggedID = nil
        dragSessionID = nil
        targetID = nil
    }

    private var gridConfiguration: AdaptiveFavoritesGridLayout.Configuration {
        AdaptiveFavoritesGridLayout.Configuration(
            minTileWidth: Metrics.minTileWidth,
            tileHeight: Metrics.tileHeight + (showsTitles ? 24 : 0),
            maxColumns: Metrics.maxColumns,
            spacing: Metrics.spacing,
        )
    }
}

// MARK: - Metrics

private enum Metrics {
    static let spacing: CGFloat = 8
    static let minTileWidth: CGFloat = Constants.Layout.tabItemHeight * 1.5
    static let tileHeight: CGFloat = Constants.Layout.tabItemHeight * 1.5
    static let maxColumns: Int = 4
    static let draggedOpacity: Double = 0.4
    static let targetCornerRadius: CGFloat = 16
    static let targetLineWidth: CGFloat = 2
    static let dragPreviewSize: CGFloat = 32
}
