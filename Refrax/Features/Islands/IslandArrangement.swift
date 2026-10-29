import CoreGraphics
import Foundation

/// Fits islands into leading columns while reserving a readable page beside them.
nonisolated struct IslandArrangement {
    struct Item {
        let id: UUID
        let size: CGSize
    }

    private enum Layout {
        static let gap: CGFloat = 8
        static let minimumPageWidth: CGFloat = 320
        static let maximumColumns = 2
    }

    let frames: [UUID: CGRect]
    let pageInset: CGFloat

    init?(items: [Item], area: CGRect) {
        guard !items.isEmpty, !area.isEmpty else { return nil }
        let width = items.map(\.size.width).max() ?? IslandGeometry.titleWidth
        let availableWidth = area.width - Layout.minimumPageWidth - Layout.gap
        guard width <= availableWidth else { return nil }
        let maximumColumns = min(Layout.maximumColumns, max(1, Int((availableWidth + Layout.gap) / (width + Layout.gap))))
        let desiredHeight = items.reduce(0) { $0 + $1.size.height + IslandGeometry.headerReserve + Layout.gap } - Layout.gap
        let fitsInOneColumn = desiredHeight <= area.height
        let columns = fitsInOneColumn ? 1 : maximumColumns
        let rows = Int(ceil(Double(items.count) / Double(columns)))
        let height = fitsInOneColumn ? area.height : floor((area.height - CGFloat(rows - 1) * Layout.gap) / CGFloat(rows) - IslandGeometry.headerReserve)
        let minimumHeight = IslandGeometry(iconsOnly: false).contentHeight(rows: 1)
        guard height >= minimumHeight else { return nil }
        var placed: [UUID: CGRect] = [:]
        var y = area.minY
        for (index, item) in items.enumerated() {
            let column = index / rows
            if index % rows == 0 {
                y = area.minY
            }
            let size = CGSize(width: item.size.width, height: min(height, item.size.height))
            placed[item.id] = CGRect(x: area.minX + CGFloat(column) * (width + Layout.gap), y: y + IslandGeometry.headerReserve, width: size.width, height: size.height)
            y += size.height + IslandGeometry.headerReserve + Layout.gap
        }
        self.frames = placed
        self.pageInset = (placed.values.map(\.maxX).max() ?? area.minX) + Layout.gap
    }
}
