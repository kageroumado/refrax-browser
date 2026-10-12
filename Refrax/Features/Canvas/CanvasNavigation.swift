import CoreGraphics
import Foundation

/// Spatial targeting in desk coordinates, where y increases down the screen.
nonisolated enum CanvasNavigation {
    private enum Constants {
        static let perpendicularWeight: CGFloat = 2
    }
    enum Direction: UInt16, CaseIterable {
        case left = 123
        case right = 124
        case down = 125
        case up = 126
    }

    struct Tile {
        let id: UUID
        let frame: CGRect
    }

    /// Chooses the nearest tile, retaining the current target within a small boundary band.
    /// Input order resolves equal distances consistently.
    static func nearest(to point: CGPoint, in tiles: [Tile], retaining currentID: UUID? = nil, hysteresis: CGFloat = 0) -> UUID? {
        let ranked = tiles.map { tile in
            let dx = max(tile.frame.minX - point.x, 0, point.x - tile.frame.maxX)
            let dy = max(tile.frame.minY - point.y, 0, point.y - tile.frame.maxY)
            return (tile: tile, distance: hypot(dx, dy), centerDistance: hypot(tile.frame.midX - point.x, tile.frame.midY - point.y))
        }
        guard let nearest = ranked.min(by: {
            $0.distance == $1.distance ? $0.centerDistance < $1.centerDistance : $0.distance < $1.distance
        }) else { return nil }
        if let current = ranked.first(where: { $0.tile.id == currentID }),
           current.distance <= nearest.distance + hysteresis, current.distance > 0 || current.tile.frame.contains(point) {
            return current.tile.id
        }
        return nearest.tile.id
    }

    /// Advances toward the arrow, preferring tiles in the same row or column.
    static func neighbor(from id: UUID, toward direction: Direction, in tiles: [Tile]) -> UUID? {
        guard let origin = tiles.first(where: { $0.id == id })?.frame else { return nil }
        let horizontal = direction == .left || direction == .right
        let sign: CGFloat = direction == .left || direction == .up ? -1 : 1
        let candidates = tiles.compactMap { tile -> (id: UUID, inBeam: Bool, score: CGFloat)? in
            guard tile.id != id else { return nil }
            let dx = tile.frame.midX - origin.midX
            let dy = tile.frame.midY - origin.midY
            let forward = (horizontal ? dx : dy) * sign
            guard forward > 0 else { return nil }
            let gap = horizontal
                ? max(tile.frame.minY - origin.maxY, origin.minY - tile.frame.maxY, 0)
                : max(tile.frame.minX - origin.maxX, origin.minX - tile.frame.maxX, 0)
            let perpendicular = abs(horizontal ? dy : dx)
            return (tile.id, gap == 0, forward + perpendicular * Constants.perpendicularWeight)
        }
        return candidates.min {
            $0.inBeam != $1.inBeam ? $0.inBeam : $0.score < $1.score
        }?.id
    }
}

/// Tracks the intent of a desk pinch independently of the fingers lifting.
nonisolated struct CanvasPinchIntent {
    private enum Constants {
        static let minimumStepScale: CGFloat = 0.05
        static let directionEpsilon: CGFloat = 0.001
        static let entryScale: CGFloat = 1.01
    }
    private(set) var scale: CGFloat = 1
    private(set) var lastStep: CGFloat = 0

    mutating func update(by magnification: CGFloat) {
        guard magnification.isFinite else { return }
        scale *= max(Constants.minimumStepScale, 1 + magnification)
        if abs(magnification) > Constants.directionEpsilon {
            lastStep = magnification
        }
    }

    /// Entry requires a pinch that enlarged a tile and is still heading into it.
    var shouldEnter: Bool {
        scale > Constants.entryScale && lastStep > 0
    }
}
