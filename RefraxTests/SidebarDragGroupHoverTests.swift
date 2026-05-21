import Foundation
import Testing

@testable import Refrax

@Suite("Sidebar.DragCoordinator Group Hover", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragGroupHoverTests {
    @Test("Group hover ignores descendant targets to avoid cycles")
    func groupHoverIgnoresDescendants() throws {
        let support = try SidebarTestSupport()
        let parent = try support.createGroup(name: "Parent")
        let child = try support.createGroup(name: "Child", parentGroupID: parent.id)

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let originIndex = support.layoutManager.metadata[parent.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: parent.id)!
        support.dragCoordinator.startDrag(
            item: .group(parent),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        let childFrame = support.dragCoordinator.computedItemFrame(for: child.id)!
        let hoverID = support.dragCoordinator.detectGroupHover(at: CGPoint(x: 10, y: childFrame.midY))

        #expect(hoverID == nil)
    }

    @Test("Dragged tab targeting group header sets addToGroup drop target")
    func draggedTabTargetingGroupHeader() throws {
        let support = try SidebarTestSupport()
        let group = try support.createGroup(name: "Group")
        let tab = support.createTab(url: "https://example.com")
        _ = support.createTab(url: "https://child.com", groupID: group.id)

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Register frames in the frame registry so getVisibleItems() can find items
        let items = support.layoutManager.pinnedItems + support.layoutManager.normalItems
        for item in items {
            if let frame = support.dragCoordinator.computedItemFrame(for: item.id) {
                support.managers.frameRegistry.setTestFrame(frame, for: item.id)
            }
        }

        let originIndex = support.layoutManager.metadata[tab.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tab.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag to group header
        let groupFrame = support.dragCoordinator.computedItemFrame(for: group.id)!
        support.dragCoordinator.updateDrag(
            offset: groupFrame.midY - startFrame.midY,
            location: CGPoint(x: groupFrame.midX, y: groupFrame.midY),
        )

        // The drop target should be addToGroup when hovering a group header
        if case let .addToGroup(groupID) = support.dragCoordinator._dropTarget {
            #expect(groupID == group.id)
        } else {
            Issue.record("Expected addToGroup target, got \(support.dragCoordinator._dropTarget)")
        }

        #expect(support.dragCoordinator.activeDropZone == .groupHeader(group.id))
    }

    @Test("Reset nesting level restores model value")
    func resetNestingRestoresModelValue() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://example.com")

        support.rebuildLayout()

        if var metadata = support.layoutManager.metadata[tab.id] {
            metadata.nestingLevel = 2
            support.layoutManager.metadata[tab.id] = metadata
        }

        let originIndex = support.layoutManager.metadata[tab.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: 100, y: 100),
        )

        support.dragCoordinator.resetDraggedItemNestingLevel()

        #expect(support.layoutManager.metadata[tab.id]?.nestingLevel == 0)
    }
}
