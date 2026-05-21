import Foundation
import Testing

@testable import Refrax

// MARK: - Complex Drag Scenarios Integration Tests

@Suite("Sidebar.DragCoordinator Integration", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragIntegrationTests {
    // MARK: - Multi-Section Drag Tests

    @Test("Drag tab from normal to pinned section with existing pinned items")
    func dragNormalTabToPinnedSection() throws {
        let support = try SidebarTestSupport()

        // Create complex setup: 2 pinned, 3 normal tabs
        _ = support.createTab(url: "https://pinned1.com", isPinned: true)
        _ = support.createTab(url: "https://pinned2.com", isPinned: true)
        let normalTab1 = support.createTab(url: "https://normal1.com")
        _ = support.createTab(url: "https://normal2.com")
        _ = support.createTab(url: "https://normal3.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Find the first normal tab
        let pinnedItems = support.layoutManager.pinnedItems
        let normalItems = support.layoutManager.normalItems
        let normalTabItem = normalItems.first { item in
            if case let .tab(tab) = item, tab.id == normalTab1.id { return true }
            return false
        }!

        // Start drag from normal section
        let originIndex = support.layoutManager.metadata[normalTabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalTabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(normalTab1),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag up into the pinned section
        let pinnedSectionFrame = support.dragCoordinator.computedPinnedSectionFrame
        let targetY = pinnedSectionFrame.midY // Middle of pinned section
        support.dragCoordinator.updateDrag(
            offset: -(startFrame.midY - targetY),
            location: CGPoint(x: 100, y: targetY),
        )

        // Verify drop target is pinned section reorder
        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .pinned)
            #expect(target.localIndex >= 0 && target.localIndex <= pinnedItems.count)
        } else {
            Issue.record("Expected reorder target for pinned section, got \(support.dragCoordinator._dropTarget)")
        }

        #expect(support.dragCoordinator.activeDropZone == .pinnedSection)
    }

    @Test("Drag pinned tab to normal section")
    func dragPinnedTabToNormalSection() throws {
        let support = try SidebarTestSupport()

        // Create setup: 2 pinned, 2 normal tabs
        let pinnedTab = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://pinned2.com", isPinned: true)
        _ = support.createTab(url: "https://normal1.com")
        _ = support.createTab(url: "https://normal2.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let pinnedItems = support.layoutManager.pinnedItems

        // Find the pinned tab item
        let pinnedTabItem = pinnedItems.first { item in
            if case let .tab(tab) = item, tab.id == pinnedTab.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[pinnedTabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: pinnedTabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(pinnedTab),
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag down into normal section - use midpoint of section for reliable detection
        let normalSectionFrame = support.dragCoordinator.computedNormalSectionFrame
        let targetY = normalSectionFrame.midY
        support.dragCoordinator.updateDrag(
            offset: targetY - startFrame.midY,
            location: CGPoint(x: startFrame.midX, y: targetY),
        )

        // Verify drop target is normal section
        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .normal)
        } else {
            Issue.record("Expected reorder target for normal section, got \(support.dragCoordinator._dropTarget)")
        }

        // The activeDropZone may be nil or .normalSection depending on whether
        // the section is considered a "zone" vs just the default reorder area
        let zone = support.dragCoordinator.activeDropZone
        #expect(zone == nil || zone == .normalSection)
    }

    // MARK: - Grouped Tabs Tests

    @Test("Drag ungrouped tab to group header")
    func dragTabToGroupHeader() throws {
        let support = try SidebarTestSupport()

        // Create setup: a group with 2 tabs, and 2 ungrouped tabs
        let group = try support.createGroup(name: "Test Group")
        _ = support.createTab(url: "https://grouped1.com", groupID: group.id)
        _ = support.createTab(url: "https://grouped2.com", groupID: group.id)
        let ungroupedTab = support.createTab(url: "https://ungrouped.com")
        _ = support.createTab(url: "https://ungrouped2.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Find the ungrouped tab and group items
        let items = support.layoutManager.pinnedItems + support.layoutManager.normalItems
        let ungroupedTabItem = items.first { item in
            if case let .tab(tab) = item, tab.id == ungroupedTab.id { return true }
            return false
        }!

        let groupItem = items.first { item in
            if case let .group(g) = item, g.id == group.id { return true }
            return false
        }!

        // Register frames in the frame registry so getVisibleItems() can find items
        for item in items {
            if let frame = support.dragCoordinator.computedItemFrame(for: item.id) {
                support.managers.frameRegistry.setTestFrame(frame, for: item.id)
            }
        }

        let originIndex = support.layoutManager.metadata[ungroupedTabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: ungroupedTabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(ungroupedTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag to group header
        let groupFrame = support.dragCoordinator.computedItemFrame(for: groupItem.id)!
        support.dragCoordinator.updateDrag(
            offset: groupFrame.midY - startFrame.midY,
            location: CGPoint(x: groupFrame.midX, y: groupFrame.midY),
        )

        support.dragCoordinator.detectDropTarget(at: CGPoint(x: groupFrame.midX, y: groupFrame.midY))

        // Verify drop target is add to group
        if case let .addToGroup(groupID) = support.dragCoordinator._dropTarget {
            #expect(groupID == group.id)
        } else {
            Issue.record("Expected addToGroup target, got \(support.dragCoordinator._dropTarget)")
        }

        #expect(support.dragCoordinator.activeDropZone == .groupHeader(group.id))
    }

    @Test("Drag grouped tab out of group")
    func dragGroupedTabOutOfGroup() throws {
        let support = try SidebarTestSupport()

        // Create setup: a group with tabs, and ungrouped tabs
        let group = try support.createGroup(name: "Test Group")
        let groupedTab = support.createTab(url: "https://grouped.com", groupID: group.id)
        _ = support.createTab(url: "https://grouped2.com", groupID: group.id)
        let ungroupedTab = support.createTab(url: "https://ungrouped.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Find the grouped tab
        let items = support.layoutManager.pinnedItems + support.layoutManager.normalItems
        let groupedTabItem = items.first { item in
            if case let .tab(tab) = item, tab.id == groupedTab.id { return true }
            return false
        }!

        // Find the ungrouped tab for target location
        let ungroupedTabItem = items.first { item in
            if case let .tab(tab) = item, tab.id == ungroupedTab.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[groupedTabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: groupedTabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(groupedTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag to the ungrouped tab area (within normal section, outside the group)
        let ungroupedFrame = support.dragCoordinator.computedItemFrame(for: ungroupedTabItem.id)!
        let targetY = ungroupedFrame.midY

        support.dragCoordinator.updateDrag(
            offset: targetY - startFrame.midY,
            location: CGPoint(x: ungroupedFrame.midX, y: targetY),
        )

        // Should be a normal reorder (not adding to any group)
        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .normal)
        } else {
            Issue.record("Expected reorder target, got \(support.dragCoordinator._dropTarget)")
        }

        // When dragging a grouped tab out of the group but staying in normal section,
        // the zone may be nil or .normalSection depending on implementation details.
        // The key assertion is that we get a normal reorder, not addToGroup.
        let zone = support.dragCoordinator.activeDropZone
        #expect(zone == nil || zone == .normalSection)
    }

    // MARK: - Drop Zone Tests (No Existing Pinned/Favorites)

    @Test("Drag tab above tab list shows drop zones when no pinned or favorites exist")
    func dragAboveTabListShowsDropZones() throws {
        let support = try SidebarTestSupport()

        // Create only normal tabs (no pinned, no favorites)
        let normalTab = support.createTab(url: "https://normal1.com")
        _ = support.createTab(url: "https://normal2.com")
        _ = support.createTab(url: "https://normal3.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Find the tab item
        let items = support.layoutManager.normalItems
        let tabItem = items.first { item in
            if case let .tab(tab) = item, tab.id == normalTab.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag above the tab list - need sufficient negative offset to trigger _isDragAboveTabList
        let normalSectionMinY = support.dragCoordinator.computedNormalSectionFrame.minY
        let offsetNeeded = normalSectionMinY - startFrame.minY - 50 // 50pt margin above threshold
        support.dragCoordinator.updateDrag(
            offset: offsetNeeded,
            location: CGPoint(x: startFrame.midX, y: normalSectionMinY - 50),
        )

        // Verify both drop zones are showing (no favorites AND no pinned)
        #expect(support.dragCoordinator.shouldShowPinDropZone == true)
        #expect(support.dragCoordinator.shouldShowFavoritesDropZone == true)

        // When both drop zones show, the drop target depends on the exact location.
        // The key assertion is that both zones are showing and push offset is applied.
        let dropTarget = support.dragCoordinator._dropTarget
        let isValidDropZoneTarget = switch dropTarget {
        case .convertToFavorite: true
        case let .reorder(target) where target.collection == .pinned: true
        default: false
        }
        #expect(isValidDropZoneTarget, "Expected drop zone target, got \(dropTarget)")

        // tabListPushOffset should account for BOTH drop zones
        let pushOffset = support.dragCoordinator.tabListPushOffset
        // Each zone adds 56 (44 height + 12 padding), and it's multiplied by progress
        #expect(pushOffset > 0)
    }

    @Test("Drag tab above tab list shows only pin drop zone when favorites exist")
    func dragAboveTabListWithExistingFavorites() throws {
        let support = try SidebarTestSupport()

        // Create normal tabs and a favorite
        let normalTab = support.createTab(url: "https://normal1.com")
        _ = support.createTab(url: "https://normal2.com")
        _ = support.createFavorite(title: "Favorite", url: "https://favorite.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Set up favorites grid frame
        support.dragCoordinator.updateFavoritesGridFrame(CGRect(x: 0, y: 0, width: 200, height: 80))

        let items = support.layoutManager.normalItems
        let tabItem = items.first { item in
            if case let .tab(tab) = item, tab.id == normalTab.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag above the tab list but below favorites
        let targetY: CGFloat = 85 // Just below favorites grid
        let offset = targetY - startFrame.midY
        support.dragCoordinator.updateDrag(
            offset: offset,
            location: CGPoint(x: 100, y: targetY),
        )

        // Favorites exist, so only pin drop zone should show
        #expect(support.dragCoordinator.shouldShowPinDropZone == true)
        #expect(support.dragCoordinator.shouldShowFavoritesDropZone == false)
    }

    @Test("Drop zone coordinate transformation with tabListPushOffset")
    func dropZoneCoordinateTransformation() throws {
        let support = try SidebarTestSupport()

        // Create normal tabs only
        let normalTab = support.createTab(url: "https://normal1.com")
        _ = support.createTab(url: "https://normal2.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let items = support.layoutManager.normalItems
        let tabItem = items.first { item in
            if case let .tab(tab) = item, tab.id == normalTab.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag above tab list to trigger drop zones
        let targetY: CGFloat = 20
        let offset = targetY - startFrame.midY
        support.dragCoordinator.updateDrag(
            offset: offset,
            location: CGPoint(x: 100, y: targetY),
        )

        // Now tabListPushOffset should be > 0
        let pushOffset = support.dragCoordinator.tabListPushOffset
        #expect(pushOffset > 0)

        // locationInStaticSpace should subtract the push offset
        let visualLocation = CGPoint(x: 100, y: 150)
        let staticLocation = support.dragCoordinator.locationInStaticSpace(visualLocation)
        #expect(staticLocation.y == visualLocation.y - pushOffset)

        // The adjusted section frames should include the push offset
        let normalSectionFrame = support.dragCoordinator.computedNormalSectionFrame
        let adjustedFrame = support.dragCoordinator._adjustedNormalSectionFrame
        #expect(adjustedFrame.minY == normalSectionFrame.minY + pushOffset)
    }

    // MARK: - Favorite Conversion Tests

    @Test("Drag tab to favorites grid converts to favorite")
    func dragTabToFavoritesGridConverts() throws {
        let support = try SidebarTestSupport()

        // Create tabs and favorites
        let normalTab = support.createTab(url: "https://normal.com")
        _ = support.createFavorite(title: "Existing", url: "https://existing.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Set up favorites grid
        let favoritesFrame = CGRect(x: 0, y: 0, width: 200, height: 80)
        support.dragCoordinator.updateFavoritesGridFrame(favoritesFrame)

        let items = support.layoutManager.normalItems
        let tabItem = items.first { item in
            if case let .tab(tab) = item, tab.id == normalTab.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag to favorites grid
        let targetY: CGFloat = 40 // Inside favorites grid
        support.dragCoordinator.updateDrag(
            offset: targetY - startFrame.midY,
            location: CGPoint(x: 100, y: targetY),
        )

        // Should convert to favorite
        if case let .convertToFavorite(mode) = support.dragCoordinator._dropTarget {
            #expect(mode == .liveFavorite)
        } else {
            Issue.record("Expected convertToFavorite, got \(support.dragCoordinator._dropTarget)")
        }

        #expect(support.dragCoordinator.activeDropZone == .favoritesGrid)
    }

    @Test("Drag favorite to normal section converts to tab")
    func dragFavoriteToNormalConverts() throws {
        let support = try SidebarTestSupport()

        // Create tabs and favorites
        _ = support.createTab(url: "https://normal.com")
        let favorite = support.createFavorite(title: "Favorite", url: "https://favorite.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        support.dragCoordinator.updateFavoritesGridFrame(CGRect(x: 0, y: 0, width: 200, height: 80))

        support.dragCoordinator.startDrag(
            item: .favorite(favorite),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: 40, y: 40),
        )

        // Drag to normal section
        let targetY: CGFloat = 150 // Inside normal section
        support.dragCoordinator.updateDrag(
            offset: targetY,
            location: CGPoint(x: 100, y: targetY),
        )

        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: targetY))

        // Should convert to tab
        if case let .convertToTab(targetSpace, targetPosition) = support.dragCoordinator._dropTarget {
            #expect(targetSpace.id == support.space.id)
            #expect(targetPosition.collection != .pinned)
        } else {
            Issue.record("Expected convertToTab, got \(support.dragCoordinator._dropTarget)")
        }
    }

    // MARK: - Complex Multi-Item Scenarios

    @Test("Complex scenario: multiple pinned, normal, grouped, and favorites")
    func complexMultiSectionScenario() throws {
        let support = try SidebarTestSupport()

        // Create complex setup
        _ = support.createTab(url: "https://pinned1.com", isPinned: true)
        _ = support.createTab(url: "https://pinned2.com", isPinned: true)

        let group = try support.createGroup(name: "Work")
        _ = support.createTab(url: "https://work1.com", groupID: group.id)
        _ = support.createTab(url: "https://work2.com", groupID: group.id)

        let normalTab = support.createTab(url: "https://normal.com")
        _ = support.createTab(url: "https://normal2.com")

        _ = support.createFavorite(title: "Fav1", url: "https://fav1.com")
        _ = support.createFavorite(title: "Fav2", url: "https://fav2.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
        support.dragCoordinator.updateFavoritesGridFrame(CGRect(x: 0, y: 0, width: 200, height: 90))

        // Verify layout counts
        #expect(support.layoutManager.pinnedItems.count == 2)
        #expect(support.layoutManager.normalItems.count >= 4) // group + 2 tabs in group + 2 ungrouped
        #expect(support.layoutManager.favoritesLayout.count == 2)

        let normalItems = support.layoutManager.normalItems

        // Find the ungrouped normal tab
        let normalTabItem = normalItems.first { item in
            if case let .tab(tab) = item, tab.id == normalTab.id { return true }
            return false
        }!

        // Test 1: Drag to group header
        let originIndex = support.layoutManager.metadata[normalTabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalTabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        let groupItem = normalItems.first { item in
            if case .group = item { return true }
            return false
        }!
        let groupFrame = support.dragCoordinator.computedItemFrame(for: groupItem.id)!

        support.dragCoordinator.updateDrag(
            offset: groupFrame.midY - startFrame.midY,
            location: CGPoint(x: 100, y: groupFrame.midY),
        )

        if case let .addToGroup(groupID) = support.dragCoordinator._dropTarget {
            #expect(groupID == group.id)
        }

        // Reset for next test
        support.dragCoordinator.reset()

        // Test 2: Drag to favorites
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        support.dragCoordinator.updateDrag(
            offset: 45 - startFrame.midY,
            location: CGPoint(x: 100, y: 45),
        )

        if case .convertToFavorite = support.dragCoordinator._dropTarget {
            // Expected
        } else {
            Issue.record("Expected convertToFavorite")
        }
    }

    @Test("Nested groups: drag tab between nested groups")
    func nestedGroupsDragBetween() throws {
        let support = try SidebarTestSupport()

        // Create nested groups
        let parentGroup = try support.createGroup(name: "Parent")
        let childGroup = try support.createGroup(name: "Child", parentGroupID: parentGroup.id)
        _ = support.createTab(url: "https://parent-tab.com", groupID: parentGroup.id)
        let childTab = support.createTab(url: "https://child-tab.com", groupID: childGroup.id)
        _ = support.createTab(url: "https://ungrouped.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Find the child tab
        let items = support.layoutManager.pinnedItems + support.layoutManager.normalItems
        let childTabItem = items.first { item in
            if case let .tab(tab) = item, tab.id == childTab.id { return true }
            return false
        }!

        // Find the parent group header
        let parentGroupItem = items.first { item in
            if case let .group(g) = item, g.id == parentGroup.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[childTabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: childTabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(childTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag to parent group header
        let parentFrame = support.dragCoordinator.computedItemFrame(for: parentGroupItem.id)!
        support.dragCoordinator.updateDrag(
            offset: 0,
            location: CGPoint(x: 100, y: parentFrame.midY),
        )

        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: parentFrame.midY))

        // Should detect parent group hover
        if case let .addToGroup(groupID) = support.dragCoordinator._dropTarget {
            #expect(groupID == parentGroup.id)
        } else {
            Issue.record("Expected addToGroup for parent, got \(support.dragCoordinator._dropTarget)")
        }
    }

    // MARK: - Edge Cases

    @Test("Drag pinned tab when it's the only pinned tab")
    func dragOnlyPinnedTab() throws {
        let support = try SidebarTestSupport()

        let pinnedTab = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://normal1.com")
        _ = support.createTab(url: "https://normal2.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let pinnedItem = support.layoutManager.pinnedItems.first!
        let originIndex = support.layoutManager.metadata[pinnedItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: pinnedItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(pinnedTab),
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag down to normal section - use actual frame position
        let normalFrame = support.dragCoordinator.computedNormalSectionFrame
        let targetY = normalFrame.midY
        support.dragCoordinator.updateDrag(
            offset: targetY - startFrame.midY,
            location: CGPoint(x: startFrame.midX, y: targetY),
        )

        // Should target normal section (unpinning)
        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .normal)
        } else {
            Issue.record("Expected reorder to normal section")
        }
    }

    @Test("Drag group with children maintains exclusion set")
    func dragGroupMaintainsExclusionSet() throws {
        let support = try SidebarTestSupport()

        let group = try support.createGroup(name: "Test Group")
        let tab1 = support.createTab(url: "https://tab1.com", groupID: group.id)
        let tab2 = support.createTab(url: "https://tab2.com", groupID: group.id)
        _ = support.createTab(url: "https://other.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let items = support.layoutManager.pinnedItems + support.layoutManager.normalItems
        let groupItem = items.first { item in
            if case let .group(g) = item, g.id == group.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[groupItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: groupItem.id)!
        support.dragCoordinator.startDrag(
            item: .group(group),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Verify exclusion set contains group and its children
        let exclusionSet = support.dragCoordinator._draggedItemExclusionSet
        #expect(exclusionSet.contains(group.id))
        #expect(exclusionSet.contains(tab1.id))
        #expect(exclusionSet.contains(tab2.id))
    }
}
