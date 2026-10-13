import CoreGraphics
import SwiftUI

/// A freehand lasso: the points a drag has drawn, and the rule for what it catches.
///
/// The desk and the floating layer draw the same lasso. A drag becomes a lasso once it has
/// travelled ``threshold`` points from where it started; on release the path closes, and a
/// card is caught when its center lies inside the closed path.
nonisolated struct LassoSelection: Equatable {
    /// How far a drag travels before it draws.
    static let threshold: CGFloat = 4
    /// The stroke's dash: on, off.
    static let dash: [CGFloat] = [8, 6]
    static let lineWidth: CGFloat = 2
    /// The accent fill inside the stroke.
    static let fillOpacity: Double = 0.08

    private(set) var points: [CGPoint]
    /// The drag has passed the threshold and draws.
    private(set) var isDrawing = false

    init(at point: CGPoint) {
        self.points = [point]
    }

    /// Adds the pointer's next position. Returns whether the lasso draws.
    @discardableResult
    mutating func extend(to point: CGPoint) -> Bool {
        guard let start = points.first else { return false }
        if !isDrawing {
            guard hypot(point.x - start.x, point.y - start.y) >= Self.threshold else { return false }
            isDrawing = true
        }
        points.append(point)
        return true
    }

    /// The open path as drawn so far.
    var path: CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        return path
    }

    /// The path closed back to its start, as it is on release.
    var closedPath: CGPath {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    /// Whether the released lasso encloses enough to catch anything.
    var canCatch: Bool {
        isDrawing && points.count > 2
    }

    /// The items whose frame's center lies inside the closed lasso.
    func caught<ID: Hashable>(_ frames: [(id: ID, frame: CGRect)]) -> Set<ID> {
        guard canCatch else { return [] }
        let closed = closedPath
        return Set(frames.filter { closed.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }.map(\.id))
    }
}

/// The lasso as a SwiftUI shape, for the floating layer.
nonisolated struct LassoShape: Shape {
    let lasso: LassoSelection

    func path(in _: CGRect) -> Path {
        Path(lasso.path)
    }
}
