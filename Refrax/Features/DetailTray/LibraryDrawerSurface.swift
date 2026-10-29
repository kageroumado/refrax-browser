import SwiftUI

/// The drawer uses the same observed tint, glass, and corners as the floating controls.
struct LibraryDrawerSurface: View {
    @Environment(WindowState.self) private var windowState

    var body: some View {
        GlassEffectContainer {
            DetailTrayContent()
                .windowGlassSurface(tint: windowState.controlIslandTint)
        }
        .padding(Constants.DetailTray.glassEffectPadding)
        .windowContainerShape()
    }
}
