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
                } else if canvas.showsControlIsland {
                    ControlIsland(area: CGRect(origin: .zero, size: geometry.size))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .transition(.opacity)
                }
            }
        }
        // Gone at once when the page becomes a slab; back with a fade once it is live again.
        .animation(canvas.showsControlIsland ? .easeOut(duration: Layout.returnDuration) : nil, value: canvas.showsControlIsland)
        .coordinateSpace(name: "browserControls")
        .windowContainerShape()
        .ignoresSafeArea()
        .environment(\.colorScheme, settings.theme.colorScheme ?? colorScheme)
    }

    private enum Layout {
        static let returnDuration: TimeInterval = 0.2
    }
}
