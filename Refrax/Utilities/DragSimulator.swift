// import Foundation
// import OSLog
// import SwiftUI
//
// #if DEBUG
//
//    /// Debug utility for simulating drag operations to test the DragCoordinator logic.
//    ///
//    /// This simulator bypasses SwiftUI gestures and directly calls DragCoordinator methods
//    /// to test drag and drop logic between sections (favorites, pinned, normal).
//    ///
//    /// ## Usage
//    ///
//    /// Add to app launch or call manually:
//    /// ```swift
//    /// DragSimulator.shared.runTestSequence(
//    ///     dragCoordinator: sidebarManagers.dragCoordinator,
//    ///     layoutManager: sidebarManagers.layoutManager
//    /// )
//    /// ```
//    final class DragSimulator {
//        static let shared = DragSimulator()
//
//        private let log = OSLog(subsystem: Constants.App.bundleID, category: "drag-simulator")
//
//        private init() {}
//
//        // MARK: - Test Sequences
//
//        /// Runs a predefined test sequence after a delay to allow views to render.
//        func runTestSequence(
//            dragCoordinator: Sidebar.DragCoordinator,
//            layoutManager: Sidebar.LayoutManager,
//            delay: TimeInterval = 2.0,
//        ) {
//            logInfo("DragSimulator: Scheduling test sequence in \(delay) seconds...")
//            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
//                self?.waitForContentAndRun(
//                    dragCoordinator: dragCoordinator,
//                    layoutManager: layoutManager,
//                )
//            }
//        }
//
//        /// Runs the test sequence repeatedly until content is available.
//        private func waitForContentAndRun(
//            dragCoordinator: Sidebar.DragCoordinator,
//            layoutManager: Sidebar.LayoutManager,
//            attempt: Int = 0,
//        ) {
//            guard attempt < 10 else {
//                logError("Gave up waiting for content after \(attempt) attempts")
//                return
//            }
//
//            if layoutManager.normalItems.isEmpty, layoutManager.pinnedItems.isEmpty {
//                logInfo("DragSimulator: No content yet (attempt \(attempt)), retrying in 1s...")
//                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
//                    self?.waitForContentAndRun(
//                        dragCoordinator: dragCoordinator,
//                        layoutManager: layoutManager,
//                        attempt: attempt + 1,
//                    )
//                }
//                return
//            }
//
//            executeTestSequence(dragCoordinator: dragCoordinator, layoutManager: layoutManager)
//        }
//
//        private func executeTestSequence(
//            dragCoordinator: Sidebar.DragCoordinator,
//            layoutManager: Sidebar.LayoutManager,
//        ) {
//            logHeader("DRAG SIMULATOR TEST SEQUENCE")
//
//            // Log initial state
//            logFrameState(dragCoordinator: dragCoordinator, layoutManager: layoutManager)
//
//            // Test 1: Drag normal tab to pinned section
//            if let normalTab = layoutManager.normalItems.first?.tab {
//                logTest("Test 1: Dragging normal tab '\(normalTab.customName ?? "tab")' to pinned section")
//                simulateDragNormalToPinned(
//                    tab: normalTab,
//                    dragCoordinator: dragCoordinator,
//                    layoutManager: layoutManager,
//                )
//
//                // Test 2: After Test 1 completes, drag a pinned tab to normal section
//                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
//                    self?.runTest2PinnedToNormal(
//                        dragCoordinator: dragCoordinator,
//                        layoutManager: layoutManager,
//                    )
//                }
//            } else {
//                logWarning("No normal tabs available for testing")
//            }
//        }
//
//        private func runTest2PinnedToNormal(
//            dragCoordinator: Sidebar.DragCoordinator,
//            layoutManager: Sidebar.LayoutManager,
//        ) {
//            logHeader("TEST 2: PINNED TO NORMAL")
//
//            // Re-fetch state after Test 1
//            logFrameState(dragCoordinator: dragCoordinator, layoutManager: layoutManager)
//
//            // Get a pinned tab (not the original pinned one, but the one we just pinned)
//            if layoutManager.pinnedItems.count > 1,
//               let pinnedTab = layoutManager.pinnedItems.last?.tab {
//                logTest("Test 2: Dragging pinned tab '\(pinnedTab.customName ?? "tab")' to normal section")
//                simulateDragPinnedToNormal(
//                    tab: pinnedTab,
//                    dragCoordinator: dragCoordinator,
//                    layoutManager: layoutManager,
//                )
//            } else if let pinnedTab = layoutManager.pinnedItems.first?.tab {
//                // Fallback: use the first pinned tab
//                logTest("Test 2: Dragging pinned tab '\(pinnedTab.customName ?? "tab")' to normal section")
//                simulateDragPinnedToNormal(
//                    tab: pinnedTab,
//                    dragCoordinator: dragCoordinator,
//                    layoutManager: layoutManager,
//                )
//            } else {
//                logWarning("No pinned tabs available for Test 2")
//            }
//        }
//
//        /// Simulates dragging a pinned tab to the normal section (unpin).
//        func simulateDragPinnedToNormal(
//            tab: Tab,
//            dragCoordinator: Sidebar.DragCoordinator,
//            layoutManager: Sidebar.LayoutManager,
//        ) {
//            guard let metadata = layoutManager.metadata[tab.id] else {
//                logError("No metadata for tab \(tab.id)")
//                return
//            }
//
//            guard let originalFrame = metadata.frame else {
//                logError("No frame captured for tab \(tab.id)")
//                return
//            }
//
//            logInfo("Starting drag (pinned to normal):")
//            logInfo("  - Tab ID: \(tab.id)")
//            logInfo("  - Tab isPinned: \(tab.isPinned)")
//            logInfo("  - Original frame: \(formatRect(originalFrame))")
//            logInfo("  - Global index: \(metadata.globalIndex)")
//            logInfo("  - Collection: \(metadata.collection)")
//
//            // Start the drag (use frame center as start location)
//            let startLocation = CGPoint(x: originalFrame.midX, y: originalFrame.midY)
//            dragCoordinator.startDrag(
//                item: .tab(tab),
//                originPosition: ItemPosition.from(metadata: metadata),
//                startLocation: startLocation,
//            )
//
//            logInfo("After startDrag:")
//            logInfo("  - draggedItem: \(String(describing: dragCoordinator.primaryDraggedItem?.id))")
//            logInfo("  - originPosition: \(String(describing: dragCoordinator.debugOriginPosition))")
//
//            // Simulate dragging downward toward normal section
//            let normalFrame = dragCoordinator.normalSectionFrame
//
//            logInfo("Target frames:")
//            logInfo("  - normalSectionFrame (raw): \(formatRect(normalFrame))")
//
//            // Calculate target location (middle of normal section)
//            let targetY: CGFloat = if !normalFrame.isEmpty {
//                normalFrame.midY
//            } else {
//                // No normal section - target below pinned section
//                originalFrame.maxY + 100
//            }
//
//            let targetLocation = CGPoint(x: originalFrame.midX, y: targetY)
//            let verticalOffset = targetY - originalFrame.midY
//
//            logInfo("Drag movement:")
//            logInfo("  - Target location: \(formatPoint(targetLocation))")
//            logInfo("  - Vertical offset: \(verticalOffset)")
//
//            // Perform drag updates in steps to simulate gradual movement
//            let steps = 10
//            for step in 1 ... steps {
//                let progress = CGFloat(step) / CGFloat(steps)
//                let currentOffset = verticalOffset * progress
//                let currentLocation = CGPoint(
//                    x: originalFrame.midX,
//                    y: originalFrame.midY + currentOffset,
//                )
//
//                dragCoordinator.updateDrag(offset: currentOffset, location: currentLocation)
//
//                if step == steps {
//                    logInfo("Final drag state (step \(step)):")
//                    logInfo("  - currentOffset: \(dragCoordinator.currentOffset)")
//                    logInfo("  - dropTarget: \(dragCoordinator.debugDropTarget)")
//                    logInfo("  - activeDropZone: \(String(describing: dragCoordinator.activeDropZone))")
//                }
//            }
//
//            // Log drop target before commit
//            logInfo("Pre-commit state:")
//            logInfo("  - dropTarget: \(dragCoordinator.debugDropTarget)")
//            logInfo("  - Expected: reorder to normal section")
//
//            // Commit the drag
//            let success = dragCoordinator.commitDrag()
//            logInfo("Commit result: \(success ? "SUCCESS" : "FAILED")")
//
//            // Log final state
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
//                self?.logInfo("Post-commit state:")
//                self?.logInfo("  - Tab isPinned: \(tab.isPinned)")
//                self?.logInfo("  - Tab position: \(tab.position)")
//                if let newMetadata = layoutManager.metadata[tab.id] {
//                    self?.logInfo("  - New collection: \(newMetadata.collection)")
//                }
//            }
//        }
//
//        // MARK: - Simulation Methods
//
//        /// Simulates dragging a normal tab to the pinned section.
//        func simulateDragNormalToPinned(
//            tab: Tab,
//            dragCoordinator: Sidebar.DragCoordinator,
//            layoutManager: Sidebar.LayoutManager,
//        ) {
//            guard let metadata = layoutManager.metadata[tab.id] else {
//                logError("No metadata for tab \(tab.id)")
//                return
//            }
//
//            guard let originalFrame = metadata.frame else {
//                logError("No frame captured for tab \(tab.id)")
//                return
//            }
//
//            logInfo("Starting drag:")
//            logInfo("  - Tab ID: \(tab.id)")
//            logInfo("  - Original frame: \(formatRect(originalFrame))")
//            logInfo("  - Global index: \(metadata.globalIndex)")
//            logInfo("  - Collection: \(metadata.collection)")
//
//            // Start the drag (use frame center as start location)
//            let startLocation = CGPoint(x: originalFrame.midX, y: originalFrame.midY)
//            dragCoordinator.startDrag(
//                item: .tab(tab),
//                originPosition: ItemPosition.from(metadata: metadata),
//                startLocation: startLocation,
//            )
//
//            logInfo("After startDrag:")
//            logInfo("  - draggedItem: \(String(describing: dragCoordinator.primaryDraggedItem?.id))")
//            logInfo("  - originPosition: \(String(describing: dragCoordinator.debugOriginPosition))")
//
//            // Simulate dragging upward toward pinned section
//            let pinnedFrame = dragCoordinator.pinnedSectionFrame
//            let adjustedPinnedFrame = pinnedFrame.offsetBy(dx: 0, dy: dragCoordinator.tabListPushOffset)
//
//            logInfo("Target frames:")
//            logInfo("  - pinnedSectionFrame (raw): \(formatRect(pinnedFrame))")
//            logInfo("  - adjustedPinnedFrame: \(formatRect(adjustedPinnedFrame))")
//            logInfo("  - tabListPushOffset: \(dragCoordinator.tabListPushOffset)")
//
//            // Calculate target location (center of pinned section)
//            let targetY: CGFloat = if !adjustedPinnedFrame.isEmpty {
//                adjustedPinnedFrame.midY
//            } else {
//                // No pinned section - target above normal section
//                originalFrame.minY - 100
//            }
//
//            let targetLocation = CGPoint(x: originalFrame.midX, y: targetY)
//            let verticalOffset = targetY - originalFrame.midY
//
//            logInfo("Drag movement:")
//            logInfo("  - Target location: \(formatPoint(targetLocation))")
//            logInfo("  - Vertical offset: \(verticalOffset)")
//
//            // Perform drag updates in steps to simulate gradual movement
//            let steps = 10
//            for step in 1 ... steps {
//                let progress = CGFloat(step) / CGFloat(steps)
//                let currentOffset = verticalOffset * progress
//                let currentLocation = CGPoint(
//                    x: originalFrame.midX,
//                    y: originalFrame.midY + currentOffset,
//                )
//
//                dragCoordinator.updateDrag(offset: currentOffset, location: currentLocation)
//
//                if step == steps {
//                    logInfo("Final drag state (step \(step)):")
//                    logInfo("  - currentOffset: \(dragCoordinator.currentOffset)")
//                    logInfo("  - dropTarget: \(dragCoordinator.debugDropTarget)")
//                    logInfo("  - activeDropZone: \(String(describing: dragCoordinator.activeDropZone))")
//                    logInfo("  - dropZoneProgress: \(dragCoordinator.dropZoneProgress)")
//                    logInfo("  - tabListPushOffset: \(dragCoordinator.tabListPushOffset)")
//                }
//            }
//
//            // Log drop target before commit
//            logInfo("Pre-commit state:")
//            logInfo("  - dropTarget: \(dragCoordinator.debugDropTarget)")
//            logInfo("  - Expected: reorder to pinned section")
//
//            // Commit the drag
//            let success = dragCoordinator.commitDrag()
//            logInfo("Commit result: \(success ? "SUCCESS" : "FAILED")")
//
//            // Log final state
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
//                self?.logInfo("Post-commit state:")
//                self?.logInfo("  - Tab isPinned: \(tab.isPinned)")
//                self?.logInfo("  - Tab position: \(tab.position)")
//                if let newMetadata = layoutManager.metadata[tab.id] {
//                    self?.logInfo("  - New collection: \(newMetadata.collection)")
//                }
//            }
//        }
//
//        /// Simulates dragging a favorite to the normal section.
//        func simulateDragFavoriteToNormal(
//            favorite: FavoriteItem,
//            dragCoordinator: Sidebar.DragCoordinator,
//            layoutManager: Sidebar.LayoutManager,
//        ) {
//            guard let metadata = layoutManager.metadata[favorite.id] else {
//                logError("No metadata for favorite \(favorite.id)")
//                return
//            }
//
//            logInfo("Starting favorite drag:")
//            logInfo("  - Favorite ID: \(favorite.id)")
//            logInfo("  - Global index: \(metadata.globalIndex)")
//
//            // For favorites, we don't have a frame in metadata typically
//            // Use the favorites grid frame as reference
//            let gridFrame = dragCoordinator.favoritesGridFrame
//            let startLocation = CGPoint(x: gridFrame.midX, y: gridFrame.midY)
//
//            dragCoordinator.startDrag(
//                item: .favorite(favorite),
//                originPosition: ItemPosition.from(metadata: metadata),
//                startLocation: startLocation,
//            )
//
//            logInfo("After startDrag for favorite:")
//            logInfo("  - draggedItem: \(String(describing: dragCoordinator.primaryDraggedItem?.id))")
//            logInfo("  - favoritesGridFrame: \(formatRect(gridFrame))")
//
//            // Target the normal section
//            let normalFrame = dragCoordinator.normalSectionFrame
//            let adjustedNormalFrame = normalFrame.offsetBy(dx: 0, dy: dragCoordinator.tabListPushOffset)
//
//            let targetY: CGFloat = if !adjustedNormalFrame.isEmpty {
//                adjustedNormalFrame.midY
//            } else {
//                gridFrame.maxY + 200
//            }
//
//            let targetLocation = CGPoint(x: gridFrame.midX, y: targetY)
//            let verticalOffset = targetY - startLocation.y
//
//            logInfo("Drag movement to normal section:")
//            logInfo("  - Start: \(formatPoint(startLocation))")
//            logInfo("  - Target: \(formatPoint(targetLocation))")
//            logInfo("  - normalSectionFrame (raw): \(formatRect(normalFrame))")
//            logInfo("  - adjustedNormalFrame: \(formatRect(adjustedNormalFrame))")
//
//            // Simulate gradual drag
//            let steps = 10
//            for step in 1 ... steps {
//                let progress = CGFloat(step) / CGFloat(steps)
//                let currentOffset = verticalOffset * progress
//                let currentLocation = CGPoint(
//                    x: startLocation.x,
//                    y: startLocation.y + currentOffset,
//                )
//
//                dragCoordinator.updateDrag(offset: currentOffset, location: currentLocation)
//
//                if step == steps {
//                    logInfo("Final drag state:")
//                    logInfo("  - dropTarget: \(dragCoordinator.debugDropTarget)")
//                    logInfo("  - activeDropZone: \(String(describing: dragCoordinator.activeDropZone))")
//                }
//            }
//
//            let success = dragCoordinator.commitDrag()
//            logInfo("Commit result: \(success ? "SUCCESS" : "FAILED")")
//        }
//
//        /// Simulates a tab being dragged to favorites, then back to tabs without release.
//        /// This tests the overlay mode transition hysteresis.
//        func simulateTabToFavoritesAndBack(
//            tab: Tab,
//            dragCoordinator: Sidebar.DragCoordinator,
//            layoutManager: Sidebar.LayoutManager,
//        ) {
//            guard let metadata = layoutManager.metadata[tab.id],
//                  let originalFrame = metadata.frame else {
//                logError("No frame for tab \(tab.id)")
//                return
//            }
//
//            logHeader("TAB → FAVORITES → TAB ROUND TRIP TEST")
//            logInfo("Tab: \(tab.displayTitle)")
//            logInfo("Original frame: \(formatRect(originalFrame))")
//
//            let favoritesFrame = dragCoordinator.favoritesGridFrame
//            let normalFrame = dragCoordinator.normalSectionFrame
//
//            logInfo("favoritesGridFrame: \(formatRect(favoritesFrame))")
//            logInfo("normalSectionFrame: \(formatRect(normalFrame))")
//            logInfo("sidebarBounds: \(formatRect(dragCoordinator.sidebarBounds))")
//
//            // Start drag (use frame center as start location)
//            let startLocation = CGPoint(x: originalFrame.midX, y: originalFrame.midY)
//            dragCoordinator.startDrag(
//                item: .tab(tab),
//                originPosition: ItemPosition.from(metadata: metadata),
//                startLocation: startLocation,
//            )
//
//            logInfo("Initial overlayMode: \(dragCoordinator.currentOverlayMode)")
//
//            // Phase 1: Drag up into favorites
//            logTest("Phase 1: Moving UP into favorites zone")
//            let favoritesTargetY = favoritesFrame.midY
//            let startY = originalFrame.midY
//            let upSteps = 20
//
//            for step in 1 ... upSteps {
//                let progress = CGFloat(step) / CGFloat(upSteps)
//                let currentY = startY + (favoritesTargetY - startY) * progress
//                let offset = currentY - startY
//                let location = CGPoint(x: originalFrame.midX, y: currentY)
//
//                dragCoordinator.updateDrag(offset: offset, location: location)
//
//                // Log at key points
//                if step == upSteps / 2 || step == upSteps {
//                    logInfo("  Step \(step): Y=\(Int(currentY)), zone=\(String(describing: dragCoordinator.activeDropZone)), mode=\(dragCoordinator.currentOverlayMode)")
//                }
//            }
//
//            logInfo("At favorites: zone=\(String(describing: dragCoordinator.activeDropZone)), mode=\(dragCoordinator.currentOverlayMode)")
//
//            // Phase 2: Drag back down to tabs
//            logTest("Phase 2: Moving DOWN back to tabs zone")
//            let tabsTargetY = normalFrame.midY > 0 ? normalFrame.midY : originalFrame.midY + 50
//            let downSteps = 20
//            let currentAtFavorites = favoritesTargetY
//
//            for step in 1 ... downSteps {
//                let progress = CGFloat(step) / CGFloat(downSteps)
//                let currentY = currentAtFavorites + (tabsTargetY - currentAtFavorites) * progress
//                let offset = currentY - startY
//                let location = CGPoint(x: originalFrame.midX, y: currentY)
//
//                dragCoordinator.updateDrag(offset: offset, location: location)
//
//                // Log transitions
//                if step == downSteps / 4 || step == downSteps / 2 || step == 3 * downSteps / 4 || step == downSteps {
//                    logInfo("  Step \(step): Y=\(Int(currentY)), zone=\(String(describing: dragCoordinator.activeDropZone)), mode=\(dragCoordinator.currentOverlayMode)")
//                }
//            }
//
//            logInfo("At tabs: zone=\(String(describing: dragCoordinator.activeDropZone)), mode=\(dragCoordinator.currentOverlayMode)")
//            logInfo("Expected: mode should be .tabRow, but may be delayed")
//
//            // Cancel without commit
//            dragCoordinator.reset()
//            logInfo("Test complete (cancelled drag)")
//        }
//
//        /// Simulates a favorite being dragged to tabs.
//        /// Tests overlay mode transition and width calculation.
//        func simulateFavoriteToTabs(
//            favorite: FavoriteItem,
//            dragCoordinator: Sidebar.DragCoordinator,
//            layoutManager: Sidebar.LayoutManager,
//        ) {
//            guard let metadata = layoutManager.metadata[favorite.id] else {
//                logError("No metadata for favorite")
//                return
//            }
//
//            guard !dragCoordinator.favoritesGridFrame.isEmpty else {
//                logError("No favorites grid frame")
//                return
//            }
//
//            logHeader("FAVORITE → TABS TEST")
//            logInfo("Favorite: \(favorite.displayName)")
//
//            let useFrame = metadata.frame ?? CGRect(
//                x: dragCoordinator.favoritesGridFrame.minX + 40,
//                y: dragCoordinator.favoritesGridFrame.minY + 40,
//                width: 80, height: 80,
//            )
//            logInfo("Using frame: \(formatRect(useFrame))")
//
//            // Start drag (use frame center as start location)
//            let startLocation = CGPoint(x: useFrame.midX, y: useFrame.midY)
//            dragCoordinator.startDrag(
//                item: .favorite(favorite),
//                originPosition: ItemPosition.from(metadata: metadata),
//                startLocation: startLocation,
//            )
//
//            logInfo("Initial overlayMode: \(dragCoordinator.currentOverlayMode)")
//            logInfo("sidebarBounds width: \(dragCoordinator.sidebarBounds.width)")
//
//            // Drag down to normal section
//            let normalFrame = dragCoordinator.normalSectionFrame
//            let pinnedFrame = dragCoordinator.pinnedSectionFrame
//            let targetY = !pinnedFrame.isEmpty ? pinnedFrame.midY : (!normalFrame.isEmpty ? normalFrame.midY : useFrame.maxY + 100)
//
//            logTest("Dragging down to Y=\(Int(targetY))")
//
//            let startY = useFrame.midY
//            let steps = 15
//
//            for step in 1 ... steps {
//                let progress = CGFloat(step) / CGFloat(steps)
//                let currentY = startY + (targetY - startY) * progress
//                let offset = currentY - startY
//                let location = CGPoint(x: useFrame.midX, y: currentY)
//
//                dragCoordinator.updateDrag(offset: offset, location: location)
//
//                if step == steps / 2 || step == steps {
//                    logInfo("  Step \(step): Y=\(Int(currentY)), zone=\(String(describing: dragCoordinator.activeDropZone)), mode=\(dragCoordinator.currentOverlayMode), dropTarget=\(dragCoordinator.debugDropTarget)")
//                }
//            }
//
//            logInfo("Final: zone=\(String(describing: dragCoordinator.activeDropZone)), mode=\(dragCoordinator.currentOverlayMode)")
//
//            // Cancel
//            dragCoordinator.reset()
//            logInfo("Test complete")
//        }
//
//        // MARK: - Logging Helpers
//
//        private func debugPrint(_ message: String) {
//            // Use FileHandle for unbuffered output
//            if let data = (message + "\n").data(using: .utf8) {
//                FileHandle.standardError.write(data)
//            }
//        }
//
//        private func logHeader(_ message: String) {
//            let separator = String(repeating: "=", count: 60)
//            debugPrint("🔧 \(separator)")
//            debugPrint("🔧 \(message)")
//            debugPrint("🔧 \(separator)")
//        }
//
//        private func logTest(_ message: String) {
//            debugPrint("🔧 [TEST] \(message)")
//        }
//
//        private func logInfo(_ message: String) {
//            debugPrint("🔧   \(message)")
//        }
//
//        private func logWarning(_ message: String) {
//            debugPrint("🔧 [WARN] \(message)")
//        }
//
//        private func logError(_ message: String) {
//            debugPrint("🔧 [ERROR] \(message)")
//        }
//
//        func logFrameState(
//            dragCoordinator: Sidebar.DragCoordinator,
//            layoutManager: Sidebar.LayoutManager,
//        ) {
//            logInfo("Current Frame State:")
//            logInfo("  - favoritesGridFrame: \(formatRect(dragCoordinator.favoritesGridFrame))")
//            logInfo("  - pinnedSectionFrame: \(formatRect(dragCoordinator.pinnedSectionFrame))")
//            logInfo("  - normalSectionFrame: \(formatRect(dragCoordinator.normalSectionFrame))")
//            logInfo("  - tabListPushOffset: \(dragCoordinator.tabListPushOffset)")
//
//            logInfo("Layout Manager State:")
//            logInfo("  - favoritesLayout.count: \(layoutManager.favoritesLayout.count)")
//            logInfo("  - pinnedItems.count: \(layoutManager.pinnedItems.count)")
//            logInfo("  - normalItems.count: \(layoutManager.normalItems.count)")
//
//            // Log first few items with their frames
//            logInfo("Pinned Items Metadata:")
//            for (index, item) in layoutManager.pinnedItems.prefix(3).enumerated() {
//                if let metadata = layoutManager.metadata[item.id] {
//                    let frameStr = metadata.frame.map { formatRect($0) } ?? "nil"
//                    logInfo("  [\(index)] \(item.id): frame=\(frameStr)")
//                }
//            }
//
//            logInfo("Normal Items Metadata:")
//            for (index, item) in layoutManager.normalItems.prefix(3).enumerated() {
//                if let metadata = layoutManager.metadata[item.id] {
//                    let frameStr = metadata.frame.map { formatRect($0) } ?? "nil"
//                    logInfo("  [\(index)] \(item.id): frame=\(frameStr)")
//                }
//            }
//        }
//
//        private func formatRect(_ rect: CGRect) -> String {
//            String(format: "(x:%.1f, y:%.1f, w:%.1f, h:%.1f)", rect.minX, rect.minY, rect.width, rect.height)
//        }
//
//        private func formatPoint(_ point: CGPoint) -> String {
//            String(format: "(x:%.1f, y:%.1f)", point.x, point.y)
//        }
//    }
//
//    // MARK: - DropTarget CustomStringConvertible
//
//    extension Sidebar.DragCoordinator.DropTarget: CustomStringConvertible {
//        public var description: String {
//            switch self {
//            case .none:
//                ".none"
//            case let .reorder(target):
//                ".reorder(target: \(target))"
//            case let .convertToFavorite(mode):
//                ".convertToFavorite(mode: \(mode))"
//            case let .convertToTab(_, targetPosition):
//                ".convertToTab(targetPosition: \(targetPosition))"
//            case let .addToGroup(groupID):
//                ".addToGroup(\(groupID))"
//            case let .nestGroup(parentID):
//                ".nestGroup(\(parentID))"
//            }
//        }
//    }
//
// #endif
