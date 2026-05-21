import SwiftUI

// MARK: - Pane Dragging

extension UnifiedContentView {
    /// Creates a drag gesture for rearranging panes in layout editing mode
    ///
    /// **Visual Result:** Allows users to click and drag panes to reorder them in the 2×2 grid.
    /// The dragged pane follows the cursor smoothly while other panes intelligently move out of the way.
    ///
    /// **UI Behavior:**
    /// - 10pt minimum drag distance to prevent accidental drags
    /// - Dragged pane appears elevated (z-index 100)
    /// - Target position shows blue highlight when overlap >50%
    /// - Occupied panes animate to nearest empty slot
    func paneDragGesture(for page: TabPage) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if draggedPaneID == nil {
                    draggedPaneID = page.id
                }
                handlePaneDrag(page: page, translation: value.translation, location: value.location)
            }
            .onEnded { _ in
                commitPaneDrag(for: page)
            }
    }

    /// Handles continuous drag movement and updates displacement/highlighting
    ///
    /// **Visual Result:** Real-time updates as pane is dragged:
    /// - Pane follows cursor using `PaneDragEffect` (GPU-accelerated transform)
    /// - Blue highlight appears on target pane when >50% overlap
    /// - Occupied target pane smoothly animates to nearest empty slot
    ///
    /// **Performance:** Uses geometry effect instead of offset for efficient pixel transformation
    func handlePaneDrag(page: TabPage, translation: CGSize, location _: CGPoint) {
        guard draggedPaneID == page.id else { return }

        dragModel.draggedPaneOffset = translation

        guard let draggedFrame = cachedFrames[page.id] else { return }
        let draggedCenter = CGPoint(
            x: draggedFrame.midX + translation.width,
            y: draggedFrame.midY + translation.height,
        )

        let targetPosition = findPanePosition(at: draggedCenter)

        guard let currentPosition = layoutGrid.position(for: page) else { return }

        let overlapPct = calculateOverlapPercentage(
            draggedFrame: draggedFrame.offsetBy(dx: translation.width, dy: translation.height),
            targetPosition: targetPosition,
        )

        if let target = targetPosition, target != currentPosition, overlapPct > 0.5 {
            highlightedDropTarget = target

            if let occupyingPage = layoutGrid.page(at: target), occupyingPage.id != page.id {
                displacePageTemporarily(occupyingPage, from: target, avoiding: currentPosition)
            } else {
                clearTemporaryDisplacements(except: [])
            }
        } else {
            highlightedDropTarget = nil
            clearTemporaryDisplacements(except: [])
        }
    }

    /// Finds which pane position contains the given point
    ///
    /// **Visual Result:** Hit-testing to determine which of the 4 grid slots contains a specific screen coordinate
    func findPanePosition(at point: CGPoint) -> PanePosition? {
        let allPositions: [PanePosition] = [.topLeft, .topRight, .bottomLeft, .bottomRight]

        for position in allPositions {
            let frame = layoutModeFrame(at: position)
            if frame.contains(point) {
                return position
            }
        }

        return nil
    }

    /// Calculates what percentage of the dragged pane overlaps with a target position
    ///
    /// **Visual Result:** Determines when to trigger highlighting and displacement (>50% overlap threshold)
    ///
    /// **Algorithm:** Uses CGRect intersection to calculate overlapping area as a percentage of dragged pane's total area
    func calculateOverlapPercentage(draggedFrame: CGRect, targetPosition: PanePosition?) -> CGFloat {
        guard let target = targetPosition else { return 0 }

        let targetFrame = layoutModeFrame(at: target)
        let intersection = draggedFrame.intersection(targetFrame)

        guard !intersection.isNull else { return 0 }

        let draggedArea = draggedFrame.width * draggedFrame.height
        guard draggedArea > 0 else { return 0 }

        let overlapArea = intersection.width * intersection.height
        return overlapArea / draggedArea
    }

    /// Temporarily moves a pane to the nearest available empty slot during drag
    ///
    /// **Visual Result:** When dragging over an occupied pane, the occupying pane smoothly animates
    /// to the nearest empty slot to make room. Uses spring physics for natural movement.
    ///
    /// **Algorithm:** Calculates distances between pane centers using Pythagorean theorem,
    /// selects closest empty slot
    func displacePageTemporarily(_ page: TabPage, from position: PanePosition, avoiding sourcePosition: PanePosition) {
        let allPositions: [PanePosition] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        let occupiedPositions = Set(layoutGrid.filledPositions)

        let emptyPositions = allPositions.filter { pos in
            pos != sourcePosition && !occupiedPositions.contains(pos)
        }

        if let nearestEmpty = findNearestPosition(to: position, in: emptyPositions) {
            withAnimation(conditionalSpringAnimation) {
                temporarilyDisplacedPanes[page.id] = nearestEmpty
            }
        }
    }

    /// Finds the nearest pane position to a reference position from a list of candidates
    ///
    /// **Visual Result:** Ensures displaced panes move to the closest available slot for minimal visual disruption
    ///
    /// **Algorithm:** Calculates Euclidean distance between pane centers using `hypot(dx, dy)`
    func findNearestPosition(to position: PanePosition, in candidates: [PanePosition]) -> PanePosition? {
        guard !candidates.isEmpty else { return nil }

        let posFrame = layoutModeFrame(at: position)
        let posCenter = CGPoint(x: posFrame.midX, y: posFrame.midY)

        return candidates.min(by: { pos1, pos2 in
            let frame1 = layoutModeFrame(at: pos1)
            let frame2 = layoutModeFrame(at: pos2)

            let center1 = CGPoint(x: frame1.midX, y: frame1.midY)
            let center2 = CGPoint(x: frame2.midX, y: frame2.midY)

            let dist1 = hypot(center1.x - posCenter.x, center1.y - posCenter.y)
            let dist2 = hypot(center2.x - posCenter.x, center2.y - posCenter.y)

            return dist1 < dist2
        })
    }

    /// Clears temporary displacement animations for all panes except specified IDs
    ///
    /// **Visual Result:** Displaced panes smoothly return to their original positions with spring animation
    func clearTemporaryDisplacements(except keepIDs: Set<UUID>) {
        withAnimation(conditionalSpringAnimation) {
            temporarilyDisplacedPanes = temporarilyDisplacedPanes.filter { keepIDs.contains($0.key) }
        }
    }

    /// Finalizes a pane drag operation - either commits the swap or snaps back
    ///
    /// **Visual Result:**
    /// - **Valid target:** Panes swap positions with smooth spring animation
    /// - **Invalid target:** Dragged pane snaps back to original position
    /// - All highlights and displacements clear
    /// - Control buttons reappear
    ///
    /// **State Updates:**
    /// - Updates `layoutGrid` with new positions
    /// - Updates `workingConfig.panePositions` for persistence
    /// - Recalculates frames for new layout
    func commitPaneDrag(for page: TabPage) {
        guard let draggedID = draggedPaneID,
              page.id == draggedID else {
            return
        }

        defer {
            withAnimation(conditionalSpringAnimation) {
                draggedPaneID = nil
                dragModel.draggedPaneOffset = .zero
                highlightedDropTarget = nil
                temporarilyDisplacedPanes = [:]
            }
        }

        guard let currentPosition = layoutGrid.position(for: page),
              let targetPosition = highlightedDropTarget else {
            return
        }

        withAnimation(conditionalSpringAnimation) {
            if let occupiedPage = layoutGrid.page(at: targetPosition) {
                layoutGrid.setPage(occupiedPage, at: currentPosition)
                workingConfig.panePositions[occupiedPage.id] = currentPosition
            } else {
                layoutGrid.removePage(at: currentPosition)
            }

            layoutGrid.setPage(page, at: targetPosition)
            workingConfig.panePositions[page.id] = targetPosition

            frameUpdateGeneration += 1
        }
    }
}
