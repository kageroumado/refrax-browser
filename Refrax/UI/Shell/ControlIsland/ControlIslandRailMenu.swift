import SwiftUI

/// The rail's own menu, on a right-click of its empty glass, a divider, or the grip.
nonisolated enum ControlIslandRailMenuItem: CaseIterable {
    case favorites
    case customizeControls
    case resetPosition

    var title: String {
        switch self {
        case .favorites: "Favorites…"
        case .customizeControls: "Customize Controls…"
        case .resetPosition: "Reset Control Position"
        }
    }

    var symbol: String {
        switch self {
        case .favorites: "star"
        case .customizeControls: "slider.horizontal.3"
        case .resetPosition: "arrow.counterclockwise"
        }
    }
}

/// Favorites, then the rail's setup: right-click the thing to set up the thing.
struct ControlIslandRailMenu: View {
    @Binding var showsFavorites: Bool
    @Environment(WindowState.self) private var windowState

    var body: some View {
        Button(ControlIslandRailMenuItem.favorites.title, systemImage: ControlIslandRailMenuItem.favorites.symbol) {
            showsFavorites = true
        }
        Divider()
        Button(ControlIslandRailMenuItem.customizeControls.title, systemImage: ControlIslandRailMenuItem.customizeControls.symbol) {
            windowState.controlIsland.showsCustomization = true
        }
        Button(ControlIslandRailMenuItem.resetPosition.title, systemImage: ControlIslandRailMenuItem.resetPosition.symbol) {
            windowState.controlIsland.resetPlacement()
        }
    }
}
