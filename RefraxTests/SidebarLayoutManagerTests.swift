import Foundation
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for Sidebar.LayoutManager operations.
    @Tag static var sidebarLayoutManager: Self
}

// MARK: - CollectionBounds Tests

@Suite("Sidebar.LayoutManager CollectionBounds", .tags(.sidebarLayoutManager))
@MainActor
struct CollectionBoundsTests {
    @Test("Empty bounds have zero ranges")
    func emptyBounds() {
        let bounds = Sidebar.LayoutManager.CollectionBounds(
            favorites: 0 ..< 0,
            pinned: 0 ..< 0,
            normal: 0 ..< 0,
        )

        #expect(bounds.favorites.isEmpty)
        #expect(bounds.pinned.isEmpty)
        #expect(bounds.normal.isEmpty)
    }

    @Test("Collection for index returns correct collection")
    func collectionForIndex() {
        let bounds = Sidebar.LayoutManager.CollectionBounds(
            favorites: 0 ..< 3,
            pinned: 3 ..< 5,
            normal: 5 ..< 10,
        )

        #expect(bounds.collection(for: 0) == .favorites)
        #expect(bounds.collection(for: 2) == .favorites)
        #expect(bounds.collection(for: 3) == .pinned)
        #expect(bounds.collection(for: 4) == .pinned)
        #expect(bounds.collection(for: 5) == .normal)
        #expect(bounds.collection(for: 9) == .normal)
    }

    @Test("Collection for index returns nil for out of range")
    func collectionForIndexOutOfRange() {
        let bounds = Sidebar.LayoutManager.CollectionBounds(
            favorites: 0 ..< 3,
            pinned: 3 ..< 5,
            normal: 5 ..< 10,
        )

        #expect(bounds.collection(for: 10) == nil)
        #expect(bounds.collection(for: 100) == nil)
    }
}

// MARK: - ItemMetadata Tests

@Suite("Sidebar.LayoutManager ItemMetadata", .tags(.sidebarLayoutManager))
@MainActor
struct ItemMetadataTests {
    @Test("Metadata is Equatable")
    func metadataEquatable() {
        let metadata1 = Sidebar.LayoutManager.ItemMetadata(
            collection: .normal,
            indexInCollection: 0,
            globalIndex: 5,
            nestingLevel: 0,
            parentGroupID: nil,
            topPadding: 0,
        )

        let metadata2 = Sidebar.LayoutManager.ItemMetadata(
            collection: .normal,
            indexInCollection: 0,
            globalIndex: 5,
            nestingLevel: 0,
            parentGroupID: nil,
            topPadding: 0,
        )

        #expect(metadata1 == metadata2)
    }

    @Test("Metadata with different values is not equal")
    func metadataDifferent() {
        let metadata1 = Sidebar.LayoutManager.ItemMetadata(
            collection: .normal,
            indexInCollection: 0,
            globalIndex: 5,
            nestingLevel: 0,
            parentGroupID: nil,
            topPadding: 0,
        )

        let metadata2 = Sidebar.LayoutManager.ItemMetadata(
            collection: .pinned,
            indexInCollection: 0,
            globalIndex: 5,
            nestingLevel: 0,
            parentGroupID: nil,
            topPadding: 0,
        )

        #expect(metadata1 != metadata2)
    }

    @Test("Metadata stores nesting level")
    func metadataNestingLevel() {
        var metadata = Sidebar.LayoutManager.ItemMetadata(
            collection: .normal,
            indexInCollection: 2,
            globalIndex: 7,
            nestingLevel: 3,
            parentGroupID: UUID(),
            topPadding: 8,
        )

        #expect(metadata.nestingLevel == 3)

        metadata.nestingLevel = 5
        #expect(metadata.nestingLevel == 5)
    }

    @Test("Metadata stores parent group ID")
    func metadataParentGroupID() {
        let parentID = UUID()
        let metadata = Sidebar.LayoutManager.ItemMetadata(
            collection: .normal,
            indexInCollection: 0,
            globalIndex: 0,
            nestingLevel: 1,
            parentGroupID: parentID,
            topPadding: 0,
        )

        #expect(metadata.parentGroupID == parentID)
    }
}

// MARK: - LayoutManager Initialization Tests

@Suite("Sidebar.LayoutManager Initialization", .tags(.sidebarLayoutManager))
@MainActor
struct LayoutManagerInitializationTests {
    @Test("Initial collections are empty")
    func initialCollectionsEmpty() {
        let manager = Sidebar.LayoutManager()

        #expect(manager.favoritesLayout.isEmpty)
        #expect(manager.pinnedItems.isEmpty)
        #expect(manager.normalItems.isEmpty)
    }

    @Test("Initial bounds are empty")
    func initialBoundsEmpty() {
        let manager = Sidebar.LayoutManager()

        #expect(manager.collectionBounds.favorites.isEmpty)
        #expect(manager.collectionBounds.pinned.isEmpty)
        #expect(manager.collectionBounds.normal.isEmpty)
    }

    @Test("Initial metadata is empty")
    func initialMetadataEmpty() {
        let manager = Sidebar.LayoutManager()

        #expect(manager.metadata.isEmpty)
    }
}

// MARK: - Notes

//
// Sidebar.LayoutManager functionality requiring integration tests:
//
// 1. rebuildLayout: Requires wired dependencies (tabManager, filterManager, etc.)
// 2. buildMetadata: Requires populated collections
// 3. dragOffset calculations: Requires active drag state
// 4. descendant cache: Requires group hierarchy
//
// The tests above verify:
// - CollectionBounds correctly maps indices to collections
// - ItemMetadata is equatable and stores expected values
// - Initial state is empty (no collections, bounds, or metadata)
//
// Full layout testing requires:
// - Complete SidebarManagers wiring
// - Tab data with groups and nesting
// - Filter state for filtered layouts
//
