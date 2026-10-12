import SwiftUI

struct ControlIslandAppearanceMenu: View {
    @Environment(WindowState.self) private var windowState

    var body: some View {
        @Bindable var state = windowState.controlIsland
        Button("Customize Controls…", systemImage: "slider.horizontal.3") { state.showsCustomization = true }
        Button("Reset control position") { state.resetPlacement() }
    }
}
