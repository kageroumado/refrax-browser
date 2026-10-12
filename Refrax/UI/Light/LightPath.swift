import CoreGraphics
import Foundation
import SwiftUI

/// A beam of light along a polyline, drawn by ``LightLayer``.
///
/// Points are in the coordinate space of the layer that draws the path, with a top-left
/// origin: a layer that fills the window takes window coordinates. The beam has a bright
/// core and a soft halo, and it is lit from its first point along `progress` of its
/// length, with a soft spot at the lit tip. After its last bend the beam can disperse into
/// three bands whose hues sit at −``Layout/hueOffset``, 0°, and +``Layout/hueOffset`` from
/// `color`, fanning out by up to ``Layout/fanAngle`` at full `dispersion`.
nonisolated struct LightPath: Equatable, Sendable {
    /// The vertices, two or more. Consecutive equal points make a zero-length segment,
    /// which draws as a spot.
    var points: [CGPoint]
    /// The color of the halo and of the center band; the core is white.
    var color: Color.Components
    /// Full width of the bright center, in points.
    var coreWidth: CGFloat
    /// Full width of the soft halo, in points; the halo reaches 2% of its peak at its edge.
    var glowWidth: CGFloat
    /// Brightness of the whole beam, 0 to 1.
    var intensity: Double
    /// How much of the path is lit from the start, 0 to 1.
    var progress: Double
    /// How far the beam splits into three bands after its last bend, 0 to 1.
    var dispersion: Double
    /// Scale of the spot at the lit tip, 1 at rest; a pulse goes above 1.
    var spotScale: CGFloat

    enum Layout {
        static let coreWidth: CGFloat = 2
        static let glowWidth: CGFloat = 24
        /// Hue distance of the two outer dispersion bands from the beam's color, in degrees.
        static let hueOffset: Double = 34
        /// Angle between the center band and each outer band at full dispersion, in degrees.
        static let fanAngle: Double = 6
    }

    init(
        points: [CGPoint],
        color: Color.Components,
        coreWidth: CGFloat = Layout.coreWidth,
        glowWidth: CGFloat = Layout.glowWidth,
        intensity: Double = 1,
        progress: Double = 1,
        dispersion: Double = 0,
        spotScale: CGFloat = 1,
    ) {
        precondition(points.count >= 2, "A LightPath needs at least two points")
        self.points = points
        self.color = color
        self.coreWidth = coreWidth
        self.glowWidth = glowWidth
        self.intensity = intensity
        self.progress = progress
        self.dispersion = dispersion
        self.spotScale = spotScale
    }

    /// The ray's three points, start, bend, and end, as one path.
    init(ray: FloatingRayPath, color: Color.Components) {
        self.init(points: [ray.start, ray.bend, ray.end], color: color)
    }

    /// The length of each segment, in order.
    var segmentLengths: [CGFloat] {
        zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
    }

    /// The length of the whole polyline.
    var length: CGFloat {
        segmentLengths.reduce(0, +)
    }

    /// The point `fraction` of the way along the polyline, by length; clamped to the ends.
    func point(at fraction: CGFloat) -> CGPoint {
        var remaining = min(max(fraction, 0), 1) * length
        let lengths = segmentLengths
        for (index, segmentLength) in lengths.enumerated() {
            let a = points[index]
            let b = points[index + 1]
            if remaining <= segmentLength || index == lengths.count - 1 {
                guard segmentLength > 0 else { return b }
                let t = min(remaining / segmentLength, 1)
                return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            remaining -= segmentLength
        }
        return points[points.count - 1]
    }

    /// The colors of the two outer dispersion bands: the hue turned down, then up.
    var bandColors: (low: Color.Components, high: Color.Components) {
        (color.rotatingHue(by: -Layout.hueOffset), color.rotatingHue(by: Layout.hueOffset))
    }

    /// The path lit as `frame` describes, with the frame's intensity and spot scale
    /// applied over the path's own.
    func applying(_ frame: LightTravel.Frame) -> LightPath {
        var lit = self
        lit.progress = frame.progress
        lit.intensity *= frame.intensity
        lit.spotScale *= frame.spotScale
        return lit
    }
}
