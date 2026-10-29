import CoreGraphics
import Foundation

/// The window side a docked page fills at full height.
nonisolated enum FloatingDockEdge: String, Codable, CaseIterable, Sendable {
    case leading
    case trailing

    /// The side as the menus name it.
    var title: String {
        switch self {
        case .leading: "Left"
        case .trailing: "Right"
        }
    }

    var opposite: Self {
        switch self {
        case .leading: .trailing
        case .trailing: .leading
        }
    }
}

/// Geometry of pages docked to the window's sides: the column each fills, the page area left
/// beside them, the zone a dragged card docks in, and the seam that resizes a column.
///
/// Frames are in the window's content coordinates with a top-left origin. A column sits
/// `margin` inside the window with corners concentric to the window's, and starts past the
/// control rail when the rail rests on its side. Columns keep at least `minimumColumnWidth`
/// and leave the page at least `minimumPageWidth`; when both cannot hold, the column keeps
/// its minimum.
nonisolated enum FloatingDockLayout {
    /// A newly docked page takes this share of the window's width.
    static let defaultFraction: Double = 0.38
    static let minimumColumnWidth: CGFloat = 320
    static let minimumPageWidth: CGFloat = 480
    /// The space between a column and the window's edges, and between a column and the page.
    static let margin: CGFloat = 8
    /// The corner radius of a Refrax window.
    static let windowCornerRadius = WindowCorner.radius
    /// The column's radius, concentric with the window's corner.
    static let cornerRadius = windowCornerRadius - margin
    /// A dragged card docks when the pointer comes this close to a window side.
    static let snapDistance: CGFloat = 24
    /// A rail whose outer side is this close to a window side rests on that side.
    static let railEdgeTolerance: CGFloat = 24
    /// The width of the seam's target, centered in the gap between column and page.
    static let seamHitWidth: CGFloat = 12
    /// A docked page's header dragged this far from its side undocks it.
    static let undockDistance: CGFloat = 48

    /// The column frames for the docked sides.
    struct Columns: Equatable {
        var leading: CGRect?
        var trailing: CGRect?

        subscript(edge: FloatingDockEdge) -> CGRect? {
            switch edge {
            case .leading: leading
            case .trailing: trailing
            }
        }
    }

    /// Whether the rail rests against `edge`, so a column there starts past it.
    static func railRests(on edge: FloatingDockEdge, rail: CGRect?, in bounds: CGRect) -> Bool {
        guard let rail, !rail.isEmpty else { return false }
        switch edge {
        case .leading: return rail.minX - bounds.minX <= railEdgeTolerance
        case .trailing: return bounds.maxX - rail.maxX <= railEdgeTolerance
        }
    }

    /// The outer limit of a column on `edge`: its first x on the leading side, its last x on
    /// the trailing side.
    static func outerLimit(of edge: FloatingDockEdge, in bounds: CGRect, rail: CGRect?) -> CGFloat {
        guard railRests(on: edge, rail: rail, in: bounds), let rail else {
            return edge == .leading ? bounds.minX + margin : bounds.maxX - margin
        }
        return edge == .leading ? rail.maxX + margin : rail.minX - margin
    }

    /// The columns for docked pages that ask for `leading` and `trailing` shares of the width;
    /// `nil` leaves a side undocked.
    static func columns(leading: Double?, trailing: Double?, in bounds: CGRect, rail: CGRect?) -> Columns {
        guard bounds.width > 0, bounds.height > 0 else { return Columns() }
        let start = outerLimit(of: .leading, in: bounds, rail: rail)
        let end = outerLimit(of: .trailing, in: bounds, rail: rail)
        var leadingWidth = leading.map { requestedWidth($0, in: bounds) }
        var trailingWidth = trailing.map { requestedWidth($0, in: bounds) }

        let docked = [leadingWidth, trailingWidth].compactMap(\.self)
        let pageMinX = leading == nil ? bounds.minX : start
        let pageMaxX = trailing == nil ? bounds.maxX : end
        let room = pageMaxX - pageMinX - margin * CGFloat(docked.count) - minimumPageWidth
        let total = docked.reduce(0, +)
        let shrinkable = total - minimumColumnWidth * CGFloat(docked.count)
        if total > room, shrinkable > 0 {
            let keep = 1 - min(1, (total - room) / shrinkable)
            leadingWidth = leadingWidth.map { minimumColumnWidth + ($0 - minimumColumnWidth) * keep }
            trailingWidth = trailingWidth.map { minimumColumnWidth + ($0 - minimumColumnWidth) * keep }
        }

        let top = bounds.minY + margin
        let height = max(1, bounds.height - margin * 2)
        return Columns(
            leading: leadingWidth.map { CGRect(x: start, y: top, width: $0, height: height) },
            trailing: trailingWidth.map { CGRect(x: end - $0, y: top, width: $0, height: height) },
        )
    }

    /// The page area beside the columns, at full window height.
    static func pageFrame(beside columns: Columns, in bounds: CGRect) -> CGRect {
        let minX = columns.leading.map { $0.maxX + margin } ?? bounds.minX
        let maxX = columns.trailing.map { $0.minX - margin } ?? bounds.maxX
        return CGRect(x: minX, y: bounds.minY, width: max(1, maxX - minX), height: bounds.height)
    }

    /// The share of the width a column on `edge` actually takes when it asks for `fraction`,
    /// beside a column on the other side asking for `opposite`.
    static func clampedFraction(_ fraction: Double, for edge: FloatingDockEdge, opposite: Double?, in bounds: CGRect, rail: CGRect?) -> Double {
        guard bounds.width > 0 else { return defaultFraction }
        let columns = edge == .leading
            ? columns(leading: fraction, trailing: opposite, in: bounds, rail: rail)
            : columns(leading: opposite, trailing: fraction, in: bounds, rail: rail)
        guard let column = columns[edge] else { return defaultFraction }
        return Double(column.width / bounds.width)
    }

    /// The share of the width a column on `edge` takes when its seam is dragged to `x`.
    static func fraction(forSeamAt x: CGFloat, edge: FloatingDockEdge, opposite: Double?, in bounds: CGRect, rail: CGRect?) -> Double {
        guard bounds.width > 0, x.isFinite else { return defaultFraction }
        let width = switch edge {
        case .leading: x - margin / 2 - outerLimit(of: .leading, in: bounds, rail: rail)
        case .trailing: outerLimit(of: .trailing, in: bounds, rail: rail) - (x + margin / 2)
        }
        return clampedFraction(Double(width / bounds.width), for: edge, opposite: opposite, in: bounds, rail: rail)
    }

    /// The side a card dragged with the pointer at `pointer` docks to: within `snapDistance` of
    /// a window side, or of the rail's outer edge while the rail rests on that side.
    static func snapEdge(at pointer: CGPoint, in bounds: CGRect, rail: CGRect?) -> FloatingDockEdge? {
        guard pointer.x.isFinite, pointer.y.isFinite, pointer.y >= bounds.minY, pointer.y <= bounds.maxY else { return nil }
        var leadingReach = bounds.minX + snapDistance
        var trailingReach = bounds.maxX - snapDistance
        if railRests(on: .leading, rail: rail, in: bounds), let rail {
            leadingReach = max(leadingReach, rail.maxX + snapDistance)
        }
        if railRests(on: .trailing, rail: rail, in: bounds), let rail {
            trailingReach = min(trailingReach, rail.minX - snapDistance)
        }
        if pointer.x <= leadingReach {
            return .leading
        }
        if pointer.x >= trailingReach {
            return .trailing
        }
        return nil
    }

    /// The seam's target beside `column`: centered in the gap between the column and the page.
    static func seamFrame(beside column: CGRect, edge: FloatingDockEdge) -> CGRect {
        let center = edge == .leading ? column.maxX + margin / 2 : column.minX - margin / 2
        return CGRect(x: center - seamHitWidth / 2, y: column.minY, width: seamHitWidth, height: column.height)
    }

    /// Whether a drag on a docked page's header by `translation` takes it off `edge`: far enough
    /// toward the page, or twice as far in any direction.
    static func undocks(after translation: CGSize, from edge: FloatingDockEdge) -> Bool {
        let away = edge == .leading ? translation.width : -translation.width
        return away >= undockDistance || hypot(translation.width, translation.height) >= undockDistance * 2
    }

    private static func requestedWidth(_ fraction: Double, in bounds: CGRect) -> CGFloat {
        let unit = fraction.isFinite ? min(1, max(0, fraction)) : defaultFraction
        return max(minimumColumnWidth, bounds.width * unit)
    }
}
