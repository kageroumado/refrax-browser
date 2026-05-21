import Foundation
import SwiftUI

extension Sidebar.DragCoordinator {
    // MARK: - Private Helpers - Nesting Level

    /// Resets the dragged item's nesting level in metadata to match the actual model.
    ///
    /// Called when drag ends without committing to restore visual consistency.
    func resetDraggedItemNestingLevel() {
        guard let primaryDraggedItem,
              case let .tab(tab) = primaryDraggedItem else { return }

        let correctLevel = layoutManager.calculateNestingLevel(for: .tab(tab))

        if var metadata = layoutManager.metadata[primaryDraggedItem.id],
           metadata.nestingLevel != correctLevel {
            metadata.nestingLevel = correctLevel
            layoutManager.metadata[primaryDraggedItem.id] = metadata
        }
    }

    /// Update the nesting level in metadata for the dragged item
    /// This ensures the overlay shows correct indentation during drag
    func updateDraggedItemNestingLevel(hoveredIndex _: Int) {
        guard let primaryDraggedItem else { return }

        // Only tabs can be nested
        guard case .tab = primaryDraggedItem else { return }

        let overlayFrame = calculateCurrentOverlayFrame()
        let allItems = getAllItems()

        // Check if dragging within own group (to allow ungrouping)
        let draggedTabGroupID = primaryDraggedItem.tab?.groupID

        // Find if overlay is inside any group's bounds (deepest first)
        var targetNestingLevel = 0
        var deepestGroupNesting = -1

        if let draggedTabGroupID,
           let headerMetadata = layoutManager.metadata[draggedTabGroupID],
           let headerFrame = frameRegistry.frame(for: draggedTabGroupID) {
            // Keep nesting while the overlay remains inside the original group bounds.
            let descendants = getDescendants(of: draggedTabGroupID)
            var groupMinY = headerFrame.minY
            var groupMaxY = headerFrame.maxY

            let groupOffsetY = itemPushOffsets[draggedTabGroupID]?.y ?? 0
            groupMinY += groupOffsetY
            groupMaxY += groupOffsetY

            for descendantID in descendants {
                if let descendantFrame = frameRegistry.frame(for: descendantID) {
                    let descendantOffsetY = itemPushOffsets[descendantID]?.y ?? 0
                    groupMinY = min(groupMinY, descendantFrame.minY + descendantOffsetY)
                    groupMaxY = max(groupMaxY, descendantFrame.maxY + descendantOffsetY)
                }
            }

            let tolerance = DragConstants.groupBoundsTolerance
            let groupBounds = CGRect(
                x: headerFrame.minX,
                y: groupMinY - tolerance,
                width: headerFrame.width,
                height: (groupMaxY - groupMinY) + tolerance * 2,
            )

            let overlayMidY = overlayFrame.midY
            if overlayMidY >= groupBounds.minY, overlayMidY <= groupBounds.maxY {
                deepestGroupNesting = headerMetadata.nestingLevel
                targetNestingLevel = headerMetadata.nestingLevel + 1
            }
        }

        for item in allItems {
            guard case let .group(group) = item else { continue }

            // Skip own group to allow ungrouping
            if group.id == draggedTabGroupID { continue }

            guard let headerMetadata = layoutManager.metadata[group.id],
                  let headerFrame = frameRegistry.frame(for: group.id) else { continue }

            // Calculate group's full vertical span WITH current offset applied
            let descendants = getDescendants(of: group.id)
            var groupMinY = headerFrame.minY
            var groupMaxY = headerFrame.maxY

            // Apply group's push-aside offset (Y component only for vertical tab list)
            let groupOffsetY = itemPushOffsets[group.id]?.y ?? 0
            groupMinY += groupOffsetY
            groupMaxY += groupOffsetY

            // Include all descendants with their offsets
            for descendantID in descendants {
                if let descendantFrame = frameRegistry.frame(for: descendantID) {
                    let descendantOffsetY = itemPushOffsets[descendantID]?.y ?? 0
                    groupMinY = min(groupMinY, descendantFrame.minY + descendantOffsetY)
                    groupMaxY = max(groupMaxY, descendantFrame.maxY + descendantOffsetY)
                }
            }

            // Add some tolerance for easier targeting
            let tolerance = DragConstants.groupBoundsTolerance
            let groupBounds = CGRect(
                x: headerFrame.minX,
                y: groupMinY - tolerance,
                width: headerFrame.width,
                height: (groupMaxY - groupMinY) + tolerance * 2,
            )

            // Check if overlay center is inside group bounds
            let overlayMidY = overlayFrame.midY
            if overlayMidY >= groupBounds.minY, overlayMidY <= groupBounds.maxY {
                // Found a containing group - check if it's deeper than previous
                let groupNestingLevel = headerMetadata.nestingLevel
                if groupNestingLevel > deepestGroupNesting {
                    deepestGroupNesting = groupNestingLevel
                    // Tab nesting = group's nesting + 1
                    targetNestingLevel = groupNestingLevel + 1
                }
            }
        }

        // Update metadata if changed
        if var metadata = layoutManager.metadata[primaryDraggedItem.id],
           metadata.nestingLevel != targetNestingLevel {
            metadata.nestingLevel = targetNestingLevel
            layoutManager.metadata[primaryDraggedItem.id] = metadata
        }
    }
}
