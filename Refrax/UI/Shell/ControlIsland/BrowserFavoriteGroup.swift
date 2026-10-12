import SwiftUI

/// Favorite identities have their own remembered place beside the current work.
struct BrowserFavoriteGroup: View {
    let area: CGRect
    @Environment(WindowState.self) private var windowState
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(BookmarksManager.self) private var bookmarks
    @Environment(TabManager.self) private var tabs
    @FocusState private var focusedControl: String?
    @State private var dragOrigin: CGPoint?
    @AppStorage("browserMarks.favorites") private var keepsFavorites = false
    private var x: Double { windowState.controlIsland.favoritePlacement.x }
    private var y: Double { windowState.controlIsland.favoritePlacement.y }

    private var favorites: [FavoriteItem] { bookmarks.favorites.filter { $0.tab != nil } }
    private var visible: Bool { keepsFavorites || canvas.floatingVisibility.isRevealed }
    private var frame: CGRect {
        let height = max(48, ControlIslandFavoriteTabs.height(for: favorites.count) + 8)
        return CGRect(x: 12 + min(1, max(0, x)) * max(0, area.width - 72),
                      y: 48 + min(1, max(0, y)) * max(0, area.height - height - 60), width: 48, height: height)
    }

    var body: some View {
        Group {
            if visible {
                Group {
                    if favorites.isEmpty {
                        Button {
                            if let tab = windowState.focusedPage?.tab ?? windowState.activeTab {
                                ControlIslandTabActions(tab: tab, windowState: windowState, tabs: tabs, bookmarks: bookmarks).toggleFavorite()
                            }
                        } label: { Image(systemName: "star.badge.plus").frame(width: 40, height: 40).contentShape(Rectangle()) }
                            .disabled(windowState.activeTab == nil)
                            .help("Favorite this page").accessibilityLabel("Favorite this page")
                    } else {
                        ControlIslandFavoriteTabs(favorites: favorites, focusedControl: $focusedControl).frame(width: 40)
                    }
                }
                .padding(4).frame(width: frame.width, height: frame.height)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .overlay {
                    ControlIslandOptionDrag(target: .panel, onFeedback: { _ in }, onBegin: { dragOrigin = frame.origin }, onMove: { delta in
                        guard let origin = dragOrigin else { return }
                        windowState.controlIsland.favoritePlacement.x = min(1, max(0, (origin.x + delta.width - 12) / max(1, area.width - 72)))
                        windowState.controlIsland.favoritePlacement.y = min(1, max(0, (origin.y + delta.height - 48) / max(1, area.height - frame.height - 60)))
                    }, onEnd: {
                        dragOrigin = nil
                        windowState.window?.invalidateRestorableState()
                    })
                }
                .offset(x: frame.minX, y: frame.minY)
                .buttonStyle(.plain)
                .accessibilityLabel("Favorites")
            }
        }
        .onAppear(perform: updateHitRegions)
        .onChange(of: frame) { updateHitRegions() }
        .onChange(of: visible) { updateHitRegions() }
        .onDisappear { windowState.controlIsland.favoriteHitRegions = [] }
    }

    private func updateHitRegions() { windowState.controlIsland.favoriteHitRegions = visible ? [frame] : [] }
}
