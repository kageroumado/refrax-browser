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
                        // Gone the frame the page is captured, so the capture shows the page
                        // alone; back with a fade once the page is live again.
                        .transition(.asymmetric(insertion: .opacity, removal: .identity))
                }
            }
        }
        .animation(.easeOut(duration: Layout.returnDuration), value: canvas.showsControlIsland)
        .coordinateSpace(name: "browserControls")
        .ignoresSafeArea()
        .environment(\.colorScheme, settings.theme.colorScheme ?? colorScheme)
    }

    private enum Layout {
        static let returnDuration: TimeInterval = 0.2
    }
}
