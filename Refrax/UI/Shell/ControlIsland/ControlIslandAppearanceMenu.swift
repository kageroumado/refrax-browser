import SwiftUI

struct ControlIslandAppearanceMenu: View {
    @Environment(WindowState.self) private var windowState

    var body: some View {
        @Bindable var state = windowState.controlIsland
        Button("Customize Controls…", systemImage: "slider.horizontal.3") { state.showsCustomization = true }
        Picker("Control appearance", selection: $state.mode) {
            ForEach(ControlIslandState.Mode.allCases, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        if state.isLatched {
            Button("Dismiss controls") {
                state.dismiss()
            }
        }
        Button("Reset control position") { state.resetPlacement() }
    }
}
