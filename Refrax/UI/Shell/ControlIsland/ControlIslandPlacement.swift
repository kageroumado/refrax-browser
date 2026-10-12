import CoreGraphics
import Foundation

/// Stores the compact control rail's normalized position within the window.
nonisolated struct ControlIslandPlacement: Codable, Equatable {
    var x: Double = 0
    var y: Double = 0.2

    static let margin: CGFloat = 12
    static let railWidth: CGFloat = 48
    static let rowHeight: CGFloat = 32
    static let contentInset: CGFloat = 8
    static let horizontalInset: CGFloat = 4
    static let contentWidth = railWidth - horizontalInset * 2
    static let sectionGap: CGFloat = 12
    static let cornerRadius: CGFloat = 24
    static let maximumVisibleSpaces = 4
    static let spaceRowHeight = contentWidth
    static let pageBranchWidth: CGFloat = 416
    static let pageBranchHeight: CGFloat = 40
    static let adjacentGap: CGFloat = 8
    static let magnetDistance: CGFloat = 24

    func railFrame(in bounds: CGRect, height: CGFloat) -> CGRect {
        let area = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        let size = CGSize(width: min(Self.railWidth, max(1, area.width)), height: min(height, max(1, area.height)))
        return CGRect(
            x: area.minX + Self.unit(x) * max(0, area.width - size.width),
            y: area.minY + Self.unit(y) * max(0, area.height - size.height),
            width: size.width, height: size.height,
        )
    }

    func opensLeft(in bounds: CGRect) -> Bool {
        railFrame(in: bounds, height: 1).midX > bounds.midX
    }

    /// Opens beside the circular target so disclosure cannot put an action under the pointer.
    func buttonPanelFrame(in bounds: CGRect, height: CGFloat) -> CGRect {
        let area = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        let button = railFrame(in: bounds, height: Self.railWidth)
        let below = max(0, area.maxY - button.maxY - Self.adjacentGap)
        let above = max(0, button.minY - area.minY - Self.adjacentGap)
        let opensDown = below >= above
        let panelHeight = min(height, max(1, max(below, above)))
        return CGRect(
            x: button.minX,
            y: opensDown ? button.maxY + Self.adjacentGap : button.minY - Self.adjacentGap - panelHeight,
            width: button.width, height: panelHeight,
        )
    }

    func pageBranchFrame(in bounds: CGRect, anchor: CGRect, height: CGFloat) -> CGRect {
        let area = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        let left = max(1, anchor.minX - Self.adjacentGap - area.minX)
        let right = max(1, area.maxX - anchor.maxX - Self.adjacentGap)
        let opensRight = right >= left
        let width = min(Self.pageBranchWidth, max(left, right))
        return CGRect(x: opensRight ? anchor.maxX + Self.adjacentGap : anchor.minX - Self.adjacentGap - width,
                      y: min(max(anchor.minY, area.minY), max(area.minY, area.maxY - height)),
                      width: width, height: min(height, area.height))
    }

    /// Nearby window edges and edge midpoints become stable resting places.
    func snapped(in bounds: CGRect, height: CGFloat) -> Self {
        let frame = railFrame(in: bounds, height: height)
        let area = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        var result = self
        if frame.minX - area.minX < Self.magnetDistance { result.x = 0 }
        else if area.maxX - frame.maxX < Self.magnetDistance { result.x = 1 }
        if frame.minY - area.minY < Self.magnetDistance { result.y = 0 }
        else if area.maxY - frame.maxY < Self.magnetDistance { result.y = 1 }
        if result.x == 0 || result.x == 1, abs(frame.midY - area.midY) < Self.magnetDistance { result.y = 0.5 }
        if result.y == 0 || result.y == 1, abs(frame.midX - area.midX) < Self.magnetDistance { result.x = 0.5 }
        return result
    }

    mutating func move(to origin: CGPoint, in bounds: CGRect, height: CGFloat) {
        let area = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        let rail = railFrame(in: bounds, height: height)
        x = Self.unit((origin.x - area.minX) / max(1, area.width - rail.width))
        y = Self.unit((origin.y - area.minY) / max(1, area.height - rail.height))
    }

    private static func unit(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}
