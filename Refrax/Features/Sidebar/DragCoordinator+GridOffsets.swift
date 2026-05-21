import Foundation
import SwiftUI

extension Sidebar.DragCoordinator {
    // MARK: - Grid Position

    /// Represents a position in a 2D grid layout (row-major order).
    struct GridPosition: Equatable, Sendable {
        let row: Int
        let column: Int

        /// Convert grid position to linear index.
        func toLinearIndex(columns: Int) -> Int {
            row * columns + column
        }

        /// Convert linear index to grid position.
        static func fromLinearIndex(_ index: Int, columns: Int) -> GridPosition {
            GridPosition(
                row: index / columns,
                column: index % columns,
            )
        }
    }

    // MARK: - Insertion Intent

    /// Determines where an item should be inserted relative to a target.
    enum InsertionIntent {
        case before
        case after
    }

    /// Type alias for grid layout info from Sidebar.GeometryState.
    typealias GridLayoutInfo = Sidebar.GeometryState.GridLayoutInfo

    // MARK: - Grid Offset Calculations

    /// Computes 2D offsets for items in a grid during drag reordering.
    ///
    /// Uses linear flow algorithm: items between the dragged position and target
    /// position shift by one slot in reading order (left-to-right, top-to-bottom).
    ///
    /// - Parameters:
    ///   - items: All items in the grid (in order)
    ///   - draggedIndex: Current index of the dragged item
    ///   - targetIndex: Target insertion index
    ///   - layout: Grid layout information (columns, tile size, spacing)
    /// - Returns: Dictionary mapping item IDs to their 2D offset
    func computeGridOffsets(
        items: [FavoriteItem],
        draggedIndex: Int,
        targetIndex: Int,
        layout: GridLayoutInfo,
    ) -> [UUID: CGPoint] {
        guard items.count > 1 else { return [:] }
        guard draggedIndex != targetIndex else { return [:] }

        var offsets: [UUID: CGPoint] = [:]
        let columns = layout.columns

        for (index, item) in items.enumerated() {
            // Skip the dragged item itself
            guard index != draggedIndex else { continue }

            let needsShift: Bool = if targetIndex < draggedIndex {
                // Dragging backward: items in [target, dragged) shift forward by one
                index >= targetIndex && index < draggedIndex
            } else {
                // Dragging forward: items in (dragged, target] shift backward by one
                index > draggedIndex && index <= targetIndex
            }

            if needsShift {
                let currentPos = GridPosition.fromLinearIndex(index, columns: columns)
                let shiftedIndex = targetIndex < draggedIndex ? index + 1 : index - 1
                let shiftedPos = GridPosition.fromLinearIndex(shiftedIndex, columns: columns)

                // Calculate pixel offset from current to shifted position
                let dx = CGFloat(shiftedPos.column - currentPos.column) * layout.horizontalStride
                let dy = CGFloat(shiftedPos.row - currentPos.row) * layout.verticalStride

                offsets[item.id] = CGPoint(x: dx, y: dy)
            }
        }

        return offsets
    }

    /// Determines insertion intent using binary space partitioning.
    ///
    /// This approach works by comparing the cursor position to the target item's
    /// centroid, rather than trying to find "gaps" between items (which fails at
    /// edges and in flow layouts).
    ///
    /// - Parameters:
    ///   - cursorPosition: Cursor position in grid coordinate space (include scroll offset)
    ///   - targetCentroid: Center point of the target item
    ///   - isHorizontalFlow: Whether the primary flow direction is horizontal (typical for grids)
    /// - Returns: Whether to insert before or after the target
    func determineInsertionIntent(
        cursorPosition: CGPoint,
        targetCentroid: CGPoint,
        isHorizontalFlow: Bool,
    ) -> InsertionIntent {
        if isHorizontalFlow {
            // For horizontal flow (typical grid), compare X positions
            cursorPosition.x < targetCentroid.x ? .before : .after
        } else {
            // For vertical flow, compare Y positions
            cursorPosition.y < targetCentroid.y ? .before : .after
        }
    }

    /// Calculates the target grid index from a cursor position.
    ///
    /// Uses the grid layout and item frames to determine which slot the cursor
    /// is closest to, accounting for the dragged item's current position.
    ///
    /// - Parameters:
    ///   - location: Cursor location in sidebar coordinate space
    ///   - items: All items in the grid
    ///   - draggedIndex: Index of the dragged item
    ///   - gridFrame: Frame of the entire grid in sidebar coordinate space
    ///   - layout: Grid layout information
    /// - Returns: Target insertion index
    func calculateGridTargetIndex(
        at location: CGPoint,
        items: [FavoriteItem],
        draggedIndex: Int,
        gridFrame: CGRect,
        layout: GridLayoutInfo,
    ) -> Int {
        guard !items.isEmpty else { return 0 }
        guard gridFrame.width > 0, gridFrame.height > 0 else { return 0 }

        // Convert location to grid-local coordinates
        let localX = location.x - gridFrame.minX
        let localY = location.y - gridFrame.minY

        // Calculate which cell the cursor is in
        let col = max(0, min(layout.columns - 1, Int(localX / layout.horizontalStride)))
        let row = max(0, Int(localY / layout.verticalStride))

        // Convert to linear index
        var linearIndex = row * layout.columns + col

        // Clamp to valid range (allow items.count for append-at-end position)
        linearIndex = max(0, min(items.count, linearIndex))

        // If cursor is beyond all items (append position), return immediately
        if linearIndex == items.count {
            return items.count
        }

        // If the cursor is in the dragged item's cell, return its index directly.
        // This prevents spurious offsets when dragging within the same slot.
        if linearIndex == draggedIndex {
            return draggedIndex
        }

        // Determine if we should insert before or after this index
        let targetPos = GridPosition.fromLinearIndex(linearIndex, columns: layout.columns)
        let targetCentroid = CGPoint(
            x: CGFloat(targetPos.column) * layout.horizontalStride + layout.tileSize.width / 2,
            y: CGFloat(targetPos.row) * layout.verticalStride + layout.tileSize.height / 2,
        )

        let intent = determineInsertionIntent(
            cursorPosition: CGPoint(x: localX, y: localY),
            targetCentroid: targetCentroid,
            isHorizontalFlow: true,
        )

        // Adjust index based on intent and dragged item position
        // Allow incrementing to items.count for append-at-end
        if intent == .after, linearIndex < items.count {
            linearIndex += 1
        }

        // Account for the gap left by the dragged item
        if linearIndex > draggedIndex {
            // Cursor is after the gap, so the effective target is linearIndex
            return linearIndex
        } else if linearIndex < draggedIndex {
            // Cursor is before the gap
            return linearIndex
        } else {
            // Cursor is at the gap position (where dragged item was)
            return draggedIndex
        }
    }

    /// Applies smoothstep easing to grid offset progress.
    ///
    /// Reuses the existing smoothstep function for consistency with tab list animations.
    func applyGridOffsetEasing(offsets: [UUID: CGPoint], progress: CGFloat) -> [UUID: CGPoint] {
        let easedProgress = smoothstep(progress)
        return offsets.mapValues { offset in
            CGPoint(
                x: offset.x * easedProgress,
                y: offset.y * easedProgress,
            )
        }
    }
}
