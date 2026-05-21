import AppKit
import Foundation

extension Sidebar.DragCoordinator {
    // MARK: - AppKit Handoff Types

    /// Phase of the drag operation with respect to SwiftUI/AppKit ownership.
    ///
    /// Transitions:
    /// - `.internal` → `.transitioning`: Cursor exits sidebar bounds
    /// - `.transitioning` → `.external`: AppKit drag session begins
    /// - `.external` → `.internal`: Re-entry detected via pasteboard type
    /// - Any → `.internal`: Drag ends (commit or cancel)
    enum HandoffPhase: Equatable {
        /// SwiftUI overlay is active, drag is within sidebar bounds
        case `internal`
        /// Handoff in progress - AppKit session being created
        case transitioning
        /// AppKit owns the drag session
        case external
    }

    /// Frozen state preserved during AppKit phase for re-entry.
    ///
    /// When transitioning to AppKit, the coordinator's live state becomes invalid
    /// (overlays hidden, offsets cleared). This struct captures everything needed
    /// to resume internal dragging if the user drags back into the sidebar.
    struct GhostState {
        /// Position the drag originated from (includes collection and local index)
        let originPosition: ItemPosition
        /// All item frames at moment of handoff (for animation continuity)
        let originalFrames: [UUID: CGRect]
        /// Main dragged item (the one grabbed by cursor)
        let draggedItems: [DraggedItem]
        /// Follower items in multi-selection drag (repositioned after main on commit)
        let followerItems: [DraggedItem]
        /// IDs of followers hidden during drag
        let hiddenFollowerIDs: Set<UUID>
        /// Original overlay mode before handoff
        let overlayMode: OverlayMode
        /// Original overlay position at handoff
        let overlayPosition: CGPoint
        /// Current drag offset at handoff (for consistent target detection on re-entry)
        let currentOffset: CGFloat
        /// Original frame of dragged item (for offset calculations)
        let draggedItemOriginalFrame: CGRect?
    }

    // MARK: - State Capture

    /// Capture current coordinator state for AppKit handoff.
    ///
    /// Call this before transitioning to `.external` phase. The captured state
    /// enables seamless re-entry if the user drags back into the sidebar.
    ///
    /// - Returns: Captured ghost state, or nil if not currently dragging
    func captureGhostState() -> GhostState? {
        guard !draggedItems.isEmpty,
              let originPosition = _originPosition else {
            return nil
        }

        // Capture current frames from FrameRegistry
        var frames: [UUID: CGRect] = [:]
        for (id, _) in layoutManager.metadata {
            if let frame = frameRegistry.frame(for: id) {
                frames[id] = frame
            }
        }

        return GhostState(
            originPosition: originPosition,
            originalFrames: frames,
            draggedItems: draggedItems,
            followerItems: followerItems,
            hiddenFollowerIDs: hiddenFollowerIDs,
            overlayMode: currentOverlayMode,
            overlayPosition: overlayPosition,
            currentOffset: currentOffset,
            draggedItemOriginalFrame: _draggedItemOriginalFrame,
        )
    }

    /// Restore coordinator state from ghost state on re-entry.
    ///
    /// Call this when an AppKit drag re-enters the sidebar. Restores internal
    /// state so the SwiftUI overlay can resume tracking.
    ///
    /// - Parameter ghost: Previously captured ghost state
    func restoreFromGhostState(_ ghost: GhostState) {
        draggedItems = ghost.draggedItems
        followerItems = ghost.followerItems
        hiddenFollowerIDs = ghost.hiddenFollowerIDs
        _originPosition = ghost.originPosition
        currentOverlayMode = ghost.overlayMode
        overlayPosition = ghost.overlayPosition
        overlayMorphProgress = 1.0
        _draggedItemOriginalFrame = ghost.draggedItemOriginalFrame

        // Rebuild caches for the restored drag
        if !draggedItems.isEmpty {
            isDragging = true
            buildDescendantsCache()
            // Build exclusion set for main item + followers
            buildExclusionSetForMainItem()
        }
    }

    // MARK: - Handoff Helpers

    /// Check if the cursor has exited the sidebar bounds.
    ///
    /// Used to detect when to initiate AppKit handoff. Uses the authoritative
    /// `sidebarBounds` property which is updated via geometry preference from
    /// the Sidebar container, ensuring it stays current during scroll, filter
    /// changes, and layout animations.
    ///
    /// - Parameter cursorPosition: Cursor position in sidebar coordinate space
    /// - Returns: True if cursor is outside the sidebar
    func cursorIsOutsideSidebar(at cursorPosition: CGPoint) -> Bool {
        // Use authoritative sidebar bounds if available, otherwise fall back to union
        let bounds: CGRect = if !sidebarBounds.isEmpty {
            sidebarBounds
        } else {
            // Fallback for initialization - union computed section frames
            favoritesGridFrame
                .union(computedPinnedSectionFrame)
                .union(computedNormalSectionFrame)
        }

        // Add margin to prevent jitter at edges and handle boundary conditions.
        // Use -8 to ensure drag locations at exactly the content boundary are still
        // considered "inside" (CGRect.contains uses strict inequality for upper bound).
        let expandedBounds = bounds.insetBy(dx: -8, dy: -8)

        let isOutside = !expandedBounds.contains(cursorPosition)

        return isOutside
    }

    // MARK: - Handoff Execution

    /// Initiate AppKit drag session handoff.
    ///
    /// Called when the cursor exits the sidebar during a SwiftUI drag. This method:
    /// 1. Sets phase to `.transitioning`
    /// 2. Captures ghost state for potential re-entry
    /// 3. Renders the current overlay as a drag image
    /// 4. Initiates an AppKit drag session
    ///
    /// App shortcuts cannot be handed off (they're internal-only features).
    ///
    /// The actual transition to `.external` phase happens in the `willBeginAt`
    /// callback from AppKit, which fires after the next runloop iteration.
    ///
    /// - Returns: True if handoff was initiated, false if not possible
    @discardableResult
    func beginAppKitHandoff() -> Bool {
        guard !draggedItems.isEmpty,
              let dragSourceView,
              handoffPhase == .internal else {
            return false
        }

        // App shortcuts are internal-only (Downloads, History, etc.) - block handoff
        if let favorite = primaryDraggedItem?.favorite,
           case .appShortcut = favorite.type {
            return false
        }

        // Set transitioning phase
        handoffPhase = .transitioning

        // Capture ghost state before we modify anything
        ghostState = captureGhostState()

        // Render the current overlay as an image
        guard let dragImage = DragImageRenderer.renderCurrentOverlay(from: self) else {
            // Failed to render - revert to internal
            handoffPhase = .internal
            ghostState = nil
            return false
        }

        // Calculate frame for the drag image (overlay position is center-anchored)
        let size = overlayTargetSize
        let frame = CGRect(
            x: overlayPosition.x - size.width / 2,
            y: overlayPosition.y - size.height / 2,
            width: size.width,
            height: size.height,
        )

        // Initiate the AppKit drag session
        // Note: The drag won't visually start until the next runloop iteration
        dragSourceView.beginAppKitDrag(
            items: draggedItems,
            image: dragImage,
            frame: frame,
        )

        return true
    }
}
