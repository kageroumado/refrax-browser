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
    static let addressSize = CGSize(width: 300, height: 36)
    static let tabInfoSize = CGSize(width: 304, height: 124)
    private static let adjacentGap: CGFloat = 8

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
        let width = min(Self.railWidth, max(1, area.width - Self.railWidth - Self.contentInset))
        let panelHeight = min(height, max(1, area.height))
        let proposedX = opensLeft(in: bounds)
            ? button.minX - Self.contentInset - width : button.maxX + Self.contentInset
        return CGRect(
            x: min(max(proposedX, area.minX), area.maxX - width),
            y: min(max(button.midY - panelHeight / 2, area.minY), area.maxY - panelHeight),
            width: width, height: panelHeight,
        )
    }

    func addressFrame(in bounds: CGRect, island: CGRect, rowMidY: CGFloat? = nil) -> CGRect {
        adjacentFrame(size: Self.addressSize, in: bounds, island: island, rowMidY: rowMidY)
    }

    func tabInfoFrame(in bounds: CGRect, island: CGRect) -> CGRect {
        let area = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        let availableWidth = max(island.minX - area.minX, area.maxX - island.maxX) - Self.adjacentGap
        let size = CGSize(width: min(Self.tabInfoSize.width, max(1, availableWidth)), height: Self.tabInfoSize.height)
        return adjacentFrame(size: size, in: bounds, island: island, rowMidY: island.minY + size.height / 2)
    }

    private func adjacentFrame(size: CGSize, in bounds: CGRect, island: CGRect, rowMidY: CGFloat?) -> CGRect {
        let area = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        let width = min(size.width, max(1, area.width))
        let gap = Self.adjacentGap
        let x: CGFloat
        let y: CGFloat
        if island.maxX + gap + width <= area.maxX {
            x = island.maxX + gap
            y = (rowMidY ?? island.midY) - size.height / 2
        } else if island.minX - gap - width >= area.minX {
            x = island.minX - gap - width
            y = (rowMidY ?? island.midY) - size.height / 2
        } else {
            x = min(max(island.midX - width / 2, area.minX), area.maxX - width)
            y = island.minY - gap - size.height >= area.minY
                ? island.minY - gap - size.height : island.maxY + gap
        }
        return CGRect(
            x: x,
            y: min(max(y, area.minY), max(area.minY, area.maxY - size.height)),
            width: width,
            height: size.height,
        )
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
