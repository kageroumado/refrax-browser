import AppKit
import SwiftUI

/// The browser destinations behind More, in their sections.
nonisolated enum ControlIslandMoreItem: CaseIterable, Identifiable {
    case favorites
    case history
    case downloads
    case bookmarks
    case settings
    case customizeControls

    var id: Self {
        self
    }

    /// Destinations, then Settings, then the one visible seat for the rail's own setup.
    static let sections: [[ControlIslandMoreItem]] = [
        [.favorites, .history, .downloads, .bookmarks],
        [.settings],
        [.customizeControls],
    ]

    var title: String {
        switch self {
        case .favorites: "Favorites…"
        case .history: "History"
        case .downloads: "Downloads"
        case .bookmarks: "Bookmarks"
        case .settings: "Settings…"
        case .customizeControls: "Customize Controls…"
        }
    }

    var symbol: String {
        switch self {
        case .favorites: "star"
        case .history: "clock"
        case .downloads: "arrow.down.circle"
        case .bookmarks: "bookmark"
        case .settings: "gearshape"
        case .customizeControls: "slider.horizontal.3"
        }
    }
}

/// More: the rail's last row, a menu of browser destinations.
struct ControlIslandMenu: View {
    @Binding var showsFavorites: Bool

    @Environment(WindowState.self) private var windowState
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.controlIslandIsResting) private var isResting

    var body: some View {
        Menu {
            ForEach(ControlIslandMoreItem.sections.indices, id: \.self) { section in
                if section > 0 {
                    Divider()
                }
                ForEach(ControlIslandMoreItem.sections[section]) { item in
                    Button(item.title, systemImage: item.symbol) { perform(item) }
                }
            }
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
        .foregroundStyle(appearsActive && !isResting ? Color.primary : Color.secondary)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .help("Favorites and browser tools")
        .accessibilityLabel("More browser controls")
    }

    private func perform(_ item: ControlIslandMoreItem) {
        switch item {
        case .favorites: showsFavorites = true
        case .history: windowState.showDetailTray(.history)
        case .downloads: windowState.showDetailTray(.downloads)
        case .bookmarks: windowState.showDetailTray(.bookmarks)
        case .settings: NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .customizeControls: windowState.controlIsland.showsCustomization = true
        }
    }
}
