import Foundation
import SwiftData
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for data model integrity invariants.
    @Tag static var dataIntegrity: Self

    /// Tests for SwiftData relationship behavior.
    @Tag static var relationships: Self

    /// Tests for cascade delete behavior.
    @Tag static var cascadeDelete: Self
}

// MARK: - Tab Tests

@Suite("Tab Data Integrity", .tags(.dataIntegrity), .serialized)
@MainActor
struct TabTests {
    /// In-memory model container for testing.
    let container: ModelContainer

    init() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Tab always has at least one page after initialization")
    func tabHasPageAfterInit() throws {
        let tab = Tab(space: nil, url: URL(string: "https://example.com")!)

        #expect(tab.pages.count >= 1, "Tab must have at least one page")
        #expect(tab.pages.first != nil, "First page must exist")
    }

    @Test("Tab.activePage returns first page without creating ephemeral objects")
    func activePageReturnsExistingPage() throws {
        let tab = Tab(space: nil, url: URL(string: "https://example.com")!)
        let firstPage = tab.pages.first!

        let activePage = tab.activePage

        #expect(activePage.id == firstPage.id, "activePage should return the existing first page")
    }

    @Test(
        "Tab initialization with various URLs",
        arguments: [
            "https://example.com",
            "https://apple.com/swift",
            "file:///local/path",
            "about:blank",
        ],
    )
    func tabInitializationWithURLs(urlString: String) throws {
        let url = URL(string: urlString)!
        let tab = Tab(space: nil, url: url)

        #expect(tab.activePage.url == url)
        #expect(tab.pages.count == 1)
    }

    @Test(
        "Tab status types",
        arguments: TabStatus.allCases,
    )
    @MainActor
    func tabStatusTypes(status: TabStatus) throws {
        let tab = Tab(space: nil, status: status)

        #expect(tab.status == status)

        // Verify cleanup exemption logic
        switch status {
        case .regular:
            #expect(!status.isExemptFromCleanup)
        case .pinned, .liveFavorite:
            #expect(status.isExemptFromCleanup)
        }
    }
}

// MARK: - TabPage Tests

@Suite("TabPage Data Integrity", .tags(.dataIntegrity), .serialized)
@MainActor
struct TabPageTests {
    let container: ModelContainer

    init() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try ModelContainer(for: schema, configurations: [config])
    }

    @Test("TabPage.tab is set via inverse relationship when added to Tab")
    @MainActor
    func tabPageInverseRelationship() throws {
        let context = container.mainContext

        let space = Space(name: "Test", iconName: "star", colorHex: "#007AFF", position: 0)
        context.insert(space)

        let tab = Tab(space: space, url: URL(string: "https://example.com")!)
        context.insert(tab)

        // The page created in Tab.init should have its tab set
        let page = tab.activePage

        // After insertion, SwiftData should establish the inverse relationship
        try context.save()

        #expect(page.tab != nil, "TabPage.tab should be set via inverse relationship")
        #expect(page.tab?.id == tab.id, "TabPage.tab should reference the correct Tab")
    }

    @Test("TabPage.parentTab provides non-optional access")
    @MainActor
    func parentTabAccessor() throws {
        let context = container.mainContext

        let space = Space(name: "Test", iconName: "star", colorHex: "#007AFF", position: 0)
        context.insert(space)

        let tab = Tab(space: space, url: URL(string: "https://example.com")!)
        context.insert(tab)
        try context.save()

        let page = tab.activePage

        // parentTab should not throw when tab relationship is established
        let parentTab = page.parentTab
        #expect(parentTab.id == tab.id)
    }

    @Test(
        "TabPage layout positions",
        arguments: [
            PanePosition.single,
            PanePosition.topLeft,
            PanePosition.topRight,
            PanePosition.bottomLeft,
            PanePosition.bottomRight,
        ],
    )
    func tabPageLayoutPositions(position: PanePosition) throws {
        let page = TabPage(url: URL(string: "https://example.com")!, layoutPosition: position)

        #expect(page.position == position)
        #expect(page.layoutPosition == position.rawValue)
    }
}

// MARK: - Bookmark Relationship Tests

@Suite("Bookmark Relationships", .tags(.relationships), .serialized)
@MainActor
struct BookmarkRelationshipTests {
    let container: ModelContainer

    init() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Tab.linkedBookmark creates bidirectional relationship")
    @MainActor
    func linkedBookmarkBidirectional() throws {
        let context = container.mainContext

        let bookmark = Bookmark(url: URL(string: "https://example.com")!, title: "Example")
        context.insert(bookmark)

        let tab = Tab(
            space: nil, // Live favorites don't belong to a space
            url: bookmark.url,
            title: bookmark.title,
            status: .liveFavorite,
            linkedBookmark: bookmark,
        )
        context.insert(tab)

        try context.save()

        // Verify bidirectional relationship
        #expect(tab.linkedBookmark?.id == bookmark.id)
        #expect(bookmark.linkedTab?.id == tab.id)
    }

    @Test("Deleting bookmark nullifies Tab.linkedBookmark")
    @MainActor
    func deleteBookmarkNullifiesTabLink() throws {
        let context = container.mainContext

        let bookmark = Bookmark(url: URL(string: "https://example.com")!, title: "Example")
        context.insert(bookmark)

        let tab = Tab(
            space: nil, // Live favorites don't belong to a space
            url: bookmark.url,
            status: .liveFavorite,
            linkedBookmark: bookmark,
        )
        context.insert(tab)

        try context.save()

        // Capture tab ID before deletion
        let tabID = tab.id

        // Delete the bookmark
        context.delete(bookmark)
        try context.save()

        // Fetch the tab again to verify relationship was nullified
        let descriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.id == tabID })
        let fetchedTab = try context.fetch(descriptor).first

        #expect(fetchedTab != nil, "Tab should still exist after bookmark deletion")
        #expect(fetchedTab?.linkedBookmark == nil, "linkedBookmark should be nullified")
    }
}

// MARK: - Space Relationship Tests

@Suite("Space Relationships", .tags(.relationships), .serialized)
@MainActor
struct SpaceRelationshipTests {
    let container: ModelContainer

    init() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Tab.space creates bidirectional relationship")
    @MainActor
    func tabSpaceBidirectional() throws {
        let context = container.mainContext

        let space = Space(
            name: "Test Space",
            iconName: "star",
            colorHex: "#007AFF",
            position: 0,
        )
        context.insert(space)

        let tab = Tab(space: space, url: URL(string: "https://example.com")!)
        context.insert(tab)

        try context.save()

        // Verify bidirectional relationship
        #expect(tab.space?.id == space.id)
        #expect(space.tabs.contains { $0.id == tab.id })
    }

    @Test("Space.mainTabs filters non-reference tabs")
    @MainActor
    func mainTabsFiltering() throws {
        let context = container.mainContext

        let space = Space(name: "Test", iconName: "star", colorHex: "#007AFF", position: 0)
        context.insert(space)

        let mainTab = Tab(space: space, url: URL(string: "https://main.com")!)
        context.insert(mainTab)

        let refTab = Tab(space: space, url: URL(string: "https://ref.com")!, isReferenceTab: true)
        context.insert(refTab)

        try context.save()

        #expect(space.mainTabs.count == 1)
        #expect(space.mainTabs.first?.id == mainTab.id)
        #expect(space.referenceTabs.count == 1)
        #expect(space.referenceTabs.first?.id == refTab.id)
    }

    @Test("TabGroup.space creates bidirectional relationship")
    @MainActor
    func tabGroupSpaceBidirectional() throws {
        let context = container.mainContext

        let space = Space(name: "Test", iconName: "star", colorHex: "#007AFF", position: 0)
        context.insert(space)

        let group = TabGroup(space: space, name: "Test Group")
        context.insert(group)

        try context.save()

        #expect(group.space?.id == space.id)
        #expect(space.groups.contains { $0.id == group.id })
    }
}

// MARK: - Cascade Delete Tests

@Suite("Cascade Delete Behavior", .tags(.cascadeDelete), .serialized)
@MainActor
struct CascadeDeleteTests {
    let container: ModelContainer

    init() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Deleting Tab cascades to TabPages")
    @MainActor
    func deleteTabCascadesToPages() throws {
        let context = container.mainContext

        let tab = Tab(space: nil, url: URL(string: "https://example.com")!)
        context.insert(tab)

        let pageID = tab.activePage.id

        try context.save()

        // Delete the tab
        context.delete(tab)
        try context.save()

        // Verify page was also deleted
        let descriptor = FetchDescriptor<TabPage>(predicate: #Predicate { $0.id == pageID })
        let pages = try context.fetch(descriptor)

        #expect(pages.isEmpty, "TabPage should be cascade deleted with Tab")
    }

    @Test("Deleting Space cascades to Tabs and TabGroups")
    @MainActor
    func deleteSpaceCascadesToTabsAndGroups() throws {
        let context = container.mainContext

        let space = Space(name: "Test", iconName: "star", colorHex: "#007AFF", position: 0)
        context.insert(space)

        let tab = Tab(space: space, url: URL(string: "https://example.com")!)
        context.insert(tab)

        let group = TabGroup(space: space, name: "Test Group")
        context.insert(group)

        let tabID = tab.id
        let groupID = group.id

        try context.save()

        // Delete the space
        context.delete(space)
        try context.save()

        // Verify tab was deleted
        let tabDescriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.id == tabID })
        let tabs = try context.fetch(tabDescriptor)
        #expect(tabs.isEmpty, "Tab should be cascade deleted with Space")

        // Verify group was deleted
        let groupDescriptor = FetchDescriptor<TabGroup>(predicate: #Predicate { $0.id == groupID })
        let groups = try context.fetch(groupDescriptor)
        #expect(groups.isEmpty, "TabGroup should be cascade deleted with Space")
    }

    @Test("Deleting BookmarkFolder cascades to bookmarks")
    @MainActor
    func deleteFolderCascadesToBookmarks() throws {
        let context = container.mainContext

        let folder = BookmarkFolder(name: "Test Folder")
        context.insert(folder)

        let bookmark = Bookmark(url: URL(string: "https://example.com")!, folder: folder)
        context.insert(bookmark)
        folder.bookmarks.append(bookmark)

        let bookmarkID = bookmark.id

        try context.save()

        // Delete the folder
        context.delete(folder)
        try context.save()

        // Verify bookmark was also deleted
        let descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == bookmarkID })
        let bookmarks = try context.fetch(descriptor)

        #expect(bookmarks.isEmpty, "Bookmark should be cascade deleted with folder")
    }

    @Test("Deleting BookmarkFolder cascades to child folders")
    @MainActor
    func deleteFolderCascadesToChildFolders() throws {
        let context = container.mainContext

        let parentFolder = BookmarkFolder(name: "Parent")
        context.insert(parentFolder)

        let childFolder = BookmarkFolder(name: "Child", parent: parentFolder)
        context.insert(childFolder)
        parentFolder.childFolders.append(childFolder)

        let childFolderID = childFolder.id

        try context.save()

        // Delete the parent folder
        context.delete(parentFolder)
        try context.save()

        // Verify child folder was also deleted
        let descriptor = FetchDescriptor<BookmarkFolder>(
            predicate: #Predicate { $0.id == childFolderID },
        )
        let folders = try context.fetch(descriptor)

        #expect(folders.isEmpty, "Child folder should be cascade deleted with parent")
    }

    @Test("Nested folder cascade delete includes all descendants")
    @MainActor
    func nestedFolderCascadeDelete() throws {
        let context = container.mainContext

        // Create hierarchy: Root → Child → Grandchild + Bookmarks at each level
        let root = BookmarkFolder(name: "Root")
        context.insert(root)

        let child = BookmarkFolder(name: "Child", parent: root)
        context.insert(child)
        root.childFolders.append(child)

        let grandchild = BookmarkFolder(name: "Grandchild", parent: child)
        context.insert(grandchild)
        child.childFolders.append(grandchild)

        let rootBookmark = Bookmark(url: URL(string: "https://root.com")!, folder: root)
        context.insert(rootBookmark)
        root.bookmarks.append(rootBookmark)

        let childBookmark = Bookmark(url: URL(string: "https://child.com")!, folder: child)
        context.insert(childBookmark)
        child.bookmarks.append(childBookmark)

        let grandchildBookmark = Bookmark(
            url: URL(string: "https://grandchild.com")!,
            folder: grandchild,
        )
        context.insert(grandchildBookmark)
        grandchild.bookmarks.append(grandchildBookmark)

        // Capture IDs
        let childID = child.id
        let grandchildID = grandchild.id
        let rootBookmarkID = rootBookmark.id
        let childBookmarkID = childBookmark.id
        let grandchildBookmarkID = grandchildBookmark.id

        try context.save()

        // Delete root folder
        context.delete(root)
        try context.save()

        // Verify everything was deleted
        let folderDescriptor = FetchDescriptor<BookmarkFolder>(
            predicate: #Predicate { $0.id == childID || $0.id == grandchildID },
        )
        let remainingFolders = try context.fetch(folderDescriptor)
        #expect(remainingFolders.isEmpty, "All descendant folders should be deleted")

        let bookmarkDescriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate {
                $0.id == rootBookmarkID || $0.id == childBookmarkID || $0.id == grandchildBookmarkID
            },
        )
        let remainingBookmarks = try context.fetch(bookmarkDescriptor)
        #expect(remainingBookmarks.isEmpty, "All descendant bookmarks should be deleted")
    }
}

// MARK: - Schema Version Tests

@Suite("Schema Versioning", .tags(.dataIntegrity), .serialized)
@MainActor
struct SchemaVersionTests {
    @Test("SchemaV1 contains all required models")
    func schemaV1ContainsAllModels() {
        let models = SchemaV1.models

        // Core tab models
        #expect(models.contains { $0 == Tab.self })
        #expect(models.contains { $0 == TabPage.self })
        #expect(models.contains { $0 == Space.self })
        #expect(models.contains { $0 == TabGroup.self })

        // History models
        #expect(models.contains { $0 == HistoryEntry.self })
        #expect(models.contains { $0 == BrowsingContext.self })

        // Bookmark models
        #expect(models.contains { $0 == Bookmark.self })
        #expect(models.contains { $0 == BookmarkFolder.self })

        // Settings models
        #expect(models.contains { $0 == BrowserSettings.self })
        #expect(models.contains { $0 == SiteSettings.self })

        // Other models
        #expect(models.contains { $0 == CachedFavicon.self })
        #expect(models.contains { $0 == Download.self })
    }

    @Test("SchemaV1 version identifier is correct")
    func schemaV1VersionIdentifier() {
        let version = SchemaV1.versionIdentifier

        #expect(version.major == 1)
        #expect(version.minor == 0)
        #expect(version.patch == 0)
    }

    @Test("RefraxMigrationPlan includes SchemaV1")
    func migrationPlanIncludesSchemaV1() {
        let schemas = RefraxMigrationPlan.schemas

        #expect(schemas.count >= 1)
        #expect(schemas.contains { $0 == SchemaV1.self })
    }
}
