import SwiftUI

/// A ray of light from the control that displaced a page to the page's new place in
/// the floating layer: it travels along its length, bends once as it enters the tab's
/// glass, lands as a bright spot that pulses once, and fades. With Reduce Motion the
/// whole ray shows at once and fades.
struct FloatingRayView: View {
    let path: FloatingRayPath
    let onFinish: () -> Void

    var body: some View {
        LightTravel(paths: [LightPath(ray: path, color: Color.Components(color: .appAccentColor))], onFinish: onFinish)
            .accessibilityHidden(true)
    }
}
