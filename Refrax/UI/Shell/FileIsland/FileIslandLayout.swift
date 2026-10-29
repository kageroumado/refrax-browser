import CoreGraphics
import Foundation

/// The File Island's geometry: a 48-point column in the Control Island's width language,
/// placed and snapped by the same ``ControlIslandPlacement`` math.
nonisolated enum FileIslandLayout {
    /// Each file is a square cell the width of the rail's content.
    static let cellSize = ControlIslandPlacement.contentWidth
    /// A thumbnail or file icon inside its cell.
    static let thumbnailSize: CGFloat = 30
    static let thumbnailCornerRadius: CGFloat = 7
    /// The progress ring around an active download's icon.
    static let ringLineWidth: CGFloat = 2.5
    /// The most files the column shows before the rest wait behind the overflow row.
    static let maximumVisibleItems = 5
    /// A finished download stays on the island this long.
    static let recentInterval: TimeInterval = 60 * 60
    /// A drag this close to the island counts as over it.
    static let dropSlack: CGFloat = 24
    static let overflowPopoverWidth: CGFloat = 320
    static let overflowPopoverMaxHeight: CGFloat = 460

    /// The bottom corner opposite the Control Island, the island's place until it is moved.
    static func defaultPlacement(oppositeOf controlIsland: ControlIslandPlacement) -> ControlIslandPlacement {
        ControlIslandPlacement(x: controlIsland.x < 0.5 ? 1 : 0, y: 1)
    }

    /// The column's height: the top inset, an optional drop cell, one cell per file, a gap between
    /// downloads and the shelf, the overflow row, and the grip with its insets.
    static func height(downloads: Int, shelf: Int, showsDropCell: Bool) -> CGFloat {
        let cells = CGFloat(downloads + shelf + (showsDropCell ? 1 : 0)) * cellSize
        let divider = downloads > 0 && shelf > 0 ? ControlIslandPlacement.sectionGap : 0
        return ControlIslandPlacement.contentInset + cells + divider + ControlIslandPlacement.rowHeight + gripHeight
    }

    /// The grip closing the column and the inset under it.
    static var gripHeight: CGFloat {
        ControlIslandPlacement.gripGap + ControlIslandPlacement.gripSize.height + ControlIslandPlacement.gripBottomInset
    }

    /// The compact column, coupled under a rail with no room for files: one cell with an icon and
    /// a count, and the grip.
    static var compactHeight: CGFloat {
        ControlIslandPlacement.contentInset + cellSize + gripHeight
    }

    /// How many file cells fit in `bounds` beside the fixed rows, never more than ``maximumVisibleItems``.
    static func visibleLimit(in bounds: CGRect, showsDropCell: Bool) -> Int {
        let available = bounds.height - ControlIslandPlacement.margin * 2
            - height(downloads: 0, shelf: 0, showsDropCell: showsDropCell) - ControlIslandPlacement.sectionGap
        return max(0, min(maximumVisibleItems, Int((available / cellSize).rounded(.down))))
    }

    /// Whether a download that finished at `date` still belongs on the island at `now`.
    static func isRecent(_ date: Date, now: Date) -> Bool {
        now.timeIntervalSince(date) < recentInterval
    }
}

/// How the column's cells are shared: active and recent downloads first, then the shelf,
/// with whatever does not fit counted behind the overflow row.
nonisolated struct FileIslandAllocation: Equatable {
    let downloads: Int
    let shelf: Int
    let hidden: Int

    init(downloads: Int, shelf: Int, limit: Int) {
        let limit = max(0, limit)
        self.downloads = min(downloads, limit)
        self.shelf = min(shelf, limit - self.downloads)
        self.hidden = downloads + shelf - self.downloads - self.shelf
    }
}
