import AppKit
import SwiftUI

struct ControlIslandMenu: View {
    @Binding var showsFavorites: Bool

    @Environment(WindowState.self) private var windowState
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        Menu {
            Button("Current Tab…", systemImage: "doc.text.magnifyingglass") {
                windowState.controlIsland.tabInfo.show()
            }
            Divider()
            Button("Unplaced Tabs (\(canvas.unplacedFloatingTabs.count))", systemImage: "tray") { canvas.recentIsOpen.toggle() }
            Button("Favorites…", systemImage: "star") { showsFavorites = true }
            Divider()
            Button("History", systemImage: "clock") { windowState.showDetailTray(.history) }
            Button("Downloads", systemImage: "arrow.down.circle") { windowState.showDetailTray(.downloads) }
            Button("Bookmarks", systemImage: "bookmark") { windowState.showDetailTray(.bookmarks) }
            Button("Settings…", systemImage: "gearshape") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Divider()
            ControlIslandAppearanceMenu()
        } label: {
            ControlIslandRow {
                Image(systemName: "ellipsis")
            }
            .frame(width: ControlIslandPlacement.contentWidth)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("More browser controls")
        }
        .menuStyle(.button)
        .buttonStyle(ControlIslandButtonStyle())
        .menuIndicator(.hidden)
        .foregroundStyle(appearsActive ? Color.primary : Color.secondary)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .help("Favorites and browser tools")
        .accessibilityLabel("More browser controls")
    }
}
