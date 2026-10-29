import CoreGraphics
import Foundation
import SwiftUI

/// The browser's beams, one style per purpose, so every effect shares its widths,
/// intensity, and timing with the others. Every beam is drawn in the browser's accent
/// color (``color``), the one set in Settings or the Control Island's Customize sheet.
///
/// A ``guide`` points from a control to what it opened: the rail's lens button to the open
/// lens, and every beam of the tour. A ``trail`` is the short run from the page icon to its
/// card, at half the brightness and a quicker travel. A ``displaced`` ray leaves the
/// control that displaced a page for the page's new place.
nonisolated enum LightStyle: CaseIterable, Sendable {
    case guide
    case trail
    case displaced

    enum Layout {
        static let coreWidth: CGFloat = LightPath.Layout.coreWidth
        static let glowWidth: CGFloat = LightPath.Layout.glowWidth
        static let guideIntensity: Double = 1
        static let trailIntensity: Double = 0.5
        static let displacedIntensity: Double = 1
        static let trailTravel: Duration = .milliseconds(350)
    }

    /// Full width of the beam's bright center, in points.
    var coreWidth: CGFloat {
        Layout.coreWidth
    }

    /// Full width of the beam's soft halo, in points.
    var glowWidth: CGFloat {
        Layout.glowWidth
    }

    /// Brightness of the beam, 0 to 1.
    var intensity: Double {
        switch self {
        case .guide: Layout.guideIntensity
        case .trail: Layout.trailIntensity
        case .displaced: Layout.displacedIntensity
        }
    }

    /// How the beam travels, holds, and fades.
    var timing: LightTravel.Timing {
        switch self {
        case .guide, .displaced: .default
        case .trail: LightTravel.Timing(travel: Layout.trailTravel)
        }
    }

    /// Every beam's color: the browser's accent.
    @MainActor
    static var color: Color.Components {
        Color.Components(color: .appAccentColor)
    }

    /// A path along `points` in this style.
    func path(_ points: [CGPoint], color: Color.Components) -> LightPath {
        LightPath(points: points, color: color, coreWidth: coreWidth, glowWidth: glowWidth, intensity: intensity)
    }

    /// The ray's three points, start, bend, and end, as one path in this style.
    func path(ray: FloatingRayPath, color: Color.Components) -> LightPath {
        path([ray.start, ray.bend, ray.end], color: color)
    }
}
