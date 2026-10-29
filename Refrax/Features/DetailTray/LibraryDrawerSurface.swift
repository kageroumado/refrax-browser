import SwiftUI

/// The drawer uses the same observed tint and glass as the floating controls, and floats like
/// them: inset evenly from every window edge, with all four
/// corners rounded. Its content is clipped to that shape, so no bar draws a square corner.
struct LibraryDrawerSurface: View {
    @Environment(WindowState.self) private var windowState

    private static let shape = RoundedRectangle(cornerRadius: WindowCorner.radius, style: .continuous)

    var body: some View {
        GlassEffectContainer {
            DetailTrayContent()
                .clipShape(Self.shape)
                .containerShape(Self.shape)
                .background(windowState.controlIslandTint, in: Self.shape)
                .glassEffect(.regular, in: Self.shape)
        }
        .padding(Constants.DetailTray.glassEffectPadding)
    }
}
