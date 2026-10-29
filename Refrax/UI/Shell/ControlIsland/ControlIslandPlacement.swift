import CoreGraphics
import Foundation

/// Stores the compact control rail's normalized position within the window.
nonisolated struct ControlIslandPlacement: Codable, Equatable {
    var x: Double = 0
    var y: Double = 0

    /// The minimum distance between the rail and the window's edge.
    static let margin: CGFloat = 8
    /// The inset from the rail's edge to a window light.
    static let lightInset: CGFloat = 12
    /// The diameter of a window light's artwork.
    static let lightDiameter: CGFloat = 12
    static let railWidth = lightInset * 2 + lightDiameter
    /// Center-to-center spacing for the window lights.
    static let lightPitch: CGFloat = 26
    /// Every control occupies the same vertical cell as a window light.
    static let rowHeight = lightPitch
    static let contentInset: CGFloat = 8
    static let horizontalInset: CGFloat = 4
    static let contentWidth = railWidth - horizontalInset * 2
    static let sectionGap = contentInset * 2
    /// The window's own corner: the rail is concentric with it at an edge and matches it afloat.
    static let cornerRadius: CGFloat = WindowCorner.radius
    /// The window's lights while the rail rests: gray, and this faint.
    static let restingLightsOpacity: Double = 0.45
    static let maximumVisibleSpaces = 4
    static let spaceRowHeight = rowHeight
    static let pageIconSize: CGFloat = 18
    static let pageLoadingRingSize: CGFloat = 22
    static let pageBranchWidth: CGFloat = 416
    static let pageBranchHeight: CGFloat = 44
    /// A row under the page card for each other pane of a split tab.
    static let paneRowHeight: CGFloat = 32
    static let adjacentGap: CGFloat = 8
    static let magnetDistance: CGFloat = 24
    /// A pointer must rest on the rail this long before the page card unfolds.
    static let hoverSettle: TimeInterval = 0.45
    static let spaceTintOpacity: Double = 0.18
    /// The tour's highlight of a row: a capsule this far inside the cell, with a glow around it.
    static let highlightInset: CGFloat = 2
    static let highlightLineWidth: CGFloat = 1.5
    static let highlightFillOpacity: Double = 0.3
    static let highlightGlowOpacity: Double = 0.7
    static let highlightGlowRadius: CGFloat = 8
    /// The handle closing the rail that moves the controls: a 3 × 2 grid of `gripDot`-point dots
    /// `gripDotSpacing` apart, the macOS handle for things that move.
    static let gripColumns = 3
    static let gripRows = 2
    static let gripDot: CGFloat = 4
    static let gripDotSpacing: CGFloat = 2
    static let gripSize = CGSize(
        width: CGFloat(gripColumns) * gripDot + CGFloat(gripColumns - 1) * gripDotSpacing,
        height: CGFloat(gripRows) * gripDot + CGFloat(gripRows - 1) * gripDotSpacing,
    )
    /// The compact File Island's gap above its grip.
    static let gripGap: CGFloat = 6

    /// How far a rounded edge of `radius` has receded from its straight tangent at a horizontal
    /// `offset` from the corner's center line: `r − √(r² − x²)`. Shapes that meet near a corner
    /// are read by their closest approach, so an inset that ignores this looks too tight.
    static func cornerSag(radius: CGFloat, offset: CGFloat) -> CGFloat {
        guard radius > 0, offset < radius else { return radius }
        return radius - (radius * radius - offset * offset).squareRoot()
    }

    /// The compact File Island's bottom inset keeps the grip's ends clear of its curved edge.
    static var gripBottomInset: CGFloat {
        gripGap + cornerSag(radius: cornerRadius, offset: gripSize.width / 2)
    }

    /// The rail's height: one row per action, three for the window controls, the space and
    /// favorite columns at their own heights, a gap for every divider, a row for the grip,
    /// and equal content insets.
    @MainActor
    static func railHeight(items: [ControlIslandItem], spaceCount: Int, favoriteCount: Int, favoritesOverflow: Bool = false) -> CGFloat {
        let layout = ControlIslandRailLayout(visibleItems: items)
        return layout.elements.reduce(contentInset * 2) { height, element in
            switch element {
            case .row(.windowControls): height + lightPitch * 3
            case .row(.spaces): height + CGFloat(min(spaceCount, maximumVisibleSpaces)) * spaceRowHeight + rowHeight
            case .row(.favoriteTabs): height + ControlIslandFavoriteTabs.height(for: favoriteCount, overflows: favoritesOverflow)
            case .row: height + rowHeight
            case .line, .gap: height + sectionGap
            case .grip: height + rowHeight
            }
        }
    }

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

    func pageBranchFrame(in bounds: CGRect, anchor: CGRect, height: CGFloat) -> CGRect {
        let area = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        let left = max(1, anchor.minX - Self.adjacentGap - area.minX)
        let right = max(1, area.maxX - anchor.maxX - Self.adjacentGap)
        let opensRight = right >= left
        let width = min(Self.pageBranchWidth, max(left, right))
        return CGRect(
            x: opensRight ? anchor.maxX + Self.adjacentGap : anchor.minX - Self.adjacentGap - width,
            y: min(max(anchor.minY, area.minY), max(area.minY, area.maxY - height)),
            width: width,
            height: min(height, area.height),
        )
    }

    /// Nearby window edges and edge midpoints become stable resting places.
    func snapped(in bounds: CGRect, height: CGFloat) -> Self {
        let frame = railFrame(in: bounds, height: height)
        let area = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        var result = self
        if frame.minX - area.minX < Self.magnetDistance {
            result.x = 0
        } else if area.maxX - frame.maxX < Self.magnetDistance {
            result.x = 1
        }
        if frame.minY - area.minY < Self.magnetDistance {
            result.y = 0
        } else if area.maxY - frame.maxY < Self.magnetDistance {
            result.y = 1
        }
        if result.x == 0 || result.x == 1, abs(frame.midY - area.midY) < Self.magnetDistance {
            result.y = 0.5
        }
        if result.y == 0 || result.y == 1, abs(frame.midX - area.midX) < Self.magnetDistance {
            result.x = 0.5
        }
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
