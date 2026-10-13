import SwiftUI

/// Live favorite destinations using the compact sidebar's favicon artwork and cell sizing.
struct ControlIslandFavoriteTabs: View {
    let favorites: [FavoriteItem]
    var focusedControl: FocusState<String?>.Binding

    @Environment(WindowState.self) private var windowState
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(TabSwitcherManager.self) private var tabSwitcher
    @Environment(BookmarksManager.self) private var bookmarks
    @State private var draggedID: UUID?
    @State private var dragSessionID: DragSession.ID?
    @State private var dropPoint: CGPoint?
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollPosition = SwiftUI.ScrollPosition(idType: UUID.self)
    @State private var autoScrollTask: Task<Void, Never>?
    @Environment(\.appearsActive) private var appearsActive

    private enum Layout {
        static let maximumVisible = 4
        static let edgeZone: CGFloat = 22
        static let scrollStep: CGFloat = 8
        static let insertionHeight: CGFloat = 2
        static let insertionWidth: CGFloat = 28
    }

    static func height(for count: Int) -> CGFloat {
        CGFloat(min(count, Layout.maximumVisible)) * CompactTabButton.Layout.buttonHeight
    }

    var body: some View {
        let selectedID = windowState.activeTabID
        return ScrollView(.vertical) {
            VStack(spacing: 0) {
                ForEach(favorites) { favorite in
                    if let tab = favorite.tab {
                        favoriteButton(favorite, tab: tab, selected: tab.id == selectedID)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollPosition($scrollPosition)
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.automatic)
        .frame(height: Self.height(for: favorites.count))
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            scrollOffset = offset
        }
        .overlay(alignment: .top) { insertionIndicator }
        .onDrop(of: [ControlIslandFavoriteDrag.contentType], delegate: ControlIslandFavoriteDropDelegate(
            isActive: draggedID != nil,
            onUpdate: updateDrop,
            onExit: clearDrop,
            onDrop: commitDrop,
        ))
        .onAppear(perform: revealSelection)
        .onChange(of: windowState.activeTabID) { revealSelection() }
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

    private func revealSelection() {
        guard draggedID == nil,
              let favorite = favorites.first(where: { $0.tab?.id == windowState.activeTabID }) else { return }
        scrollPosition.scrollTo(id: favorite.id)
    }

    private var insertionIndex: Int? {
        guard draggedID != nil, let dropPoint else { return nil }
        let rowHeight = CompactTabButton.Layout.buttonHeight
        return min(favorites.count, max(0, Int((dropPoint.y + scrollOffset + rowHeight / 2) / rowHeight)))
    }

    @ViewBuilder
    private var insertionIndicator: some View {
        if let index = insertionIndex {
            Capsule()
                .fill(.primary)
                .frame(width: Layout.insertionWidth, height: Layout.insertionHeight)
                .offset(y: min(
                    Self.height(for: favorites.count) - Layout.insertionHeight,
                    max(0, CGFloat(index) * CompactTabButton.Layout.buttonHeight - scrollOffset),
                ))
                .allowsHitTesting(false)
        }
    }

    private func updateDrop(_ point: CGPoint) {
        dropPoint = point
        guard autoScrollTask == nil else { return }
        autoScrollTask = Task(name: "Scroll favorite reorder destination") {
            while !Task.isCancelled, draggedID != nil, let point = dropPoint {
                let height = Self.height(for: favorites.count)
                let direction: CGFloat = point.y < Layout.edgeZone ? -1 : (point.y > height - Layout.edgeZone ? 1 : 0)
                let maximum = max(0, CGFloat(favorites.count) * CompactTabButton.Layout.buttonHeight - height)
                if direction != 0 {
                    scrollPosition.scrollTo(y: min(maximum, max(0, scrollOffset + direction * Layout.scrollStep)))
                }
                try? await Task.sleep(for: .milliseconds(40))
            }
        }
    }

    private func clearDrop() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
        dropPoint = nil
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
        clearDrop()
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
        scrollPosition.scrollTo(id: id)
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
            FaviconView(data: favorite.largeFaviconData, url: favorite.url, size: CompactTabButton.Layout.faviconSize)
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
