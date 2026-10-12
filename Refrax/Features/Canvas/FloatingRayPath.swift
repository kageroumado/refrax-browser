import CoreGraphics
import Foundation

/// A request for the floating layer to point at the tab that just left the window.
///
/// `source` is in window coordinates with a top-left origin, the frame of whatever
/// displaced the page: the Command Lens capsule, the page card, or the rail.
nonisolated struct FloatingRayRequest: Equatable, Sendable {
    let source: CGRect
    let tabID: Tab.ID
    let revision: Int
}

/// The route a ray takes from the control that displaced a page to the page's new
/// place in the floating layer: one straight run to a pane of glass just outside
/// the destination, one bend as it enters, and a short run to the destination's edge.
///
/// The bend follows Snell's law for glass (`refractiveIndex`), so the ray always turns
/// toward the pane's normal, the way light does entering a denser medium. Every point
/// is kept inside `area`.
nonisolated struct FloatingRayPath: Equatable, Sendable {
    let start: CGPoint
    let bend: CGPoint
    let end: CGPoint

    /// Glass; the ratio by which the sine of the incidence angle shrinks past the pane.
    static let refractiveIndex: CGFloat = 1.5
    /// Distance from the destination's near edge to the pane the ray refracts at.
    static let paneGap: CGFloat = 56
    /// Fraction of a short approach the pane sits at, so the bend stays between the two.
    static let paneApproachFraction: CGFloat = 0.4
    /// Approaches shorter than this get one straight run with its midpoint as the bend.
    static let minimumApproach: CGFloat = 8

    /// The pane's distance from the near edge for a ray approaching from `distance` away.
    static func paneGap(forApproach distance: CGFloat) -> CGFloat {
        min(paneGap, distance * paneApproachFraction)
    }

    init(start: CGPoint, bend: CGPoint, end: CGPoint) {
        self.start = start
        self.bend = bend
        self.end = end
    }

    init(from source: CGRect, to destination: CGRect, in area: CGRect) {
        let source = Self.finite(source)
        let destination = Self.finite(destination)
        let center = CGPoint(x: destination.midX, y: destination.midY)
        let start = Self.clamp(Self.exit(of: source, toward: center), to: area)
        let side = Self.nearSide(of: destination, from: start)

        guard !source.intersects(destination), !destination.contains(start),
              let side, side.distance(from: start, to: destination) > Self.minimumApproach else {
            let end = Self.clamp(Self.nearestEdgePoint(of: destination, to: start), to: area)
            self.init(start: start, bend: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), end: end)
            return
        }

        // The incoming direction aims at the destination's center and meets the pane
        // where the line crosses it; both distances are measured along the pane's normal.
        let gap = Self.paneGap(forApproach: side.distance(from: start, to: destination))
        let direction = CGVector(dx: center.x - start.x, dy: center.y - start.y)
        let normal = side.inwardNormal
        let along = direction.dx * normal.dx + direction.dy * normal.dy
        let paneOffset = (side.paneCoordinate(of: destination, gap: gap) - side.coordinate(of: start)) * (normal.dx + normal.dy)
        let t = along <= 0 ? 0 : paneOffset / along
        let hit = CGPoint(x: start.x + direction.dx * t, y: start.y + direction.dy * t)
        let bend = Self.clamp(hit, to: area)

        // Snell: sin θ₂ = sin θ₁ / n, measured from the normal; the tangential sign is kept.
        let length = hypot(direction.dx, direction.dy)
        let tangent = CGVector(dx: -normal.dy, dy: normal.dx)
        let sinIncidence = (direction.dx * tangent.dx + direction.dy * tangent.dy) / max(length, .ulpOfOne)
        let sinRefraction = sinIncidence / Self.refractiveIndex
        let cosRefraction = sqrt(max(0, 1 - sinRefraction * sinRefraction))
        let run = gap / max(cosRefraction, 0.1)
        let landing = CGPoint(
            x: bend.x + (normal.dx * cosRefraction + tangent.dx * sinRefraction) * run,
            y: bend.y + (normal.dy * cosRefraction + tangent.dy * sinRefraction) * run,
        )
        let end = Self.clamp(side.point(on: destination, nearest: landing), to: area)
        self.init(start: start, bend: bend, end: end)
    }

    /// Straight-line length of both runs.
    var length: CGFloat {
        hypot(bend.x - start.x, bend.y - start.y) + hypot(end.x - bend.x, end.y - bend.y)
    }

    /// Sine of the angle each run makes with the pane's normal; refraction shrinks the second.
    func sines(normal: CGVector) -> (incidence: CGFloat, refraction: CGFloat) {
        let tangent = CGVector(dx: -normal.dy, dy: normal.dx)
        func sine(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = hypot(dx, dy)
            return length == 0 ? 0 : abs(dx * tangent.dx + dy * tangent.dy) / length
        }
        return (sine(start, bend), sine(bend, end))
    }

    // MARK: - Sides

    /// The edge of the destination the ray enters through.
    enum Side: Equatable, Sendable {
        case top, bottom, leading, trailing

        var inwardNormal: CGVector {
            switch self {
            case .top: CGVector(dx: 0, dy: 1)
            case .bottom: CGVector(dx: 0, dy: -1)
            case .leading: CGVector(dx: 1, dy: 0)
            case .trailing: CGVector(dx: -1, dy: 0)
            }
        }

        fileprivate func coordinate(of point: CGPoint) -> CGFloat {
            switch self {
            case .top, .bottom: point.y
            case .leading, .trailing: point.x
            }
        }

        fileprivate func edgeCoordinate(of rect: CGRect) -> CGFloat {
            switch self {
            case .top: rect.minY
            case .bottom: rect.maxY
            case .leading: rect.minX
            case .trailing: rect.maxX
            }
        }

        fileprivate func paneCoordinate(of rect: CGRect, gap: CGFloat) -> CGFloat {
            edgeCoordinate(of: rect) - (inwardNormal.dx + inwardNormal.dy) * gap
        }

        fileprivate func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
            abs(edgeCoordinate(of: rect) - coordinate(of: point))
        }

        fileprivate func point(on rect: CGRect, nearest point: CGPoint) -> CGPoint {
            switch self {
            case .top, .bottom: CGPoint(x: min(max(point.x, rect.minX), rect.maxX), y: edgeCoordinate(of: rect))
            case .leading, .trailing: CGPoint(x: edgeCoordinate(of: rect), y: min(max(point.y, rect.minY), rect.maxY))
            }
        }
    }

    /// The side of `rect` that `point` lies outside of by the largest margin.
    static func nearSide(of rect: CGRect, from point: CGPoint) -> Side? {
        let above = rect.minY - point.y
        let below = point.y - rect.maxY
        let before = rect.minX - point.x
        let beyond = point.x - rect.maxX
        let vertical = max(above, below)
        let horizontal = max(before, beyond)
        guard max(vertical, horizontal) > 0 else { return nil }
        if vertical >= horizontal { return above >= below ? .top : .bottom }
        return before >= beyond ? .leading : .trailing
    }

    // MARK: - Helpers

    /// Where a ray leaving the rect's center toward `target` crosses the rect's edge.
    private static func exit(of rect: CGRect, toward target: CGPoint) -> CGPoint {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dx = target.x - center.x, dy = target.y - center.y
        guard rect.width > 0 || rect.height > 0, dx != 0 || dy != 0 else { return center }
        let tx = dx == 0 ? CGFloat.infinity : (rect.width / 2) / abs(dx)
        let ty = dy == 0 ? CGFloat.infinity : (rect.height / 2) / abs(dy)
        let t = min(tx, ty)
        return CGPoint(x: center.x + dx * t, y: center.y + dy * t)
    }

    private static func nearestEdgePoint(of rect: CGRect, to point: CGPoint) -> CGPoint {
        let clamped = CGPoint(x: min(max(point.x, rect.minX), rect.maxX), y: min(max(point.y, rect.minY), rect.maxY))
        guard rect.contains(point) else { return clamped }
        let toEdges = [
            (point.x - rect.minX, CGPoint(x: rect.minX, y: point.y)),
            (rect.maxX - point.x, CGPoint(x: rect.maxX, y: point.y)),
            (point.y - rect.minY, CGPoint(x: point.x, y: rect.minY)),
            (rect.maxY - point.y, CGPoint(x: point.x, y: rect.maxY)),
        ]
        return toEdges.min { $0.0 < $1.0 }?.1 ?? clamped
    }

    private static func clamp(_ point: CGPoint, to area: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, area.minX), area.maxX), y: min(max(point.y, area.minY), area.maxY))
    }

    private static func finite(_ rect: CGRect) -> CGRect {
        let values = [rect.minX, rect.minY, rect.width, rect.height]
        guard values.allSatisfy(\.isFinite) else { return .zero }
        return rect.standardized
    }
}
