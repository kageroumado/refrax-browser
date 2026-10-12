import SwiftUI

/// The control rail shares window coordinates with the page and stays above transient overlays.
struct ControlIslandLayer: View {
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(BrowserSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            if canvas.showsFloatingControls {
                if let selection = canvas.regionSelection {
                    FloatingRegionSelector(selection: selection)
                } else {
                    ControlIsland(area: CGRect(origin: .zero, size: geometry.size))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .coordinateSpace(name: "browserControls")
        .ignoresSafeArea()
        .environment(\.colorScheme, settings.theme.colorScheme ?? colorScheme)
    }
}
