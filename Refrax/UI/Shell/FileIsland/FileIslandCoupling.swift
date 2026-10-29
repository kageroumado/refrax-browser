import CoreGraphics

/// The File Island coupled under the Control Island: two islands a small gap apart that move as
/// one. The rail's bottom edge places the File Island on every layout pass, so it follows as the
/// rail grows or shrinks and never overlaps it; when the window has no room below the rail it
/// compacts, and with no room even for that it waits beside the rail at the window's bottom.
nonisolated enum FileIslandCoupling {
    /// The space between the rail's bottom edge and the File Island's top.
    static let gap = ControlIslandPlacement.adjacentGap
    /// How close the dragged island's top must come to the seam under the rail to couple on release.
    static let seamReach: CGFloat = 28
    /// How far the pointer pulls a coupled island before it pops free.
    static let breakDistance: CGFloat = 36
    /// How much of the pointer's travel a coupled island follows before it pops free.
    static let resistance: CGFloat = 0.3

    /// How the coupled island fits in the window under the rail.
    enum Fit: Equatable {
        /// Under the rail, showing at most `limit` files.
        case full(limit: Int)
        /// Under the rail as a single cell: an icon and a count.
        case compact
        /// No room under the rail: compact, beside it, at the window's bottom.
        case beside
    }

    /// The height free under `rail`: from the gap below it to the window's bottom margin.
    static func space(below rail: CGRect, in area: CGRect) -> CGFloat {
        max(0, area.maxY - ControlIslandPlacement.margin - (rail.maxY + gap))
    }

    /// How the island fits under `rail`: as many files as the space holds, up to the column's
    /// maximum; compact when not even one fits; beside the rail when the compact cell does not fit.
    static func fit(below rail: CGRect, in area: CGRect, showsDropCell: Bool) -> Fit {
        let space = space(below: rail, in: area)
        let fixed = FileIslandLayout.height(downloads: 0, shelf: 0, showsDropCell: showsDropCell) + ControlIslandPlacement.sectionGap
        let limit = min(FileIslandLayout.maximumVisibleItems, Int(((space - fixed) / FileIslandLayout.cellSize).rounded(.down)))
        if limit >= 1 {
            return .full(limit: limit)
        }
        return FileIslandLayout.compactHeight <= space ? .compact : .beside
    }

    /// The island's frame for `fit` at `height`: under `rail` at its width, or beside it on the
    /// window's inner side, resting on the bottom margin.
    static func frame(for fit: Fit, height: CGFloat, below rail: CGRect, in area: CGRect) -> CGRect {
        switch fit {
        case .full, .compact:
            return CGRect(x: rail.minX, y: rail.maxY + gap, width: rail.width, height: height)
        case .beside:
            let onRight = rail.midX > area.midX
            let x = onRight ? rail.minX - gap - rail.width : rail.maxX + gap
            let y = max(area.minY + ControlIslandPlacement.margin, area.maxY - ControlIslandPlacement.margin - height)
            return CGRect(x: x, y: y, width: rail.width, height: height)
        }
    }

    /// Whether an island dragged to `island` would couple under `rail` on release: its top near
    /// the seam below the rail's bottom edge, and roughly in the rail's column.
    static func isAtSeam(_ island: CGRect, rail: CGRect) -> Bool {
        guard !rail.isEmpty, !island.isEmpty else { return false }
        return abs(island.minY - (rail.maxY + gap)) <= seamReach
            && abs(island.midX - rail.midX) <= rail.width * 0.6
    }

    /// Where a coupled island sits while the pointer pulls it `translation` away: a fraction of
    /// the pull, as if held by a magnet. Nil once the pull passes ``breakDistance`` and it pops free.
    static func resistedOffset(for translation: CGSize) -> CGSize? {
        let distance = (translation.width * translation.width + translation.height * translation.height).squareRoot()
        guard distance < breakDistance else { return nil }
        return CGSize(width: translation.width * resistance, height: translation.height * resistance)
    }

    /// The glowing seam between `rail` and an island coupling under it, for the drag preview.
    static func seamFrame(below rail: CGRect) -> CGRect {
        CGRect(x: rail.minX + ControlIslandPlacement.horizontalInset * 2, y: rail.maxY + gap / 2 - 1.5,
               width: max(0, rail.width - ControlIslandPlacement.horizontalInset * 4), height: 3)
    }
}
