import CoreGraphics

/// Projects the shared table into a viewport without changing card positions.
nonisolated struct TabSpatialCamera: Equatable, Sendable {
    var origin: CGPoint = .zero
    var scale: CGFloat = 1

    func project(_ frame: CGRect) -> CGRect {
        CGRect(
            x: (frame.minX - origin.x) * scale,
            y: (frame.minY - origin.y) * scale,
            width: frame.width * scale,
            height: frame.height * scale,
        )
    }

    func unproject(_ frame: CGRect) -> CGRect {
        CGRect(
            x: origin.x + frame.minX / scale,
            y: origin.y + frame.minY / scale,
            width: frame.width / scale,
            height: frame.height / scale,
        )
    }

    /// Panning follows the input in screen points at every scale.
    mutating func pan(by delta: CGPoint) {
        guard delta.x.isFinite, delta.y.isFinite else { return }
        origin.x -= delta.x / scale
        origin.y -= delta.y / scale
    }

    /// Keeps the table point beneath the pointer fixed as the camera changes scale.
    mutating func zoom(to scale: CGFloat, at point: CGPoint) {
        guard scale.isFinite, scale > 0 else { return }
        let anchor = unproject(CGRect(origin: point, size: .zero)).origin
        self.scale = scale
        origin = CGPoint(x: anchor.x - point.x / scale, y: anchor.y - point.y / scale)
    }

    mutating func reveal(_ frame: CGRect, in viewport: CGRect) {
        let visible = unproject(viewport)
        func shift(_ low: CGFloat, _ high: CGFloat, _ start: CGFloat, _ end: CGFloat) -> CGFloat {
            if high - low > end - start {
                return (low + high - start - end) / 2
            }
            if low < start {
                return low - start
            }
            return max(0, high - end)
        }
        origin.x += shift(frame.minX, frame.maxX, visible.minX, visible.maxX)
        origin.y += shift(frame.minY, frame.maxY, visible.minY, visible.maxY)
    }
}
