import SwiftUI

/// The favorites column: the favorites that fit, as site icons in every space, then a "more"
/// chevron when the grid holds more than the column shows. The chevron opens the grid.
struct ControlIslandFavoriteTabs: View {
    /// Favorites with a tab, in favorites order.
    let favorites: [FavoriteItem]
    /// Whether the grid holds favorites without a tab, which the column leaves out.
    let overflows: Bool
    let onShowAll: () -> Void
    var focusedControl: FocusState<String?>.Binding

    @Environment(WindowState.self) private var windowState
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(TabSwitcherManager.self) private var tabSwitcher
    @Environment(BookmarksManager.self) private var bookmarks
    @State private var draggedID: UUID?
    @State private var dragSessionID: DragSession.ID?
    @State private var dropPoint: CGPoint?
    @Environment(\.appearsActive) private var appearsActive

    private enum Layout {
        static let maximumVisible = 4
        static let moreHeight: CGFloat = 20
        static let moreSymbolSize: CGFloat = 9
        static let insertionHeight: CGFloat = 2
        static let insertionWidth: CGFloat = 28
    }

    /// The column's height for `count` favorites with tabs, with the chevron when the grid holds more.
    static func height(for count: Int, overflows: Bool = false) -> CGFloat {
        CGFloat(min(count, Layout.maximumVisible)) * ControlIslandFavoriteIcon.Layout.rowHeight
            + (overflows || count > Layout.maximumVisible ? Layout.moreHeight : 0)
    }

    private var visible: ArraySlice<FavoriteItem> {
        favorites.prefix(Layout.maximumVisible)
    }

    private var showsMore: Bool {
        overflows || favorites.count > Layout.maximumVisible
    }

    var body: some View {
        let selectedID = windowState.activeTabID
        return VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(visible) { favorite in
                    if let tab = favorite.tab {
                        favoriteButton(favorite, tab: tab, selected: tab.id == selectedID)
                    }
                }
            }
            .overlay(alignment: .top) { insertionIndicator }
            .onDrop(of: [ControlIslandFavoriteDrag.contentType], delegate: ControlIslandFavoriteDropDelegate(
                isActive: draggedID != nil,
                onUpdate: { dropPoint = $0 },
                onExit: { dropPoint = nil },
                onDrop: commitDrop,
            ))
            if showsMore {
                moreButton
            }
        }
        .frame(height: Self.height(for: favorites.count, overflows: overflows))
        .onChange(of: favorites.map(\.id)) { finishDrag() }
        .onChange(of: windowState.controlIsland.dismissalRequest) { finishDrag() }
        .onChange(of: appearsActive) {
            _, active in if !active {
                finishDrag()
            }
        }
        .onDisappear(perform: finishDrag)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Favorite tabs")
    }

    private var moreButton: some View {
        Button(action: onShowAll) {
            Image(systemName: "chevron.down")
                .font(.system(size: Layout.moreSymbolSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: Layout.moreHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused(focusedControl, equals: "All Favorites")
        .focusEffectDisabled()
        .help("All Favorites")
        .accessibilityLabel("All Favorites")
    }

    private var insertionIndex: Int? {
        guard draggedID != nil, let dropPoint else { return nil }
        let rowHeight = ControlIslandFavoriteIcon.Layout.rowHeight
        return min(visible.count, max(0, Int((dropPoint.y + rowHeight / 2) / rowHeight)))
    }

    @ViewBuilder
    private var insertionIndicator: some View {
        if let index = insertionIndex {
            Capsule()
                .fill(.primary)
                .frame(width: Layout.insertionWidth, height: Layout.insertionHeight)
                .offset(y: min(
                    CGFloat(visible.count) * ControlIslandFavoriteIcon.Layout.rowHeight - Layout.insertionHeight,
                    max(0, CGFloat(index) * ControlIslandFavoriteIcon.Layout.rowHeight),
                ))
                .allowsHitTesting(false)
        }
    }

    private func commitDrop(_ point: CGPoint) -> Bool {
        dropPoint = point
        guard let id = draggedID, let index = insertionIndex,
              favorites.contains(where: { $0.id == id }) else { finishDrag(); return false }
        let nextID = favorites.indices.contains(index) ? favorites[index].id : nil
        bookmarks.moveLiveFavorite(id, before: nextID)
        finishDrag()
        return true
    }

    private func finishDrag() {
        dropPoint = nil
        draggedID = nil
        dragSessionID = nil
        windowState.controlIsland.isReorderingFavorites = false
    }

    private func trackDrag(_ session: DragSession, favoriteID: UUID) {
        switch session.phase {
        case .initial, .active:
            guard dragSessionID == nil || dragSessionID == session.id else { return }
            dragSessionID = session.id
            draggedID = favoriteID
            windowState.controlIsland.isReorderingFavorites = true
        case .ended, .dataTransferCompleted:
            if dragSessionID == session.id {
                finishDrag()
            }
        @unknown default:
            finishDrag()
        }
    }

    private func moveFavorite(_ id: UUID, by offset: Int) {
        guard let index = favorites.firstIndex(where: { $0.id == id }),
              favorites.indices.contains(index + offset) else { return }
        let nextIndex = offset < 0 ? index - 1 : index + 2
        bookmarks.moveLiveFavorite(id, before: favorites.indices.contains(nextIndex) ? favorites[nextIndex].id : nil)
    }

    private func favoriteButton(_ favorite: FavoriteItem, tab: Tab, selected: Bool) -> some View {
        Button {
            guard draggedID == nil else { return }
            tabSwitcher.cancel()
            windowState.closeCommandLens()
            canvas.openFloatingTab(tab)
            if let bookmark = favorite.bookmark {
                bookmarks.recordVisit(for: bookmark)
            }
        } label: {
            ControlIslandFavoriteIcon(favorite: favorite, tab: tab, isSelected: selected)
        }
        .draggable(ControlIslandFavoriteDrag(id: favorite.id)) {
            FaviconView(data: favorite.largeFaviconData, url: favorite.url, size: ControlIslandFavoriteIcon.Layout.faviconSize)
                .faviconBackground()
        }
        .dragConfiguration(DragConfiguration(
            operationsWithinApp: .init(allowCopy: false, allowMove: true),
            operationsOutsideApp: .init(allowCopy: false),
        ))
        .onDragSessionUpdated { trackDrag($0, favoriteID: favorite.id) }
        .contextMenu { favoriteMenu(favorite) }
        .accessibilityAction(named: "Move up") { moveFavorite(favorite.id, by: -1) }
        .accessibilityAction(named: "Move down") { moveFavorite(favorite.id, by: 1) }
        .help("\(favorite.displayName) · Drag to reorder")
        .accessibilityLabel(favorite.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .focusable()
        .focused(focusedControl, equals: favorite.id.uuidString)
        .focusEffectDisabled()
    }

    @ViewBuilder
    private func favoriteMenu(_ favorite: FavoriteItem) -> some View {
        let isFirst = favorites.first?.id == favorite.id
        let isLast = favorites.last?.id == favorite.id
        Button("Move Up", action: { moveFavorite(favorite.id, by: -1) })
            .disabled(isFirst)
        Button("Move Down", action: { moveFavorite(favorite.id, by: 1) })
            .disabled(isLast)
    }
}
