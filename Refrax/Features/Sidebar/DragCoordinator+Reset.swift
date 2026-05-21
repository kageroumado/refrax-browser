import Foundation
import SwiftUI

extension Sidebar.DragCoordinator {
    // MARK: - Reset

    /// Reset all drag state
    func reset() {
        isDragging = false
        draggedItems.removeAll()
        followerItems.removeAll()
        hiddenFollowerIDs.removeAll()
        _originPosition = nil
        _draggedItemWasActive = false
        _dropTarget = .none
        activeDropZone = nil
        _preCalculatedTargetPosition = nil
        _gridShrinkCompensation = 0
        _dropZonePushCompensation = 0
        _convertedItemID = nil
        isAnimatingReturn = false
        currentOffset = 0
        showDataStorageWarning = false
        currentOverlayMode = .tabRow
        overlayMorphProgress = 1.0
        overlayPosition = .zero
        itemPushOffsets = [:]
        _draggedItemOriginalFrame = nil
        _clickOffset = .zero
        _draggedGroupBounds = nil
        _partialAnimationItems = []
        _crossedThresholdItems = []
        _firstItemStartY = nil
        _dropZonesActive = false

        // AppKit handoff state
        handoffPhase = .internal
        ghostState = nil
        externalPhaseStartTime = nil

        // Inbound drop state
        inboundDropZone = nil

        clearCaches()
    }
}
