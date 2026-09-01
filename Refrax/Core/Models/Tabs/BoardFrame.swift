import CoreGraphics
import Foundation

/// A rectangle on the tab canvas, in board points with a top-left origin.
///
/// Stored on ``Tab`` and ``TabGroup`` as JSON so the board layout persists and
/// syncs like every other tab property.
nonisolated struct BoardFrame: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    static func decode(_ data: Data?) -> CGRect? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(BoardFrame.self, from: data).rect
    }

    static func encode(_ rect: CGRect?) -> Data? {
        guard let rect else { return nil }
        return try? JSONEncoder().encode(BoardFrame(rect))
    }
}

/// A point on the tab canvas, in board points with a top-left origin.
///
/// Stored on ``TabGroup`` as the anchor of a magnet.
nonisolated struct BoardPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var point: CGPoint {
        CGPoint(x: x, y: y)
    }

    static func decode(_ data: Data?) -> CGPoint? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(BoardPoint.self, from: data).point
    }

    static func encode(_ point: CGPoint?) -> Data? {
        guard let point else { return nil }
        return try? JSONEncoder().encode(BoardPoint(point))
    }
}
