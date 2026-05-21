// import Foundation
//
///// Performance test extension for profiling common user interactions.
/////
///// Usage:
///// 1. Launch app with Instruments (Time Profiler, 15 second recording)
///// 2. The test sequence starts automatically 2 seconds after launch
///// 3. Completes in ~12 seconds, leaving ~3 seconds of idle for comparison
/////
///// To enable, call `schedulePerformanceTest()` from `RefraxWindowController.init`
///// or uncomment the call in `setupSplitViewController`.
// extension RefraxWindowController {
//    /// Schedules the performance test to run after app launch settles.
//    func schedulePerformanceTest() {
//        Task {
//            // Wait for app to fully launch and settle
//            try? await Task.sleep(for: .seconds(2))
//            await runPerformanceTestSequence()
//        }
//    }
//
//    /// Runs a deterministic sequence of UI operations for profiling.
//    ///
//    /// Operations tested:
//    /// - Tab switching (forces WebView loading)
//    /// - Filter changes (triggers layout rebuilds)
//    /// - Tab reordering with drag commit
//    /// - Cross-section drags (tab ↔ favorites)
//    /// - Tab renaming
//
//    private func runPerformanceTestSequence() async {
//        print("🔬 [PerfTest] Starting performance test sequence...")
//
//        guard let space = windowState.activeSpace else {
//            print("🔬 [PerfTest] ERROR: No active space")
//            return
//        }
//
//        let tabs = space.mainTabs
//        guard tabs.count >= 3 else {
//            print("🔬 [PerfTest] ERROR: Need at least 3 tabs (have \(tabs.count))")
//            return
//        }
//
//        let dragCoordinator = sidebarManagers.dragCoordinator
//        let layoutManager = sidebarManagers.layoutManager
//        let filterManager = sidebarManagers.filterManager
//
//        // MARK: - Phase 1: Rapid Tab Switching (tests WebView loading, state updates)
//
//        print("🔬 [PerfTest] Phase 1: Rapid tab switching...")
//        for i in 0 ..< min(tabs.count, 6) {
//            tabManager.setActiveTab(tabs[i], in: windowState)
//            try? await Task.sleep(for: .milliseconds(300))
//        }
//
//        // Switch back through in reverse
//        for i in stride(from: min(tabs.count - 1, 5), through: 0, by: -1) {
//            tabManager.setActiveTab(tabs[i], in: windowState)
//            try? await Task.sleep(for: .milliseconds(200))
//        }
//
//        print("🔬 [PerfTest] Phase 1 complete")
//        try? await Task.sleep(for: .milliseconds(400))
//
//        // MARK: - Phase 2: Filter Changes (triggers layout rebuilds)
//
//        print("🔬 [PerfTest] Phase 2: Filter changes...")
//
//        for i in 0 ..< 4 {
//            filterManager.searchText = "test\(i)"
//            try? await Task.sleep(for: .milliseconds(150))
//            filterManager.searchText = ""
//            try? await Task.sleep(for: .milliseconds(150))
//        }
//
//        print("🔬 [PerfTest] Phase 2 complete")
//        try? await Task.sleep(for: .milliseconds(400))
//
//        // MARK: - Phase 3: Tab Reordering with Commit
//
//        print("🔬 [PerfTest] Phase 3: Tab reordering...")
//
//        // Reorder within normal section: move tab 0 down, then back
//        if tabs.count >= 3,
//           let firstMeta = layoutManager.metadata[tabs[0].id],
//           let thirdMeta = layoutManager.metadata[tabs[2].id],
//           let firstFrame = firstMeta.frame,
//           let thirdFrame = thirdMeta.frame {
//            // Drag first tab to third position
//            let dragItem = Sidebar.DragCoordinator.DraggedItem.tab(tabs[0])
//            let startLocation = CGPoint(x: firstFrame.midX, y: firstFrame.midY)
//
//            dragCoordinator.startDrag(
//                item: dragItem,
//                originPosition: ItemPosition.from(metadata: firstMeta),
//                startLocation: startLocation,
//            )
//
//            // Animate movement
//            let startY = firstFrame.midY
//            let targetY = thirdFrame.midY + 20 // Just past third tab
//            let steps = 10
//            for step in 0 ... steps {
//                let progress = CGFloat(step) / CGFloat(steps)
//                let currentY = startY + (targetY - startY) * progress
//                let offset = currentY - startY
//                dragCoordinator.updateDrag(
//                    offset: offset,
//                    location: CGPoint(x: firstFrame.midX, y: currentY),
//                )
//                try? await Task.sleep(for: .milliseconds(30))
//            }
//
//            // Commit the reorder
//            let didReorder = dragCoordinator.commitDrag()
//            print("🔬 [PerfTest] Reorder commit: \(didReorder)")
//            try? await Task.sleep(for: .milliseconds(300))
//
//            // Wait for animation
//            dragCoordinator.reset()
//            try? await Task.sleep(for: .milliseconds(200))
//        }
//
//        print("🔬 [PerfTest] Phase 3 complete")
//        try? await Task.sleep(for: .milliseconds(400))
//
//        // MARK: - Phase 4: Cross-Section Drag (Tab to Favorites)
//
//        print("🔬 [PerfTest] Phase 4: Cross-section drags...")
//
//        // Get current tabs (may have changed after reorder)
//        let currentTabs = space.mainTabs
//
//        // Tab to Favorites: drag an unpinned tab to favorites grid area
//        if let tabToFavorite = currentTabs.first(where: { !$0.isPinned }),
//           let tabMeta = layoutManager.metadata[tabToFavorite.id],
//           let tabFrame = tabMeta.frame {
//            let dragItem = Sidebar.DragCoordinator.DraggedItem.tab(tabToFavorite)
//            let startLocation = CGPoint(x: tabFrame.midX, y: tabFrame.midY)
//
//            dragCoordinator.startDrag(
//                item: dragItem,
//                originPosition: ItemPosition.from(metadata: tabMeta),
//                startLocation: startLocation,
//            )
//
//            // Move up toward favorites grid (top of sidebar)
//            let startY = tabFrame.midY
//            let favoritesY = dragCoordinator.favoritesGridFrame.midY
//            let targetY = favoritesY > 0 ? favoritesY : 100 // Fallback if frame not set
//
//            let steps = 15
//            for step in 0 ... steps {
//                let progress = CGFloat(step) / CGFloat(steps)
//                let currentY = startY + (targetY - startY) * progress
//                dragCoordinator.updateDrag(
//                    offset: currentY - startY,
//                    location: CGPoint(x: tabFrame.midX, y: currentY),
//                )
//                try? await Task.sleep(for: .milliseconds(25))
//            }
//
//            // Commit (converts to favorite)
//            let didConvert = dragCoordinator.commitDrag()
//            print("🔬 [PerfTest] Tab to favorites: \(didConvert)")
//            dragCoordinator.reset()
//            try? await Task.sleep(for: .milliseconds(400))
//        }
//
//        // Favorites to Tab: drag a favorite back to tab list
//        if let favoriteItem = layoutManager.favoritesLayout.first(where: { $0.isDraggableToTabs }),
//           let favMeta = layoutManager.metadata[favoriteItem.id],
//           let favFrame = favMeta.frame {
//            let dragItem = Sidebar.DragCoordinator.DraggedItem.favorite(favoriteItem)
//            let startLocation = CGPoint(x: favFrame.midX, y: favFrame.midY)
//
//            dragCoordinator.startDrag(
//                item: dragItem,
//                originPosition: ItemPosition.from(metadata: favMeta),
//                startLocation: startLocation,
//            )
//
//            // Move down toward normal tab section
//            let startY = favFrame.midY
//            let normalY = dragCoordinator.normalSectionFrame.midY
//            let targetY = normalY > 0 ? normalY : startY + 300
//
//            let steps = 15
//            for step in 0 ... steps {
//                let progress = CGFloat(step) / CGFloat(steps)
//                let currentY = startY + (targetY - startY) * progress
//                dragCoordinator.updateDrag(
//                    offset: currentY - startY,
//                    location: CGPoint(x: favFrame.midX, y: currentY),
//                )
//                try? await Task.sleep(for: .milliseconds(25))
//            }
//
//            // Commit (converts to tab)
//            let didConvert = dragCoordinator.commitDrag()
//            print("🔬 [PerfTest] Favorites to tab: \(didConvert)")
//            dragCoordinator.reset()
//            try? await Task.sleep(for: .milliseconds(400))
//        }
//
//        print("🔬 [PerfTest] Phase 4 complete")
//        try? await Task.sleep(for: .milliseconds(400))
//
//        // MARK: - Phase 5: Tab Renaming (reduced)
//
//        print("🔬 [PerfTest] Phase 5: Tab renaming...")
//
//        let renameTabs = Array(space.mainTabs.prefix(2))
//        let originalNames: [Tab.ID: String?] = Dictionary(
//            uniqueKeysWithValues: renameTabs.map { ($0.id, $0.customName) },
//        )
//
//        // Rename and restore
//        for (index, tab) in renameTabs.enumerated() {
//            tab.customName = "PerfTest \(index)"
//            tabManager.state.incrementContentVersion()
//            try? await Task.sleep(for: .milliseconds(150))
//        }
//
//        for tab in renameTabs {
//            tab.customName = originalNames[tab.id] ?? nil
//            tabManager.state.incrementContentVersion()
//            try? await Task.sleep(for: .milliseconds(100))
//        }
//
//        print("🔬 [PerfTest] Phase 5 complete")
//        try? await Task.sleep(for: .milliseconds(400))
//
//        // MARK: - Phase 6: Combined Operations
//
//        print("🔬 [PerfTest] Phase 6: Combined realistic operations...")
//
//        let finalTabs = space.mainTabs
//        for i in 0 ..< 3 {
//            let tabIndex = i % finalTabs.count
//            tabManager.setActiveTab(finalTabs[tabIndex], in: windowState)
//            try? await Task.sleep(for: .milliseconds(300))
//
//            if i % 2 == 0 {
//                filterManager.searchText = "a"
//                try? await Task.sleep(for: .milliseconds(100))
//                filterManager.searchText = ""
//            }
//            try? await Task.sleep(for: .milliseconds(150))
//        }
//
//        print("🔬 [PerfTest] Phase 6 complete")
//
//        // MARK: - Completion
//
//        print("🔬 [PerfTest] ✅ Performance test sequence completed!")
//    }
//
//    /// Schedules drag overlay mode tests to debug tile↔tab transitions.
//    func scheduleDragOverlayTest() {
//        Task {
//            try? await Task.sleep(for: .seconds(3))
//            await runDragOverlayTest()
//        }
//    }
//
//    private func runDragOverlayTest() async {
//        print("🔬 [DragTest] Starting comprehensive drag test...")
//
//        guard let _ = windowState.activeSpace else {
//            print("🔬 [DragTest] ERROR: No active space")
//            return
//        }
//
//        let dragCoordinator = sidebarManagers.dragCoordinator
//        let layoutManager = sidebarManagers.layoutManager
//
//        // Wait for layout to be ready
//        try? await Task.sleep(for: .milliseconds(500))
//
//        let favorites = layoutManager.favoritesLayout
//        let pinnedItems = layoutManager.pinnedItems
//        let normalItems = layoutManager.normalItems
//
//        let draggableFavorites = favorites.filter(\.isDraggableToTabs)
//
//        print("🔬 [DragTest] Initial state:")
//        print("  Favorites: \(favorites.count) total, \(draggableFavorites.count) draggable")
//        for fav in favorites {
//            print("    - \(fav.displayName): type=\(fav.type), draggable=\(fav.isDraggableToTabs)")
//        }
//        print("  Pinned tabs: \(pinnedItems.count)")
//        print("  Normal tabs: \(normalItems.count)")
//        print("  favoritesGridFrame: \(dragCoordinator.favoritesGridFrame)")
//        print("  pinnedSectionFrame: \(dragCoordinator.pinnedSectionFrame)")
//        print("  normalSectionFrame: \(dragCoordinator.normalSectionFrame)")
//
//        guard !draggableFavorites.isEmpty else {
//            print("🔬 [DragTest] ERROR: No draggable favorites available (need liveFavorite or shortcut)")
//            return
//        }
//
//        // Helper to get item frame from metadata
//        let itemFrame: (TabListItem) -> CGRect? = { item in
//            layoutManager.metadata[item.id]?.frame
//        }
//
//        // Get actual item positions for reliable targeting
//        let pinnedFrames = pinnedItems.compactMap { itemFrame($0) }
//        let normalFrames = normalItems.compactMap { itemFrame($0) }
//
//        print("  Pinned item frames: \(pinnedFrames.map { "Y=\(Int($0.minY))" })")
//        print("  Normal item frames (first 5): \(normalFrames.prefix(5).map { "Y=\(Int($0.minY))" })")
//
//        // Test 1: Favorite → Pinned section (index 0)
//        // Target: just into the top of the first pinned item
//        if let firstPinnedFrame = pinnedFrames.first {
//            await testFavoriteToTab(
//                testName: "Favorite → Pinned[0]",
//                dragCoordinator: dragCoordinator,
//                layoutManager: layoutManager,
//                targetY: firstPinnedFrame.minY + 5,
//                expectedIsPinned: true,
//                expectedIndex: 0,
//            )
//            try? await Task.sleep(for: .seconds(1))
//        }
//
//        // Test 2: Favorite → Pinned section (index 1, between first and second)
//        if pinnedItems.count >= 2, pinnedFrames.count >= 2 {
//            // Target: just past the midpoint of first pinned item (triggers insert at 1)
//            let targetY = pinnedFrames[0].maxY + 5
//            await testFavoriteToTab(
//                testName: "Favorite → Pinned[1]",
//                dragCoordinator: dragCoordinator,
//                layoutManager: layoutManager,
//                targetY: targetY,
//                expectedIsPinned: true,
//                expectedIndex: 1,
//            )
//            try? await Task.sleep(for: .seconds(1))
//        }
//
//        // Test 3: Favorite → End of pinned (after all pinned items)
//        if let lastPinnedFrame = pinnedFrames.last {
//            // Target: below all pinned items
//            let targetY = lastPinnedFrame.maxY + 5
//            await testFavoriteToTab(
//                testName: "Favorite → Pinned[end]",
//                dragCoordinator: dragCoordinator,
//                layoutManager: layoutManager,
//                targetY: targetY,
//                expectedIsPinned: true,
//                expectedIndex: pinnedItems.count,
//            )
//            try? await Task.sleep(for: .seconds(1))
//        }
//
//        // Test 4: Favorite → Normal section (index 0)
//        // Target: just into the top of the first normal item
//        if let firstNormalFrame = normalFrames.first {
//            await testFavoriteToTab(
//                testName: "Favorite → Normal[0]",
//                dragCoordinator: dragCoordinator,
//                layoutManager: layoutManager,
//                targetY: firstNormalFrame.minY + 5,
//                expectedIsPinned: false,
//                expectedIndex: 0,
//            )
//            try? await Task.sleep(for: .seconds(1))
//        }
//
//        // Test 5: Favorite → Normal section (index 1)
//        if normalItems.count >= 2, normalFrames.count >= 2 {
//            // Target: just past the midpoint of first normal item
//            let targetY = normalFrames[0].maxY + 5
//            await testFavoriteToTab(
//                testName: "Favorite → Normal[1]",
//                dragCoordinator: dragCoordinator,
//                layoutManager: layoutManager,
//                targetY: targetY,
//                expectedIsPinned: false,
//                expectedIndex: 1,
//            )
//            try? await Task.sleep(for: .seconds(1))
//        }
//
//        // Test 6: Tab reorder within normal (move tab 0 to position 2)
//        if normalItems.count >= 3 {
//            await testTabReorder(
//                testName: "Normal[0] → Normal[2]",
//                dragCoordinator: dragCoordinator,
//                layoutManager: layoutManager,
//                sourceItem: normalItems[0],
//                targetIndex: 2,
//            )
//            try? await Task.sleep(for: .seconds(1))
//        }
//
//        print("🔬 [DragTest] ✅ All tests complete!")
//    }
//
//    private func testFavoriteToTab(
//        testName: String,
//        dragCoordinator: Sidebar.DragCoordinator,
//        layoutManager: Sidebar.LayoutManager,
//        targetY: CGFloat,
//        expectedIsPinned: Bool,
//        expectedIndex: Int,
//    ) async {
//        print("\n🔬 [DragTest] === \(testName) ===")
//
//        guard let favorite = layoutManager.favoritesLayout.first(where: { $0.isDraggableToTabs }),
//              let metadata = layoutManager.metadata[favorite.id],
//              let startFrame = metadata.frame else {
//            print("🔬 [DragTest] ERROR: No draggable favorite available (need liveFavorite or shortcut type)")
//            return
//        }
//
//        print("  Dragging: \(favorite.displayName)")
//        print("  From Y: \(Int(startFrame.midY)) → To Y: \(Int(targetY))")
//        print("  Expected: isPinned=\(expectedIsPinned), index=\(expectedIndex)")
//
//        // Start drag (use frame center as start location)
//        let startLocation = CGPoint(x: startFrame.midX, y: startFrame.midY)
//        dragCoordinator.startDrag(
//            item: .favorite(favorite),
//            originPosition: ItemPosition.from(metadata: metadata),
//            startLocation: startLocation,
//        )
//
//        // Animate to target
//        let steps = 15
//        let startY = startFrame.midY
//        for step in 1 ... steps {
//            let progress = CGFloat(step) / CGFloat(steps)
//            let currentY = startY + (targetY - startY) * progress
//            dragCoordinator.updateDrag(
//                offset: currentY - startY,
//                location: CGPoint(x: startFrame.midX, y: currentY),
//            )
//            try? await Task.sleep(for: .milliseconds(40))
//        }
//
//        // Check drop target
//        let dropTarget = dragCoordinator._dropTarget
//        print("  Final dropTarget: \(dropTarget)")
//
//        // Validate
//        var passed = true
//        if case let .convertToTab(_, targetPosition) = dropTarget {
//            let isPinned = targetPosition.collection == .pinned
//            let targetIndex = targetPosition.localIndex
//            if isPinned != expectedIsPinned {
//                print("  ❌ FAIL: isPinned mismatch - got \(isPinned), expected \(expectedIsPinned)")
//                passed = false
//            }
//            if targetIndex != expectedIndex {
//                print("  ❌ FAIL: index mismatch - got \(targetIndex), expected \(expectedIndex)")
//                passed = false
//            }
//            if passed {
//                print("  ✅ PASS: isPinned=\(isPinned), index=\(targetIndex)")
//            }
//        } else {
//            print("  ❌ FAIL: Wrong drop target type: \(dropTarget)")
//        }
//
//        // Cancel (don't actually commit)
//        dragCoordinator.reset()
//    }
//
//    private func testTabReorder(
//        testName: String,
//        dragCoordinator: Sidebar.DragCoordinator,
//        layoutManager: Sidebar.LayoutManager,
//        sourceItem: TabListItem,
//        targetIndex: Int,
//    ) async {
//        print("\n🔬 [DragTest] === \(testName) ===")
//
//        guard let metadata = layoutManager.metadata[sourceItem.id],
//              let startFrame = metadata.frame else {
//            print("🔬 [DragTest] ERROR: No frame for source item")
//            return
//        }
//
//        let itemName: String = switch sourceItem {
//        case let .tab(tab): tab.displayTitle
//        case let .group(group): group.name
//        }
//        print("  Dragging: \(itemName)")
//        print("  From index: \(metadata.globalIndex) → To index: \(targetIndex)")
//
//        // Calculate target Y based on target index
//        let slotHeight = Constants.Layout.tabItemHeight + Constants.Layout.tabSpacing
//        let targetY = startFrame.minY + CGFloat(targetIndex - metadata.globalIndex + layoutManager.favoritesLayout.count) * slotHeight
//
//        // Start drag (use frame center as start location)
//        let dragItem: Sidebar.DragCoordinator.DraggedItem = switch sourceItem {
//        case let .tab(tab): .tab(tab)
//        case let .group(group): .group(group)
//        }
//        let startLocation = CGPoint(x: startFrame.midX, y: startFrame.midY)
//
//        dragCoordinator.startDrag(
//            item: dragItem,
//            originPosition: ItemPosition.from(metadata: metadata),
//            startLocation: startLocation,
//        )
//
//        // Animate to target
//        let steps = 15
//        let startY = startFrame.midY
//        for step in 1 ... steps {
//            let progress = CGFloat(step) / CGFloat(steps)
//            let currentY = startY + (targetY - startY) * progress
//            dragCoordinator.updateDrag(
//                offset: currentY - startY,
//                location: CGPoint(x: startFrame.midX, y: currentY),
//            )
//            try? await Task.sleep(for: .milliseconds(40))
//        }
//
//        // Check result
//        let dropTarget = dragCoordinator._dropTarget
//        print("  Final dropTarget: \(dropTarget)")
//        print("  Items pushed: \(dragCoordinator.itemPushOffsets.count)")
//
//        // Cancel
//        dragCoordinator.reset()
//    }
// }
