import SwiftUI

/// Draws every ``LightPath`` it is given in one Metal pass and is transparent elsewhere.
///
/// Place it so that its top-left corner is the origin the paths were measured from; a
/// layer that fills the window draws paths in window coordinates. The output carries
/// premultiplied alpha, so it composites over page content and glass like light would.
/// The layer takes no clicks. ``LightPacking/maximumSegments`` caps how many segments
/// one layer draws.
struct LightLayer: View {
    let paths: [LightPath]

    var body: some View {
        Group {
            if paths.isEmpty {
                Color.clear
            } else {
                // The base is opaque so the effect visits every pixel of the layer; the
                // shader writes each output pixel itself, transparent where no light falls.
                Rectangle()
                    .fill(.black)
                    .colorEffect(ShaderLibrary.lightPaths(.floatArray(LightPacking.pack(paths))))
            }
        }
        .allowsHitTesting(false)
    }
}
