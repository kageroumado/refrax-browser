import CoreGraphics
import Foundation

/// Preserves disclosure while the pointer crosses the space between related controls.
nonisolated struct ControlIslandHoverPath {
    private var departure: CGPoint?
    private var lastInside = Date.distantPast
    static let grace: TimeInterval = 0.55

    mutating func contains(_ point: CGPoint, regions: [CGRect], now: Date = Date()) -> Bool {
        if regions.contains(where: { $0.contains(point) }) {
            departure = point
            lastInside = now
            return true
        }
        guard let departure, now.timeIntervalSince(lastInside) < Self.grace else { return false }
        return regions.contains { Self.bridges(point, from: departure, to: $0) }
    }

    static func bridges(_ point: CGPoint, from origin: CGPoint, to target: CGRect) -> Bool {
        let corners = [CGPoint(x: target.minX, y: target.minY), CGPoint(x: target.maxX, y: target.minY),
                       CGPoint(x: target.maxX, y: target.maxY), CGPoint(x: target.minX, y: target.maxY)]
        return corners.indices.contains { index in
            let a = corners[index]
            let b = corners[(index + 1) % corners.count]
            let area = cross(origin, a, b)
            guard abs(area) > 0.001 else { return false }
            let u = cross(point, a, b) / area
            let v = cross(origin, point, b) / area
            let w = cross(origin, a, point) / area
            return u >= 0 && v >= 0 && w >= 0
        }
    }

    private static func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }
}
