import CoreGraphics
import Foundation

/// Spatial targeting in desk coordinates, where y increases down the screen.
nonisolated enum CanvasNavigation {
    private enum Constants {
        static let maximumNeighborGap: CGFloat = 64
        static let minimumBeamOverlap: CGFloat = 8
        static let overlapTolerance: CGFloat = 2
    }
    enum Direction: UInt16, CaseIterable {
        case left = 123
        case right = 124
        case down = 125
        case up = 126

        var opposite: Self {
            switch self {
            case .left: .right
            case .right: .left
            case .up: .down
            case .down: .up
            }
        }
    }

    struct Tile {
        let id: UUID
        let frame: CGRect
        let groupID: UUID?

        init(id: UUID, frame: CGRect, groupID: UUID? = nil) {
            self.id = id
            self.frame = frame
            self.groupID = groupID
        }
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

    /// Follows a nearby, visible connection that also leads back in the reverse direction.
    static func neighbor(from id: UUID, toward direction: Direction, in tiles: [Tile]) -> UUID? {
        guard let origin = tiles.first(where: { $0.id == id }),
              let next = nearestAdjacent(to: origin, toward: direction, in: tiles),
              nearestAdjacent(to: next, toward: direction.opposite, in: tiles)?.id == id else { return nil }
        return next.id
    }

    private static func nearestAdjacent(to origin: Tile, toward direction: Direction, in tiles: [Tile]) -> Tile? {
        let horizontal = direction == .left || direction == .right
        let candidates = tiles.compactMap { tile -> (tile: Tile, gap: CGFloat, offset: CGFloat)? in
            guard tile.id != origin.id, tile.groupID == origin.groupID else { return nil }
            let gap: CGFloat
            let overlap: CGFloat
            let offset: CGFloat
            switch direction {
            case .left:
                gap = origin.frame.minX - tile.frame.maxX
            case .right:
                gap = tile.frame.minX - origin.frame.maxX
            case .up:
                gap = origin.frame.minY - tile.frame.maxY
            case .down:
                gap = tile.frame.minY - origin.frame.maxY
            }
            if horizontal {
                overlap = min(origin.frame.maxY, tile.frame.maxY) - max(origin.frame.minY, tile.frame.minY)
                offset = abs(origin.frame.midY - tile.frame.midY)
            } else {
                overlap = min(origin.frame.maxX, tile.frame.maxX) - max(origin.frame.minX, tile.frame.minX)
                offset = abs(origin.frame.midX - tile.frame.midX)
            }
            guard gap >= -Constants.overlapTolerance, gap <= Constants.maximumNeighborGap,
                  overlap >= Constants.minimumBeamOverlap else { return nil }
            return (tile, max(0, gap), offset)
        }
        return candidates.min {
            $0.gap == $1.gap ? $0.offset < $1.offset : $0.gap < $1.gap
        }?.tile
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
