import SwiftUI

/// The rail's own settings, on a right-click of its empty glass.
nonisolated enum ControlIslandRailMenuItem: CaseIterable {
    case customizeControls
    case resetPosition
    case optionDragTarget

    var title: String {
        switch self {
        case .customizeControls: "Customize Controls…"
        case .resetPosition: "Reset Control Position"
        case .optionDragTarget: "Option-drag moves"
        }
    }
}

/// Customize, reset the position, and choose what Option-drag moves: right-click the thing to set up the thing.
struct ControlIslandRailMenu: View {
    @Environment(WindowState.self) private var windowState

    private var configuration: ControlIslandConfiguration {
        windowState.controlIsland.configuration
    }

    var body: some View {
        Button(ControlIslandRailMenuItem.customizeControls.title, systemImage: "slider.horizontal.3") {
            windowState.controlIsland.showsCustomization = true
        }
        Button(ControlIslandRailMenuItem.resetPosition.title) { windowState.controlIsland.resetPlacement() }
        Picker(ControlIslandRailMenuItem.optionDragTarget.title, selection: optionDragTarget) {
            ForEach(ControlIslandDragTarget.allCases, id: \.self) { target in
                Text(target.title).tag(target)
            }
        }
    }

    /// Writes the chosen target through the shared configuration, keeping every other preference.
    private var optionDragTarget: Binding<ControlIslandDragTarget> {
        Binding {
            configuration.optionDragTarget
        } set: { target in
            configuration.apply(
                configuration.items,
                optionDragTarget: target,
                avoidsPageControls: configuration.avoidsPageControls,
                restsWhenIdle: configuration.restsWhenIdle,
                tintsWithSpaceColor: configuration.tintsWithSpaceColor,
            )
        }
    }
}
