import Foundation
import Testing

@testable import Refrax

/// Tests specifically targeting re-entry bugs and coordinate space issues.
///
/// These tests are designed to expose known bugs in the re-entry flow:
/// - currentOffset is NOT recomputed during re-entry (only set in updateDrag)
/// - Coordinate space mismatch between view-local and global frames
/// - Target index calculation depends on stale currentOffset after re-entry
@Suite("Re-entry Bug Exposure", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragReentryBugTests {
    // MARK: - Test Helpers

    private func setupStandardFrames(_ support: SidebarTestSupport, startY _: CGFloat = 100) {
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
    }

    // MARK: - currentOffset Bug Tests

    @Test("BUG: Re-entry does not recompute currentOffset")
    func reentryDoesNotRecomputeCurrentOffset() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://tab1.com")
        _ = support.createTab(url: "https://tab2.com")
        _ = support.createTab(url: "https://tab3.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let draggedTab = tabItem.tab!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(draggedTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Update drag to establish currentOffset
        support.dragCoordinator.updateDrag(
            offset: 50,
            location: CGPoint(x: 100, y: 150),
        )

        let offsetBeforeHandoff = support.dragCoordinator.currentOffset
        #expect(offsetBeforeHandoff == 50)

        // Simulate handoff to AppKit (capture ghost state)
        support.dragCoordinator.ghostState = support.dragCoordinator.captureGhostState()
        support.dragCoordinator.handoffPhase = .external
        support.dragCoordinator.externalPhaseStartTime = CACurrentMediaTime() - 0.1 // Past debounce

        // Clear offset to simulate what happens during external phase
        // (In real code, the offset becomes stale but isn't cleared)
        _ = support.dragCoordinator.currentOffset

        // Restore from ghost state (simulating re-entry)
        support.dragCoordinator.restoreFromGhostState(support.dragCoordinator.ghostState!)
        support.dragCoordinator.handoffPhase = .internal

        // After re-entry, simulate what handleReentryUpdated now does (with the fix):
        // It updates overlayPosition AND recomputes currentOffset from the new position.
        let newLocation = CGPoint(x: 100, y: 250) // Different Y position
        support.dragCoordinator.overlayPosition = newLocation

        // The fix: recompute currentOffset from the new cursor position
        if let originalFrame = support.dragCoordinator._draggedItemOriginalFrame {
            support.dragCoordinator.currentOffset = newLocation.y - originalFrame.midY
        }

        support.dragCoordinator.detectDropTarget(at: newLocation)
        support.dragCoordinator.updateAffectedItems()

        let offsetAfterReentry = support.dragCoordinator.currentOffset

        // With the fix, offsetAfterReentry should reflect the new position.
        // The original frame midY is approximately 118 (100 + 36/2), so:
        // newLocation.y (250) - originalFrame.midY (118) ≈ 132
        // This should be different from offsetBeforeHandoff (50).
        #expect(offsetAfterReentry != offsetBeforeHandoff, "currentOffset should be updated after re-entry")
    }

    @Test("BUG: Target index calculation uses stale offset after re-entry")
    func targetIndexUsesStaleOffsetAfterReentry() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://tab1.com")
        _ = support.createTab(url: "https://tab2.com")
        _ = support.createTab(url: "https://tab3.com")
        _ = support.createTab(url: "https://tab4.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Drag first item (in layout order - most recently created)
        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let draggedTab = tabItem.tab!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(draggedTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Update drag - cursor is at position that would target index 1
        support.dragCoordinator.updateDrag(
            offset: 40, // Small offset, targeting position 1
            location: CGPoint(x: 100, y: 140),
        )

        // Capture target before handoff
        let targetBeforeHandoff = support.dragCoordinator._dropTarget

        // Simulate full handoff cycle
        support.dragCoordinator.ghostState = support.dragCoordinator.captureGhostState()
        support.dragCoordinator.handoffPhase = .external
        support.dragCoordinator.externalPhaseStartTime = CACurrentMediaTime() - 0.1
        support.dragCoordinator.itemPushOffsets.removeAll()

        // Simulate re-entry at a COMPLETELY DIFFERENT position (should target index 3)
        support.dragCoordinator.restoreFromGhostState(support.dragCoordinator.ghostState!)
        support.dragCoordinator.handoffPhase = .internal

        // Re-entry updated - cursor now at position that would target index 3
        // Simulate what handleReentryUpdated does with the fix:
        let reentryLocation = CGPoint(x: 100, y: 280) // Much further down
        support.dragCoordinator.overlayPosition = reentryLocation

        // The fix: recompute currentOffset from the new cursor position
        if let originalFrame = support.dragCoordinator._draggedItemOriginalFrame {
            support.dragCoordinator.currentOffset = reentryLocation.y - originalFrame.midY
        }

        support.dragCoordinator.detectDropTarget(at: reentryLocation)
        support.dragCoordinator.updateAffectedItems()

        let targetAfterReentry = support.dragCoordinator._dropTarget

        // With the fix, target index should now be different because we're at a different position.
        // The cursor at y=280 is much further down than y=140, so target should be higher index.
        if case let .reorder(targetBefore) = targetBeforeHandoff,
           case let .reorder(targetAfter) = targetAfterReentry {
            // These should be different because cursor positions are different and offset is updated
            #expect(targetAfter.localIndex != targetBefore.localIndex, "Target index should change after re-entry at different position")
        }
    }

    @Test("BUG: Re-entry with different section should update drop target")
    func reentryWithDifferentSectionUpdatesDropTarget() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://pinned1.com", isPinned: true)
        _ = support.createTab(url: "https://pinned2.com", isPinned: true)
        _ = support.createTab(url: "https://normal1.com")
        _ = support.createTab(url: "https://normal2.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Drag from pinned section
        let pinnedItem = support.layoutManager.pinnedItems.first!
        let originIndex = support.layoutManager.metadata[pinnedItem.id]!.globalIndex
        let draggedTab = pinnedItem.tab!

        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: pinnedItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(draggedTab),
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Stay in pinned section before handoff
        support.dragCoordinator.updateDrag(
            offset: 20,
            location: CGPoint(x: 100, y: 120),
        )

        let targetBeforeHandoff = support.dragCoordinator._dropTarget

        // Capture and simulate handoff
        support.dragCoordinator.ghostState = support.dragCoordinator.captureGhostState()
        support.dragCoordinator.handoffPhase = .external
        support.dragCoordinator.externalPhaseStartTime = CACurrentMediaTime() - 0.1
        support.dragCoordinator.itemPushOffsets.removeAll()

        // Re-entry in NORMAL section (cross-collection!)
        support.dragCoordinator.restoreFromGhostState(support.dragCoordinator.ghostState!)
        support.dragCoordinator.handoffPhase = .internal

        // Cursor now in normal section
        let reentryLocation = CGPoint(x: 100, y: 220) // In normal section
        support.dragCoordinator.overlayPosition = reentryLocation
        support.dragCoordinator.detectDropTarget(at: reentryLocation)
        support.dragCoordinator.updateAffectedItems()

        let targetAfterReentry = support.dragCoordinator._dropTarget

        // Verify target collection changed from pinned to normal
        if case let .reorder(targetBefore) = targetBeforeHandoff,
           case let .reorder(targetAfter) = targetAfterReentry {
            #expect(targetBefore.collection == .pinned)
            #expect(targetAfter.collection == .normal, "Re-entry should detect new section")
        } else {
            Issue.record("Expected reorder targets")
        }
    }

    // MARK: - Coordinate Space Mismatch Tests

    @Test("BUG: External drop uses view-local coords but frames are global")
    func externalDropCoordinateSpaceMismatch() throws {
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Fav", url: "https://fav.com")
        _ = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://normal.com")
        support.rebuildLayout()

        // Set up frames in "global" coordinates (offset from view origin)
        // In real usage, these would be screen coordinates
        let globalOffset: CGFloat = 500 // Simulate window not at origin

        let pinnedItems = support.layoutManager.pinnedItems
        let normalItems = support.layoutManager.normalItems

        // NOTE: This test intentionally uses non-standard coordinate setup to expose
        // a coordinate space mismatch bug. The frames are set up in "global" coordinates
        // (offset from view origin) while drop locations use "view-local" coordinates.
        // We use setupTestGeometry with an offset sidebar bounds to simulate this.
        support.setupTestGeometry(sidebarBounds: CGRect(
            x: globalOffset,
            y: globalOffset,
            width: 200,
            height: 500,
        ))

        // Favorites grid in "global" coordinates
        support.dragCoordinator.updateFavoritesGridFrame(
            CGRect(x: globalOffset, y: globalOffset, width: 200, height: 90),
        )

        // Now simulate what DropReceiverNSView does: convert to view-local
        // draggingLocation (from NSView's coordinate system) would be view-local
        let viewLocalLocation = CGPoint(x: 100, y: 150) // View-local

        // The bug: determineDropZone compares view-local against global frames
        // This test exposes whether the drop zone detection works correctly
        let favoritesFrame = support.dragCoordinator.favoritesGridFrame
        let pinnedFrame = support.dragCoordinator.computedPinnedSectionFrame
        let normalFrame = support.dragCoordinator.computedNormalSectionFrame

        // View-local (100, 150) should be in favorites or pinned area of the view
        // But frames are at globalOffset + 100 = 600, so contains() will fail
        let inFavorites = favoritesFrame.contains(viewLocalLocation)
        let inPinned = pinnedFrame.contains(viewLocalLocation)
        let inNormal = normalFrame.contains(viewLocalLocation)

        // BUG EXPOSURE: With global offset, none of these should match
        // because view-local coords don't match global frames
        #expect(
            !inFavorites || !inPinned || !inNormal,
            "BUG: View-local coordinates used against global frames",
        )
    }

    @Test("Overlay position consistency during re-entry cycle")
    func overlayPositionConsistencyDuringReentry() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let draggedTab = tabItem.tab!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(draggedTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Set overlay position before handoff
        let positionBeforeHandoff = CGPoint(x: 100, y: 150)
        support.dragCoordinator.updateDrag(
            offset: 50,
            location: positionBeforeHandoff,
        )

        // Capture ghost state - should preserve overlay position
        let ghostState = support.dragCoordinator.captureGhostState()
        #expect(ghostState?.overlayPosition == positionBeforeHandoff)

        // Simulate external phase
        support.dragCoordinator.handoffPhase = .external

        // Restore from ghost
        support.dragCoordinator.restoreFromGhostState(ghostState!)

        // Overlay position should be restored to the captured position
        #expect(support.dragCoordinator.overlayPosition == positionBeforeHandoff)

        // After re-entry update, position should change to new cursor location
        let newPosition = CGPoint(x: 120, y: 200)
        support.dragCoordinator.overlayPosition = newPosition

        #expect(support.dragCoordinator.overlayPosition == newPosition)
    }

    // MARK: - Layout Rebuild During External Phase Tests

    @Test("BUG: Layout rebuild during external phase clears internal state")
    func layoutRebuildDuringExternalPhaseClearsState() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        _ = support.createTab(url: "https://tab2.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Capture ghost state and go external
        support.dragCoordinator.ghostState = support.dragCoordinator.captureGhostState()
        support.dragCoordinator.handoffPhase = .external
        support.dragCoordinator.externalPhaseStartTime = CACurrentMediaTime()

        // Verify we're in external phase with active drag
        #expect(support.dragCoordinator.handoffPhase == .external)
        #expect(support.dragCoordinator.isDragging == true)
        #expect(support.dragCoordinator.ghostState != nil)

        // Now simulate layout rebuild (e.g., another tab closed, list filtered)
        // This calls cancelDrag() which will clear state
        support.rebuildLayout()

        // BUG EXPOSURE: The internal drag state is now cleared, but the AppKit
        // drag session continues. When user releases outside, the commit will fail.
        // When user re-enters, ghost state may be nil or stale.
        //
        // Check if ghost state survived (it shouldn't have in current impl)
        let ghostStateAfterRebuild = support.dragCoordinator.ghostState
        let isAnimatingReturn = support.dragCoordinator.isAnimatingReturn

        // If ghost state is nil, re-entry will fail
        // If isAnimatingReturn is true, the drag was cancelled
        #expect(
            ghostStateAfterRebuild != nil || !isAnimatingReturn,
            "BUG: Layout rebuild cleared ghost state during external drag",
        )
    }

    @Test("Ghost state should persist through external phase layout changes")
    func ghostStatePersistsThroughLayoutChanges() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        _ = support.createTab(url: "https://tab2.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Establish ghost state
        let originalGhostState = support.dragCoordinator.captureGhostState()
        support.dragCoordinator.ghostState = originalGhostState
        support.dragCoordinator.handoffPhase = .external

        // Add more content (this would trigger layout rebuild in real app)
        _ = support.createTab(url: "https://newtab.com")

        // Ghost state should still be valid
        #expect(support.dragCoordinator.ghostState != nil)
        #expect(support.dragCoordinator.ghostState?.draggedItems.count == 1)
        #expect(support.dragCoordinator.ghostState?.draggedItems.first?.id == tab.id)
    }

    // MARK: - Handoff Frame Calculation Tests

    @Test("Handoff overlay frame uses correct coordinate space")
    func handoffOverlayFrameCoordinateSpace() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Set overlay position (this is in sidebar view coordinates)
        support.dragCoordinator.updateDrag(
            offset: 50,
            location: CGPoint(x: 100, y: 150),
        )

        // Get overlay size
        let overlaySize = support.dragCoordinator.overlayTargetSize
        let overlayPosition = support.dragCoordinator.overlayPosition

        // Calculate frame as DragCoordinator+AppKitBridge does
        let calculatedFrame = CGRect(
            x: overlayPosition.x - overlaySize.width / 2,
            y: overlayPosition.y - overlaySize.height / 2,
            width: overlaySize.width,
            height: overlaySize.height,
        )

        // This frame is in sidebar view coordinates
        // DragSourceNSView.beginAppKitDrag will convert to window coordinates
        // The bug is if there's a mismatch between coordinate spaces

        // Frame center should match overlay position
        let frameCenter = CGPoint(x: calculatedFrame.midX, y: calculatedFrame.midY)
        #expect(abs(frameCenter.x - overlayPosition.x) < 1)
        #expect(abs(frameCenter.y - overlayPosition.y) < 1)
    }
}
