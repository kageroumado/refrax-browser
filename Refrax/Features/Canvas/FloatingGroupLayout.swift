import CoreGraphics

/// The geometry of a group on the floating layer: a glass capsule header inside the top
/// leading corner of a tinted outline that holds the group's cards.
///
/// Every radius is concentric: the outline's corner is the header capsule's radius plus the
/// header's inset, and the cards sit inside the outline by the outline's radius minus their own.
/// Folded, the group is its header alone, at the place the header has while unfolded.
nonisolated enum FloatingGroupLayout {
    static let headerHeight: CGFloat = 28
    /// The header's distance from the outline's top and leading edges.
    static let headerInset: CGFloat = 6
    /// The space between the header and the cards below it.
    static let headerGap: CGFloat = 4
    /// The header's width before the layer has measured it.
    static let nominalHeaderWidth: CGFloat = 160
    /// The widest a folded header grows, whatever its name.
    static let maximumHeaderWidth: CGFloat = 260
    /// Favicons stacked on a folded header.
    static let foldedFaviconLimit = 3
    /// Two members closer than this count as one pile, which unfolding fans out.
    static let stackTolerance: CGFloat = 2
    /// The space between cards fanned out of a stack.
    static let fanGap: CGFloat = 12

    /// The radius of a shape inset by `inset` inside a shape of radius `outer`.
    static func concentricRadius(outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(0, outer - inset)
    }

    /// The outline's corner radius: concentric around the header capsule.
    static var outlineRadius: CGFloat {
        headerHeight / 2 + headerInset
    }

    /// The cards' inset inside the outline: concentric around the cards' own corners.
    static var cardPadding: CGFloat {
        outlineRadius - CanvasTileLayout.slabCornerRadius
    }

    /// The outline's top edge above its highest card: the header, its inset, and its gap.
    static var topPadding: CGFloat {
        headerInset + headerHeight + headerGap
    }

    /// The outline around `memberFrames` (cards and nested outlines), kept inside `area`.
    static func outlineFrame(around memberFrames: [CGRect], in area: CGRect) -> CGRect? {
        guard let first = memberFrames.first else { return nil }
        let bounds = memberFrames.dropFirst().reduce(first) { $0.union($1) }
        let outline = CGRect(
            x: bounds.minX - cardPadding,
            y: bounds.minY - topPadding,
            width: bounds.width + cardPadding * 2,
            height: bounds.height + topPadding + cardPadding,
        )
        return outline.intersection(area).isNull ? outline : outline.intersection(area)
    }

    /// The header's frame inside `outline`, at most `width` wide.
    static func headerFrame(in outline: CGRect, width: CGFloat) -> CGRect {
        CGRect(
            x: outline.minX + headerInset,
            y: outline.minY + headerInset,
            width: max(headerHeight, min(width, outline.width - headerInset * 2, maximumHeaderWidth)),
            height: headerHeight,
        )
    }

    /// The folded header's frame: where the header sits while unfolded, as wide as its content.
    static func foldedHeaderFrame(in outline: CGRect, width: CGFloat) -> CGRect {
        CGRect(
            x: outline.minX + headerInset,
            y: outline.minY + headerInset,
            width: max(headerHeight, min(width, maximumHeaderWidth)),
            height: headerHeight,
        )
    }

    /// Where members piled into a stack go so that the folded header lands at `headerOrigin`.
    static func memberOrigin(forHeaderAt headerOrigin: CGPoint) -> CGPoint {
        CGPoint(x: headerOrigin.x - headerInset + cardPadding, y: headerOrigin.y - headerInset + topPadding)
    }

    /// Whether every frame starts at the same place: a pile left by Stacks by Site.
    static func isPiled(_ frames: [CGRect]) -> Bool {
        guard frames.count > 1, let first = frames.first else { return false }
        return frames.allSatisfy {
            abs($0.minX - first.minX) <= stackTolerance && abs($0.minY - first.minY) <= stackTolerance
        }
    }

    /// Origins for `count` cards of `size` fanned out of a pile at `origin`: rows of up to
    /// ⌈√count⌉ cards, filling right then down, turning back left at `area`'s trailing edge.
    static func fanOrigins(count: Int, size: CGSize, from origin: CGPoint, in area: CGRect) -> [CGPoint] {
        guard count > 0 else { return [] }
        let usable = FloatingTabPlacement.availableArea(in: area)
        let requestedColumns = max(1, Int(Double(count).squareRoot().rounded(.up)))
        let fittingColumns = max(1, Int((usable.width + fanGap) / (size.width + fanGap)))
        let columns = min(requestedColumns, fittingColumns)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let step = CGSize(width: size.width + fanGap, height: size.height + fanGap)
        let span = CGFloat(columns) * step.width - fanGap
        let height = CGFloat(rows) * step.height - fanGap
        let startX = min(max(usable.minX, origin.x), max(usable.minX, usable.maxX - span))
        let startY = min(max(usable.minY, origin.y), max(usable.minY, usable.maxY - height))
        return (0 ..< count).map { index in
            CGPoint(
                x: startX + CGFloat(index % columns) * step.width,
                y: startY + CGFloat(index / columns) * step.height,
            )
        }
    }

    /// The group a card dropped at `point` joins: the smallest target containing it, so a
    /// nested group wins over its parent.
    static func dropTarget<ID>(at point: CGPoint, among targets: [(id: ID, frame: CGRect)]) -> ID? {
        targets.filter { $0.frame.contains(point) }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?.id
    }
}
