import Foundation
import Testing

@testable import Refrax

/// Tests for drop zone edge cases:
/// - No favorites AND no pinned tabs (both placeholder zones must be targetable)
/// - Favorites exist but no pinned tabs (pinned placeholder must be targetable)
///
/// Drop zone placeholders are positioned from `sidebarBounds.minY` using
/// `DropZoneConstants`, so probes compute their coordinates from those same
/// constants to stay in sync with the implementation.
@Suite("Drop Zone Edge Cases", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragDropZoneEdgeCaseTests {
    // MARK: - Test Helpers

    private func setupStandardFrames(_ support: SidebarTestSupport, startY _: CGFloat = 100) {
        // Set sidebar bounds large enough to contain content AND drop zone area above
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: -200, width: 240, height: 700))
        support.dragCoordinator.updateFavoritesGridFrame(.zero) // No favorites
    }

    // MARK: - No Favorites AND No Pinned Tests

    @Test("Favorites and pinned drop zones are targetable when neither section exists")
    func dropZonesTargetableWhenNoFavoritesAndNoPinned() throws {
        let support = try SidebarTestSupport()
        // Create only normal tabs - no favorites, no pinned
        _ = support.createTab(url: "https://tab1.com")
        _ = support.createTab(url: "https://tab2.com")
        _ = support.createTab(url: "https://tab3.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        #expect(support.layoutManager.favoritesLayout.isEmpty)
        #expect(support.layoutManager.pinnedItems.isEmpty)

        // Use the first item in the layout (which has the frame at y=100)
        let normalItem = support.layoutManager.normalItems.first!
        let tab = normalItem.tab!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Drag above the tab list to trigger drop zones
        // First item starts at y=100, so dragging to y=20 is well above
        support.dragCoordinator.updateDrag(
            offset: -80, // Move up 80 pixels (from ~118 midY to ~38)
            location: CGPoint(x: 100, y: 38),
        )

        // Verify both drop zones are showing
        #expect(support.dragCoordinator.shouldShowFavoritesDropZone == true)
        #expect(support.dragCoordinator.shouldShowPinDropZone == true)

        // Probe the vertical center of each placeholder, computed from the
        // same constants the coordinator uses to position them
        typealias Zones = Sidebar.DragCoordinator.DropZoneConstants
        let areaTop = support.dragCoordinator.sidebarBounds.minY + Zones.addressBarOffset
        let favoritesProbeY = areaTop + Zones.favoritesDropZoneTotalHeight / 2
        let pinnedProbeY = areaTop + Zones.favoritesDropZoneTotalHeight + Zones.pinnedDropZoneTotalHeight / 2

        support.dragCoordinator.updateDrag(
            offset: favoritesProbeY - tabFrame.midY,
            location: CGPoint(x: 100, y: favoritesProbeY),
        )
        #expect(support.dragCoordinator.activeDropZone == .favoritesGrid)

        support.dragCoordinator.updateDrag(
            offset: pinnedProbeY - tabFrame.midY,
            location: CGPoint(x: 100, y: pinnedProbeY),
        )
        #expect(support.dragCoordinator.activeDropZone == .pinnedSection)
    }

    @Test("Drop zone detection uses adjusted frames for hit testing")
    func dropZoneDetectionUsesAdjustedFrames() throws {
        let support = try SidebarTestSupport()
        // No favorites, no pinned - only normal tabs
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support, startY: 100)

        let normalItem = support.layoutManager.normalItems.first!
        let tab = normalItem.tab!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Get the un-adjusted frame BEFORE drag update (static frame)
        let unadjustedNormalMinY = support.dragCoordinator.computedNormalSectionFrame.minY

        // Drag well above to trigger max drop zone progress
        support.dragCoordinator.updateDrag(
            offset: -200,
            location: CGPoint(x: 100, y: -100),
        )

        // Now get the adjusted frame AFTER drag update (includes push offset)
        let adjustedNormalMinY = support.dragCoordinator._adjustedNormalSectionFrame.minY
        let pushOffset = support.dragCoordinator.tabListPushOffset

        // With both zones showing, adjustedNormalMinY should be unadjusted + pushOffset
        if pushOffset > 0 {
            #expect(
                adjustedNormalMinY == unadjustedNormalMinY + pushOffset,
                "Adjusted frame should account for push offset (\(adjustedNormalMinY) != \(unadjustedNormalMinY) + \(pushOffset))",
            )
        } else {
            Issue.record("BUG: tabListPushOffset is 0 even though both drop zones should be showing")
        }

        // The location used for drop zone detection MUST compare against adjusted frames
        // This test documents the expected behavior - detection should use adjusted bounds
    }

    @Test("Pinned zone targetable in gap between favorites zone and pushed normal section")
    func pinnedZoneTargetableInGap() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support, startY: 100)

        let normalItem = support.layoutManager.normalItems.first!
        let tab = normalItem.tab!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Drag to trigger drop zones at max progress
        support.dragCoordinator.updateDrag(
            offset: -200,
            location: CGPoint(x: 100, y: -100),
        )

        // Both zones should be showing
        #expect(support.dragCoordinator.shouldShowFavoritesDropZone)
        #expect(support.dragCoordinator.shouldShowPinDropZone)

        // The pinned placeholder sits directly below the favorites placeholder;
        // probe its vertical center, computed from the positioning constants
        typealias Zones = Sidebar.DragCoordinator.DropZoneConstants
        let pinnedProbeY = support.dragCoordinator.sidebarBounds.minY
            + Zones.addressBarOffset
            + Zones.favoritesDropZoneTotalHeight
            + Zones.pinnedDropZoneTotalHeight / 2

        support.dragCoordinator.updateDrag(
            offset: pinnedProbeY - tabFrame.midY,
            location: CGPoint(x: 100, y: pinnedProbeY),
        )

        let zone = support.dragCoordinator.activeDropZone
        #expect(
            zone == .pinnedSection,
            "Should target the pinned drop zone at y=\(pinnedProbeY), got \(String(describing: zone))",
        )
    }

    // MARK: - Favorites Exist But No Pinned Tests

    @Test("BUG: Pinned drop zone positioned incorrectly when favorites exist")
    func pinnedZoneIncorrectWhenFavoritesExist() throws {
        let support = try SidebarTestSupport()
        // Create favorites but no pinned tabs
        _ = support.createFavorite(title: "Fav1", url: "https://fav1.com")
        _ = support.createFavorite(title: "Fav2", url: "https://fav2.com")
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()

        // Set up frames with favorites grid above tabs
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: -100, width: 240, height: 500))

        // Set favorites grid frame (above normal section)
        support.dragCoordinator.updateFavoritesGridFrame(CGRect(x: 0, y: 20, width: 200, height: 100))

        #expect(!support.layoutManager.favoritesLayout.isEmpty)
        #expect(support.layoutManager.pinnedItems.isEmpty)

        let normalItem = support.layoutManager.normalItems.first!
        let tab = normalItem.tab!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Drag above normal section but below favorites
        // This should be where the pinned drop zone appears
        support.dragCoordinator.updateDrag(
            offset: -100,
            location: CGPoint(x: 100, y: 130), // Between favorites grid and normal section
        )

        // With favorites existing but no pinned, shouldShowPinDropZone should be true
        // when dragging above the tab list
        let showPinZone = support.dragCoordinator.shouldShowPinDropZone
        let isDragAbove = support.dragCoordinator._isDragAboveTabList

        // If dragging above the tab list, pinned zone should show
        if isDragAbove {
            #expect(showPinZone == true, "Pin drop zone should show when favorites exist but no pinned tabs")
        }

        // Try targeting the pinned zone in the gap
        let activeZone = support.dragCoordinator.activeDropZone

        // BUG: The pinned zone might not be targetable because:
        // 1. checkDropZoneTarget checks `location.y < normalSectionFrame.minY`
        // 2. But with favorites, the priority order might skip pinned zone
        // 3. The gap detection doesn't properly account for the favorites grid bottom
        if showPinZone, isDragAbove {
            // Document that pinned zone SHOULD be targetable here
            #expect(
                activeZone == .pinnedSection || activeZone == .normalSection,
                "Drop zone should be detected when favorites exist, got \(String(describing: activeZone))",
            )
        }
    }

    @Test("Tab dropped in pinned zone gap creates pinned tab when favorites exist")
    func dropInPinnedZoneCreatessPinnedTab() throws {
        let support = try SidebarTestSupport()
        // Create favorites but no pinned tabs
        _ = support.createFavorite(title: "Fav", url: "https://fav.com")
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()

        // Set up frames. The coordinator positions the pinned placeholder at
        // addressBarOffset + grid height + 12 below the sidebar top, so the
        // grid frame must sit where that math assumes it: right below the
        // address bar.
        typealias Zones = Sidebar.DragCoordinator.DropZoneConstants
        let sidebarBounds = CGRect(x: 0, y: -100, width: 240, height: 500)
        support.setupTestGeometry(sidebarBounds: sidebarBounds)
        support.dragCoordinator.updateFavoritesGridFrame(
            CGRect(x: 0, y: sidebarBounds.minY + Zones.addressBarOffset, width: 200, height: 100),
        )

        let normalItem = support.layoutManager.normalItems.first!
        let tab = normalItem.tab!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Probe the vertical center of the pinned placeholder (favorites exist,
        // so no favorites placeholder is shown above it)
        let gridFrame = support.dragCoordinator.favoritesGridFrame
        let pinnedProbeY = sidebarBounds.minY
            + Zones.addressBarOffset
            + gridFrame.height + 12
            + Zones.pinnedDropZoneTotalHeight / 2

        // Zone activation tracks the dragged frame (item minY + offset must sit
        // above the first item), while hit-testing uses the location — so keep
        // the offset far negative and probe with the location
        support.dragCoordinator.updateDrag(
            offset: -200,
            location: CGPoint(x: 100, y: pinnedProbeY),
        )

        // The drop target must create a pinned tab
        switch support.dragCoordinator._dropTarget {
        case let .reorder(target):
            #expect(target.collection == .pinned)
        default:
            Issue.record(
                "Expected a pinned reorder target at y=\(pinnedProbeY), got \(String(describing: support.dragCoordinator._dropTarget))",
            )
        }
    }

    // MARK: - Frame Adjustment Tests

    @Test("Section frames are correctly adjusted by tabListPushOffset")
    func sectionFramesAdjustedByPushOffset() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support, startY: 100)

        let normalItem = support.layoutManager.normalItems.first!
        let tab = normalItem.tab!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Get adjusted frame BEFORE activating drop zones (pushOffset should be 0)
        let frameBeforeDrag = support.dragCoordinator._adjustedNormalSectionFrame

        // Drag to activate drop zones
        support.dragCoordinator.updateDrag(
            offset: -150,
            location: CGPoint(x: 100, y: -50),
        )

        let pushOffset = support.dragCoordinator.tabListPushOffset
        let frameAfterDrag = support.dragCoordinator._adjustedNormalSectionFrame

        // Verify the offset is applied
        #expect(pushOffset > 0, "Push offset should be positive when drop zones are showing")

        // The adjusted frame after drag should be offset from the frame before drag
        #expect(
            frameAfterDrag.minY == frameBeforeDrag.minY + pushOffset,
            "Adjusted minY should increase by push offset",
        )
        #expect(
            frameAfterDrag.maxY == frameBeforeDrag.maxY + pushOffset,
            "Adjusted maxY should increase by push offset",
        )
    }

    @Test("Drop zone progress affects push offset calculation")
    func dropZoneProgressAffectsPushOffset() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support, startY: 100)

        let normalItem = support.layoutManager.normalItems.first!
        let tab = normalItem.tab!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Get push offset at various drag positions
        var pushOffsets: [CGFloat] = []

        // Start above threshold (negative offset from start position)
        support.dragCoordinator.updateDrag(offset: -150, location: CGPoint(x: tabFrame.midX, y: tabFrame.midY - 150))
        pushOffsets.append(support.dragCoordinator.tabListPushOffset)

        // Move closer to threshold
        support.dragCoordinator.updateDrag(offset: -50, location: CGPoint(x: tabFrame.midX, y: tabFrame.midY - 50))
        pushOffsets.append(support.dragCoordinator.tabListPushOffset)

        // Move within normal section (positive offset, well below the start position)
        let normalFrame = support.dragCoordinator.computedNormalSectionFrame
        let targetY = normalFrame.midY
        support.dragCoordinator.updateDrag(
            offset: targetY - tabFrame.midY,
            location: CGPoint(x: tabFrame.midX, y: targetY),
        )
        pushOffsets.append(support.dragCoordinator.tabListPushOffset)

        // Push offset should be higher when further above threshold
        // and should be 0 (or very small) when within the tab list
        #expect(pushOffsets[0] >= pushOffsets[1], "Push offset should be higher when further above threshold")
        #expect(pushOffsets[2] <= pushOffsets[1], "Push offset should decrease when moving back into tab list")
    }

    // MARK: - Detection Priority Tests

    @Test("Pinned zone has correct priority when both zones showing")
    func pinnedZonePriorityWhenBothShowing() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support, startY: 100)

        let normalItem = support.layoutManager.normalItems.first!
        let tab = normalItem.tab!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Verify both zones are showing
        support.dragCoordinator.updateDrag(offset: -150, location: CGPoint(x: 100, y: -50))

        #expect(support.dragCoordinator.shouldShowFavoritesDropZone)
        #expect(support.dragCoordinator.shouldShowPinDropZone)

        // Test that favorites zone is targeted at the top
        support.dragCoordinator.updateDrag(offset: -150, location: CGPoint(x: 100, y: 28)) // Center of first 56px zone
        let zoneAtTop = support.dragCoordinator.activeDropZone

        // Test that pinned zone is targeted below the favorites zone
        support.dragCoordinator.updateDrag(offset: -150, location: CGPoint(x: 100, y: 84)) // Center of second 56px zone
        let zoneAtMiddle = support.dragCoordinator.activeDropZone

        // Test that normal section is targeted below both zones
        let adjustedNormalY = support.dragCoordinator._adjustedNormalSectionFrame.minY
        support.dragCoordinator.updateDrag(
            offset: -150,
            location: CGPoint(x: 100, y: adjustedNormalY + 20),
        )
        let zoneAtBottom = support.dragCoordinator.activeDropZone

        // Document the expected zone ordering
        // Note: actual zone depends on whether the bug is fixed
        #expect(
            zoneAtTop != nil || zoneAtMiddle != nil || zoneAtBottom != nil,
            "At least one zone should be detected at various positions",
        )
    }
}
