import CoreGraphics
import Foundation
import SwiftUI

/// The geometry of the empty page's light: one entry beam from the rail's Command Lens
/// row into the lens on the page, and one band leaving the lens for each placed page,
/// ending on that page's outline.
///
/// Every frame is in window coordinates, top-left origin. The entry beam leaves the rail
/// row (or the rail, or the window's left edge at the lens's height when no rail frame
/// is known) from the edge that faces the lens and enters the lens on the edge that faces
/// the rail. Bands leave the lens from the edge facing each page and end where the line
/// toward the page's center meets its outline. Band hues spread evenly across the
/// dispersion range in angular order, so the bands read as one spectrum fanning out.
nonisolated struct PrismLayout: Equatable, Sendable {
    /// One band of dispersed light from the lens to a page outline.
    struct Band: Equatable, Sendable {
        /// The band's two points: where it leaves the lens and where it meets the outline.
        var points: [CGPoint]
        /// The band's hue, in degrees from the space color.
        var hueOffset: Double
        /// The outline the band ends on.
        var target: CGRect
    }

    /// The most pages that get a band; pages past this count keep their outline and no band.
    static let maximumBands = 12
    /// The outer bands' hue distance from the space color, in degrees.
    static let hueSpread = LightPath.Layout.hueOffset
    /// The entry beam's pulse comes around this often.
    static let pulsePeriod: TimeInterval = 5
    /// How long the pulse takes to travel the entry beam.
    static let pulseTravel: TimeInterval = 1.4
    /// The shortest and longest breathing periods of the bands, in seconds.
    static let breathPeriods: ClosedRange<TimeInterval> = 6 ... 10

    /// The entry beam's two points: the rail row's edge and the lens's edge.
    let entry: [CGPoint]
    /// One band per page, in the order the page frames were given, at most ``maximumBands``.
    let bands: [Band]
    /// The window area the geometry was laid out in.
    let bounds: CGRect

    private enum Layout {
        static let entryGlowWidth: CGFloat = 36
        static let entryGlowWidthTightened: CGFloat = 16
        static let bandGlowWidth: CGFloat = 28
        static let coreWidth: CGFloat = 1.5
        static let entryIntensity: Double = 0.55
        static let entryIntensityTightened: Double = 0.8
        static let bandIntensity: Double = 0.5
        static let pulseWidth: Double = 0.12
        static let pulseGain: Double = 1.2
        static let placeholderPlacements: [(x: Double, y: Double)] = [(0.97, 0.36), (0.99, 0.56), (0.97, 0.76)]
    }

    init(railLensFrame: CGRect, railFrame: CGRect, lensFrame: CGRect, pageFrames: [CGRect], bounds: CGRect) {
        self.bounds = bounds
        let source: CGRect? = !railLensFrame.isEmpty ? railLensFrame : (!railFrame.isEmpty ? railFrame : nil)
        let origin: CGPoint = if let source {
            Self.edgePoint(of: source, toward: Self.facingPoint(of: lensFrame, toward: CGPoint(x: source.midX, y: source.midY)))
        } else {
            CGPoint(x: bounds.minX, y: lensFrame.midY)
        }
        let entryPoint = Self.facingPoint(of: lensFrame, toward: origin)
        self.entry = [origin, entryPoint].map { Self.clamp($0, to: bounds) }

        let targets = Array(pageFrames.prefix(Self.maximumBands))
        let runs: [(exit: CGPoint, end: CGPoint, angle: Double)] = targets.map { frame in
            let exit = Self.facingPoint(of: lensFrame, toward: CGPoint(x: frame.midX, y: frame.midY))
            let end = Self.edgePoint(of: frame, toward: exit)
            return (exit, end, atan2(end.y - exit.y, end.x - exit.x))
        }
        let order = runs.indices.sorted { runs[$0].angle < runs[$1].angle }
        var offsets = [Double](repeating: 0, count: runs.count)
        for (rank, index) in order.enumerated() where runs.count > 1 {
            offsets[index] = -Self.hueSpread + 2 * Self.hueSpread * Double(rank) / Double(runs.count - 1)
        }
        self.bands = zip(runs, zip(offsets, targets)).map { run, rest in
            Band(points: [run.exit, run.end].map { Self.clamp($0, to: bounds) }, hueOffset: rest.0, target: rest.1)
        }
    }

    /// Segments the light layer needs for this geometry.
    var segmentCount: Int {
        entry.count - 1 + bands.count
    }

    /// Three compact outlines on the right of the window, where first-launch bands end;
    /// on the left when the rail sits on the right.
    static func placeholderFrames(in bounds: CGRect, railFrame: CGRect) -> [CGRect] {
        let mirrored = !railFrame.isEmpty && railFrame.midX > bounds.midX
        return Layout.placeholderPlacements.map { place in
            FloatingTabPlacement(x: mirrored ? 1 - place.x : place.x, y: place.y, shape: .tab, isPinned: false).frame(in: bounds)
        }
    }

    /// The paths to draw `time` seconds in: the entry beam with its pulse and the bands
    /// breathing, or, with `reduceMotion`, the same beams at rest.
    ///
    /// `tightened` is the lens being typed in: the entry beam narrows and brightens.
    func paths(color: Color.Components, time: TimeInterval, tightened: Bool, reduceMotion: Bool) -> [LightPath] {
        var entryPath = LightPath(
            points: entry,
            color: color,
            coreWidth: Layout.coreWidth,
            glowWidth: tightened ? Layout.entryGlowWidthTightened : Layout.entryGlowWidth,
            intensity: tightened ? Layout.entryIntensityTightened : Layout.entryIntensity,
        )
        if !reduceMotion {
            let phase = time.truncatingRemainder(dividingBy: Self.pulsePeriod)
            if phase < Self.pulseTravel {
                entryPath.pulse = LightPath.Pulse(position: phase / Self.pulseTravel, width: Layout.pulseWidth, gain: Layout.pulseGain)
            }
        }
        let bandPaths = bands.enumerated().map { index, band in
            LightPath(
                points: band.points,
                color: color.rotatingHue(by: band.hueOffset),
                coreWidth: Layout.coreWidth,
                glowWidth: Layout.bandGlowWidth,
                intensity: Layout.bandIntensity * (reduceMotion ? 1 : Self.breath(at: time, band: index)),
            )
        }
        return [entryPath] + bandPaths
    }

    /// The band's brightness factor, between 0.5 and 1, on a period of its own.
    static func breath(at time: TimeInterval, band index: Int) -> Double {
        let periods = breathPeriods
        let step = Int((periods.upperBound - periods.lowerBound).rounded()) + 1
        let period = periods.lowerBound + TimeInterval(index % step)
        return 0.75 + 0.25 * cos(2 * .pi * time / period)
    }

    // MARK: - Points on edges

    /// The point on `rect`'s edge where the line from its center toward `point` leaves it;
    /// `point` itself when it lies inside, and the center when it is the center.
    static func edgePoint(of rect: CGRect, toward point: CGPoint) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = point.x - center.x
        let dy = point.y - center.y
        guard dx != 0 || dy != 0 else { return center }
        let reachX = dx == 0 ? CGFloat.infinity : rect.width / 2 / abs(dx)
        let reachY = dy == 0 ? CGFloat.infinity : rect.height / 2 / abs(dy)
        let scale = min(reachX, reachY, 1)
        return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
    }

    /// The middle of the edge of `rect` that faces `point`: the near vertical edge when
    /// `point` lies beyond the rect's horizontal span, else the near horizontal edge.
    static func facingPoint(of rect: CGRect, toward point: CGPoint) -> CGPoint {
        if point.x < rect.minX {
            return CGPoint(x: rect.minX, y: rect.midY)
        }
        if point.x > rect.maxX {
            return CGPoint(x: rect.maxX, y: rect.midY)
        }
        return CGPoint(x: rect.midX, y: point.y < rect.midY ? rect.minY : rect.maxY)
    }

    private static func clamp(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }
}
