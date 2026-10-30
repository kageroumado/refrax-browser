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
/// Tiles are dragged to reorder: the held tile floats under the pointer, the others slide
/// aside to open its slot, and letting go writes the same shared order the control rail
/// shows. The drag is the grid's own gesture, not a system drag, so it stays inside the
/// drawer's view and needs no drop target.
struct FavoritesGrid: View {
    var showsTitles = false
    @Environment(BookmarksManager.self) private var bookmarksManager
    /// The drag in progress, with the order the grid shows while a tile is held.
    @State private var reorder: FavoritesGridReorder?
    /// Each tile's frame in the grid's space, kept current for the next drag's slots.
    @State private var tileFrames: [UUID: CGRect] = [:]
    /// Until when a tile's button ignores its click: a drag's mouse-up is not an open.
    @State private var tapsSuppressedUntil: Date = .distantPast

    private static let coordinateSpace = "FavoritesGrid"

    var body: some View {
        AdaptiveFavoritesGridLayout(configuration: gridConfiguration) {
            ForEach(shownFavorites) { item in
                tile(item)
            }
        }
        .coordinateSpace(name: Self.coordinateSpace)
        .overlay(alignment: .topLeading) { floatingTile }
        .environment(\.favoriteTapsSuppressedUntil, tapsSuppressedUntil)
        .onChange(of: bookmarksManager.favorites.map(\.id)) { _, ids in
            // The order a landing just wrote is the one the grid shows; any other change ends the drag.
            if reorder?.order != ids {
                reorder = nil
            }
        }
        .onDisappear {
            reorder = nil
            tapsSuppressedUntil = .distantPast
        }
        .accessibilityIdentifier("FavoritesGrid")
    }

    /// The favorites in the order the grid shows: the live order while a tile is held.
    private var shownFavorites: [FavoriteItem] {
        let favorites = bookmarksManager.favorites
        guard let reorder else { return favorites }
        let byID = Dictionary(favorites.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return reorder.order.compactMap { byID[$0] }
    }

    private func tile(_ item: FavoriteItem) -> some View {
        FavoriteTileView(item: item, shouldShowTitle: showsTitles)
            .opacity(reorder?.draggedID == item.id ? 0 : 1)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(Self.coordinateSpace))
            } action: { frame in
                tileFrames[item.id] = frame
            }
            .highPriorityGesture(reorderGesture(for: item.id))
            .accessibilityAction(named: "Move earlier") { move(item.id, by: -1) }
            .accessibilityAction(named: "Move later") { move(item.id, by: 1) }
    }

    /// The held tile, drawn over the grid under the pointer. Its own moves follow the pointer
    /// with no animation; only the settle into its slot animates.
    @ViewBuilder
    private var floatingTile: some View {
        if let reorder, let item = bookmarksManager.favorites.first(where: { $0.id == reorder.draggedID }) {
            FavoriteTileView(item: item, shouldShowTitle: showsTitles)
                .frame(width: reorder.floatingSize.width, height: reorder.floatingSize.height)
                .scaleEffect(reorder.isSettling ? 1 : Metrics.liftScale)
                .shadow(
                    color: .black.opacity(reorder.isSettling ? 0 : Metrics.liftShadowOpacity),
                    radius: Metrics.liftShadowRadius,
                    y: Metrics.liftShadowOffset,
                )
                .offset(x: reorder.floatingOrigin.x, y: reorder.floatingOrigin.y)
                .transaction { transaction in
                    if !reorder.isSettling {
                        transaction.animation = nil
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Reordering

    /// A short pull past `Metrics.dragThreshold` starts a drag; a plain click still reaches the
    /// tile's button, because the drag gesture only claims the pointer once it has moved.
    private func reorderGesture(for id: UUID) -> some Gesture {
        DragGesture(minimumDistance: Metrics.dragThreshold, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                if reorder == nil {
                    reorder = FavoritesGridReorder(
                        order: bookmarksManager.favorites.map(\.id),
                        frames: tileFrames,
                        draggedID: id,
                        start: value.startLocation,
                    )
                }
                guard var drag = reorder, drag.draggedID == id, !drag.isSettling else { return }
                tapsSuppressedUntil = Date().addingTimeInterval(Metrics.tapSuppressionWhileDragging)
                if drag.move(to: value.location) {
                    withAnimation(Metrics.slide) { reorder = drag }
                } else {
                    reorder = drag
                }
            }
            .onEnded { value in
                guard var drag = reorder, drag.draggedID == id, !drag.isSettling else { return }
                drag.move(to: value.location)
                finish(drag)
            }
    }

    /// Writes the order the tile landed in, settles the tile into its slot, and keeps the
    /// mouse-up from counting as a click on a tile.
    private func finish(_ drag: FavoritesGridReorder) {
        var settled = drag
        settled.settle()
        tapsSuppressedUntil = Date().addingTimeInterval(Metrics.tapSuppression)
        withAnimation(Metrics.settle) {
            reorder = settled
            if settled.changesOrder {
                bookmarksManager.moveFavorite(settled.draggedID, before: settled.insertionNextID)
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: Metrics.settleDuration)
            guard reorder == settled else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { reorder = nil }
        }
    }

    private func move(_ id: UUID, by offset: Int) {
        let ids = bookmarksManager.favorites.map(\.id)
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        let nextIndex = offset < 0 ? index - 1 : index + 2
        bookmarksManager.moveFavorite(id, before: ids.indices.contains(nextIndex) ? ids[nextIndex] : nil)
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
    /// How far the pointer travels before a press on a tile becomes a drag.
    static let dragThreshold: CGFloat = 4
    static let liftScale: CGFloat = 1.05
    static let liftShadowOpacity: Double = 0.28
    static let liftShadowRadius: CGFloat = 12
    static let liftShadowOffset: CGFloat = 6
    /// The other tiles sliding into their new slots.
    static let slide: Animation = .spring(duration: 0.3, bounce: 0.12)
    /// The held tile settling into its slot when let go.
    static let settle: Animation = .spring(duration: 0.22, bounce: 0)
    static let settleDuration: Duration = .milliseconds(220)
    /// How long after a drag's mouse-up a tile's button still ignores a click.
    static let tapSuppression: TimeInterval = 0.4
    /// Pushed ahead on every pointer move while a tile is held, so a drag that ends without a
    /// mouse-up (focus lost) frees the tiles again on its own.
    static let tapSuppressionWhileDragging: TimeInterval = 1
}

// MARK: - Taps during a drag

private struct FavoriteTapsSuppressedUntilKey: EnvironmentKey {
    static let defaultValue: Date = .distantPast
}

extension EnvironmentValues {
    /// Until when a favorite tile's click is ignored, because a drag is in progress or just ended.
    var favoriteTapsSuppressedUntil: Date {
        get { self[FavoriteTapsSuppressedUntilKey.self] }
        set { self[FavoriteTapsSuppressedUntilKey.self] = newValue }
    }
}
