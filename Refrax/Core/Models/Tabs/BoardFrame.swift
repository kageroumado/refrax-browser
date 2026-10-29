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
    var isCompact: Bool?
    var floating: FloatingTabPlacement?
    var hasDeskFrame: Bool?

    init(_ rect: CGRect, isCompact: Bool = false) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.width
        self.height = rect.height
        self.isCompact = isCompact ? true : nil
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    static func decode(_ data: Data?) -> CGRect? {
        guard let data else { return nil }
        guard let value = value(data), value.hasDeskFrame != false else { return nil }
        return value.rect
    }

    static func isCompact(_ data: Data?) -> Bool {
        guard let data else { return false }
        return (try? JSONDecoder().decode(BoardFrame.self, from: data).isCompact) == true
    }

    static func value(_ data: Data?) -> Self? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    static func updating(frame: CGRect?, isCompact: Bool, floating: FloatingTabPlacement?) -> Data? {
        guard frame != nil || floating != nil else { return nil }
        var value = Self(frame ?? .zero, isCompact: isCompact)
        value.hasDeskFrame = frame == nil ? false : nil
        value.floating = floating
        return try? JSONEncoder().encode(value)
    }

    static func encode(_ rect: CGRect?, isCompact: Bool = false) -> Data? {
        guard let rect else { return nil }
        return try? JSONEncoder().encode(BoardFrame(rect, isCompact: isCompact))
    }
}

/// A point on the tab canvas, in board points with a top-left origin.
///
/// Stored on ``TabGroup`` as the anchor of a magnet.
nonisolated struct BoardPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        self.x = point.x
        self.y = point.y
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
